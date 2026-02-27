locals {
    is_fargate = var.launch_type == "FARGATE"
}

resource "aws_ecr_repository" "ecr_repository" {
    name                 = var.name_ecr
    image_tag_mutability = "MUTABLE"
    force_delete         = true

    image_scanning_configuration {
        scan_on_push = true
    }
}

resource "aws_ecs_cluster" "ecs_cluster" {
    name = var.name_cluster_ecs

    setting {
        name  = "containerInsights"
        value = "enabled"
    }

    tags = {
        ENV     = "PROD"
        SERVICE = upper(var.name_main)
    }
}

resource "aws_cloudwatch_log_group" "ecs_tasks" {
    name = "/ecs/tasks-logs${var.name_main}"
}

resource "aws_ecs_task_definition" "task_definition" {
    family = var.name_tasks_ecs

    # EC2: solo requiere EC2. FARGATE: requiere FARGATE
    requires_compatibilities = [var.launch_type]

    # cpu y memory a nivel de task son obligatorios en Fargate, opcionales en EC2
    cpu    = local.is_fargate ? var.task_cpu : null
    memory = local.is_fargate ? var.task_memory : null

    execution_role_arn = "arn:aws:iam::${var.account_id}:role/ecsTaskExecutionRole"
    network_mode       = "awsvpc"

    container_definitions = templatefile(var.container_path, {
        NAME_MAIN             = var.name_main
        REPOSITORY_URL        = aws_ecr_repository.ecr_repository.repository_url
        CLOUDWATCH_LOG_GROUP  = aws_cloudwatch_log_group.ecs_tasks.name
        AWSLOGS_STREAM_PREFIX = "ecs"
    })
}

resource "aws_ecs_service" "ecs_service" {
    name            = "service_${var.name_main}"
    cluster         = aws_ecs_cluster.ecs_cluster.id
    task_definition = aws_ecs_task_definition.task_definition.arn
    desired_count   = 1
    launch_type     = var.launch_type

    health_check_grace_period_seconds  = 0
    deployment_minimum_healthy_percent = 100
    deployment_maximum_percent         = 200

    # Las placement strategies solo son compatibles con EC2, no con Fargate
    dynamic "ordered_placement_strategy" {
        for_each = local.is_fargate ? [] : [
            { type = "spread", field = "attribute:ecs.availability-zone" },
            { type = "spread", field = "instanceId" }
        ]
        content {
            type  = ordered_placement_strategy.value.type
            field = ordered_placement_strategy.value.field
        }
    }

    network_configuration {
        subnets          = var.subnets
        security_groups  = [var.ec2_security_group_id]
        # En EC2 siempre false. En Fargate depende de si hay NAT gateway o no
        assign_public_ip = local.is_fargate ? var.assign_public_ip : false
    }

    load_balancer {
        target_group_arn = var.target_group_arn
        container_name   = "container_${var.name_main}"
        container_port   = 80
    }

    lifecycle {
        ignore_changes = [desired_count]
    }
}

# ─── Application Auto Scaling (funciona igual para EC2 y Fargate) ─────────────

resource "aws_appautoscaling_target" "ecs_target" {
    max_capacity       = 10
    min_capacity       = 1
    resource_id        = "service/${aws_ecs_cluster.ecs_cluster.name}/${aws_ecs_service.ecs_service.name}"
    scalable_dimension = "ecs:service:DesiredCount"
    service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "scale_up" {
    name               = "ecs-scale-up-${var.name_main}"
    policy_type        = "StepScaling"
    resource_id        = aws_appautoscaling_target.ecs_target.resource_id
    scalable_dimension = aws_appautoscaling_target.ecs_target.scalable_dimension
    service_namespace  = aws_appautoscaling_target.ecs_target.service_namespace

    step_scaling_policy_configuration {
        adjustment_type         = "ChangeInCapacity"
        cooldown                = 30
        metric_aggregation_type = "Maximum"

        step_adjustment {
            metric_interval_upper_bound = 0
            scaling_adjustment          = 1
        }
    }
}

resource "aws_appautoscaling_policy" "scale_down" {
    name               = "ecs-scale-down-${var.name_main}"
    policy_type        = "StepScaling"
    resource_id        = aws_appautoscaling_target.ecs_target.resource_id
    scalable_dimension = aws_appautoscaling_target.ecs_target.scalable_dimension
    service_namespace  = aws_appautoscaling_target.ecs_target.service_namespace

    step_scaling_policy_configuration {
        adjustment_type         = "ChangeInCapacity"
        cooldown                = 60
        metric_aggregation_type = "Maximum"

        step_adjustment {
            metric_interval_upper_bound = 0
            scaling_adjustment          = -1
        }
    }
}

# ─── CloudWatch Alarms ECS (funcionan igual para EC2 y Fargate) ───────────────

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
    alarm_name          = "ecs-cpu-high-${var.name_main}"
    comparison_operator = "GreaterThanOrEqualToThreshold"
    evaluation_periods  = 1
    metric_name         = "CPUUtilization"
    namespace           = "AWS/ECS"
    period              = 60
    statistic           = "Average"
    unit                = "Percent"
    threshold           = 75

    dimensions = {
        ClusterName = aws_ecs_cluster.ecs_cluster.name
        ServiceName = aws_ecs_service.ecs_service.name
    }

    alarm_actions = [aws_appautoscaling_policy.scale_up.arn]
}

resource "aws_cloudwatch_metric_alarm" "cpu_low" {
    alarm_name          = "ecs-cpu-low-${var.name_main}"
    comparison_operator = "LessThanOrEqualToThreshold"
    evaluation_periods  = 2
    metric_name         = "CPUUtilization"
    namespace           = "AWS/ECS"
    period              = 240
    statistic           = "Average"
    unit                = "Percent"
    threshold           = 10

    dimensions = {
        ClusterName = aws_ecs_cluster.ecs_cluster.name
        ServiceName = aws_ecs_service.ecs_service.name
    }

    alarm_actions = [aws_appautoscaling_policy.scale_down.arn]
}

resource "aws_cloudwatch_metric_alarm" "memory_high" {
    alarm_name          = "ecs-memory-high-${var.name_main}"
    comparison_operator = "GreaterThanOrEqualToThreshold"
    evaluation_periods  = 1
    metric_name         = "MemoryUtilization"
    namespace           = "AWS/ECS"
    period              = 60
    statistic           = "Average"
    unit                = "Percent"
    threshold           = 75

    dimensions = {
        ClusterName = aws_ecs_cluster.ecs_cluster.name
        ServiceName = aws_ecs_service.ecs_service.name
    }

    alarm_actions = [aws_appautoscaling_policy.scale_up.arn]
}

resource "aws_cloudwatch_metric_alarm" "memory_low" {
    alarm_name          = "ecs-memory-low-${var.name_main}"
    comparison_operator = "LessThanOrEqualToThreshold"
    evaluation_periods  = 2
    metric_name         = "MemoryUtilization"
    namespace           = "AWS/ECS"
    period              = 240
    statistic           = "Average"
    unit                = "Percent"
    threshold           = 10

    dimensions = {
        ClusterName = aws_ecs_cluster.ecs_cluster.name
        ServiceName = aws_ecs_service.ecs_service.name
    }

    alarm_actions = [aws_appautoscaling_policy.scale_down.arn]
}

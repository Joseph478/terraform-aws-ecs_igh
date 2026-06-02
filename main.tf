locals {
    is_fargate  = var.launch_type == "FARGATE"
    app_port    = var.type_project == "django" ? 8000 : 80
    common_tags = merge(var.tags, {
        ENV     = "PROD"
        SERVICE = upper(var.name_main)
    })
}

resource "aws_ecr_repository" "ecr_repository" {
    name                 = var.name_ecr
    image_tag_mutability = "MUTABLE"
    force_delete         = true

    image_scanning_configuration {
        scan_on_push = true
    }

    tags = local.common_tags

    lifecycle {
        ignore_changes = [tags["ORDEN"], tags["Name"]]
    }
}

resource "aws_ecs_cluster" "ecs_cluster" {
    name = var.name_cluster_ecs

    setting {
        name  = "containerInsights"
        value = var.container_insights
    }

    tags = local.common_tags

    lifecycle {
        ignore_changes = [tags["ORDEN"], tags["Name"]]
    }
}

resource "aws_cloudwatch_log_group" "ecs_tasks" {
    name = "/ecs/tasks-logs${var.name_main}"

    tags = local.common_tags

    lifecycle {
        ignore_changes = [tags["ORDEN"], tags["Name"]]
    }
}

# Task Role — permisos que usa el contenedor en tiempo de ejecución (ECS Exec, SSM, etc.)
resource "aws_iam_role" "ecs_task_role" {
    name = "ecsTaskRole-${var.name_main}"

    assume_role_policy = jsonencode({
        Version = "2012-10-17"
        Statement = [{
            Effect    = "Allow"
            Principal = { Service = "ecs-tasks.amazonaws.com" }
            Action    = "sts:AssumeRole"
        }]
    })

    tags = local.common_tags

    lifecycle {
        ignore_changes = [tags["ORDEN"], tags["Name"]]
    }
}

resource "aws_iam_role_policy" "ecs_exec_policy" {
    name = "ecs-exec-ssm-${var.name_main}"
    role = aws_iam_role.ecs_task_role.id

    policy = jsonencode({
        Version = "2012-10-17"
        Statement = [{
            Effect = "Allow"
            Action = [
                "ssmmessages:CreateControlChannel",
                "ssmmessages:CreateDataChannel",
                "ssmmessages:OpenControlChannel",
                "ssmmessages:OpenDataChannel"
            ]
            Resource = "*"
        }]
    })
}

resource "aws_ecs_task_definition" "task_definition" {
    family = var.name_tasks_ecs

    # EC2: solo requiere EC2. FARGATE: requiere FARGATE
    requires_compatibilities = [var.launch_type]

    # cpu y memory a nivel de task son obligatorios en Fargate, opcionales en EC2
    cpu    = local.is_fargate ? var.task_cpu : null
    memory = local.is_fargate ? var.task_memory : null

    execution_role_arn = "arn:aws:iam::${var.account_id}:role/ecsTaskExecutionRole"
    task_role_arn      = aws_iam_role.ecs_task_role.arn
    network_mode       = "awsvpc"

    container_definitions = templatefile(var.container_path, {
        NAME_MAIN             = var.name_main
        REPOSITORY_URL        = aws_ecr_repository.ecr_repository.repository_url
        CLOUDWATCH_LOG_GROUP  = aws_cloudwatch_log_group.ecs_tasks.name
        AWSLOGS_STREAM_PREFIX = "ecs"
        SECRETS               = jsonencode(var.secrets)
        ENVIRONMENT_VARS      = jsonencode(var.environment_vars)
        TASK_CPU              = var.task_cpu
        TASK_MEMORY           = var.task_memory
    })

    tags = local.common_tags

    lifecycle {
        ignore_changes = [tags["ORDEN"], tags["Name"]]
    }
}

resource "aws_ecs_service" "ecs_service" {
    name            = "service_${var.name_main}"
    cluster         = aws_ecs_cluster.ecs_cluster.id
    task_definition = aws_ecs_task_definition.task_definition.arn
    desired_count           = var.desired_count
    launch_type             = var.launch_type
    enable_execute_command  = true

    health_check_grace_period_seconds  = var.health_check_grace_period_seconds
    deployment_minimum_healthy_percent = var.deployment_minimum_healthy_percent
    deployment_maximum_percent         = var.deployment_maximum_percent

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
        container_port   = local.app_port
    }

    lifecycle {
        ignore_changes = [desired_count, tags["ORDEN"], tags["Name"]]
    }

    tags = local.common_tags
}

# ─── Application Auto Scaling (funciona igual para EC2 y Fargate) ─────────────

resource "aws_appautoscaling_target" "ecs_target" {
    max_capacity       = var.max_capacity
    min_capacity       = var.min_capacity
    resource_id        = "service/${aws_ecs_cluster.ecs_cluster.name}/${aws_ecs_service.ecs_service.name}"
    scalable_dimension = "ecs:service:DesiredCount"
    service_namespace  = "ecs"

    tags = local.common_tags

    lifecycle {
        ignore_changes = [tags["ORDEN"], tags["Name"]]
    }
}

resource "aws_appautoscaling_policy" "scale_up" {
    name               = "ecs-scale-up-${var.name_main}"
    policy_type        = "StepScaling"
    resource_id        = aws_appautoscaling_target.ecs_target.resource_id
    scalable_dimension = aws_appautoscaling_target.ecs_target.scalable_dimension
    service_namespace  = aws_appautoscaling_target.ecs_target.service_namespace

    step_scaling_policy_configuration {
        adjustment_type         = "ChangeInCapacity"
        cooldown                = var.autoscaling_scale_up_cooldown
        metric_aggregation_type = "Average"

        step_adjustment {
            metric_interval_lower_bound = 0
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
        cooldown                = var.autoscaling_scale_down_cooldown
        metric_aggregation_type = "Average"

        step_adjustment {
            metric_interval_upper_bound = 0
            scaling_adjustment          = -1
        }
    }
}

# ─── CloudWatch Alarms ECS (funcionan igual para EC2 y Fargate) ───────────────

# Una sola alarma para scale_up: MAX(cpu/cpu_threshold, mem/mem_threshold) >= 1.0
# Equivale a "CPU >= cpu_threshold OR memoria >= mem_threshold".
# Normalizar permite umbrales distintos sin múltiples alarmas en la misma política.
resource "aws_cloudwatch_metric_alarm" "scale_up" {
    alarm_name          = "ecs-scale-up-${var.name_main}"
    comparison_operator = "GreaterThanOrEqualToThreshold"
    evaluation_periods  = 1
    threshold           = 1.0

    metric_query {
        id          = "cpu"
        return_data = false
        metric {
            metric_name = "CPUUtilization"
            namespace   = "AWS/ECS"
            period      = 60
            stat        = "Average"
            dimensions = {
                ClusterName = aws_ecs_cluster.ecs_cluster.name
                ServiceName = aws_ecs_service.ecs_service.name
            }
        }
    }

    metric_query {
        id          = "mem"
        return_data = false
        metric {
            metric_name = "MemoryUtilization"
            namespace   = "AWS/ECS"
            period      = 60
            stat        = "Average"
            dimensions = {
                ClusterName = aws_ecs_cluster.ecs_cluster.name
                ServiceName = aws_ecs_service.ecs_service.name
            }
        }
    }

    metric_query {
        id          = "combined"
        expression  = "MAX([cpu/${var.autoscaling_cpu_scale_up_threshold}, mem/${var.autoscaling_memory_scale_up_threshold}])"
        label       = "Normalized Max CPU or Memory"
        return_data = true
    }

    alarm_actions = [aws_appautoscaling_policy.scale_up.arn]

    tags = local.common_tags

    lifecycle {
        ignore_changes = [tags["ORDEN"], tags["Name"]]
    }
}

# Una sola alarma para scale_down: MAX(cpu, mem) <= umbral
# Equivale a "CPU baja Y memoria baja" sin necesitar composite alarm.
# Evita el warning de múltiples alarmas en la misma política.
resource "aws_cloudwatch_metric_alarm" "scale_down" {
    alarm_name          = "ecs-scale-down-${var.name_main}"
    comparison_operator = "LessThanOrEqualToThreshold"
    evaluation_periods  = 2
    threshold           = var.autoscaling_scale_down_threshold

    metric_query {
        id          = "cpu"
        return_data = false
        metric {
            metric_name = "CPUUtilization"
            namespace   = "AWS/ECS"
            period      = var.autoscaling_scale_down_period
            stat        = "Average"
            dimensions = {
                ClusterName = aws_ecs_cluster.ecs_cluster.name
                ServiceName = aws_ecs_service.ecs_service.name
            }
        }
    }

    metric_query {
        id          = "mem"
        return_data = false
        metric {
            metric_name = "MemoryUtilization"
            namespace   = "AWS/ECS"
            period      = var.autoscaling_scale_down_period
            stat        = "Average"
            dimensions = {
                ClusterName = aws_ecs_cluster.ecs_cluster.name
                ServiceName = aws_ecs_service.ecs_service.name
            }
        }
    }

    metric_query {
        id          = "combined"
        expression  = "MAX([cpu, mem])"
        label       = "Max CPU or Memory"
        return_data = true
    }

    alarm_actions = [aws_appautoscaling_policy.scale_down.arn]

    tags = local.common_tags

    lifecycle {
        ignore_changes = [tags["ORDEN"], tags["Name"]]
    }
}

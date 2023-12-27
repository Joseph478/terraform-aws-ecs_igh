
# resource "random_string" "cluster" {
#     length  = 8
#     lower   = false
#     special = false

#     keepers = {
#         name    = var.name_main
#         environ = var.vpc_id
#     }
# }

resource "aws_ecr_repository" "ecr_repository" {
    name                 = var.name_ecr
    image_tag_mutability = "MUTABLE"
    force_delete = true
    image_scanning_configuration {
        scan_on_push = true
    }
    # FALTA LA ENCRIPTACION
}

# resource "null_resource" "docker_push" {

#     triggers = {
#         ecr_repo = aws_ecr_repository.ecr_repository.name
#     }

#     provisioner "local-exec" {
#         command = <<-EOT
#         aws ecr get-login-password --region us-east-1 | \
#         docker login --username AWS --password-stdin ${aws_ecr_repository.ecr_repository.registry_id}.dkr.ecr.us-east-1.amazonaws.com

#         docker pull nginx
#         docker tag nginx ${aws_ecr_repository.ecr_repository.repository_url}:latest
#         docker push ${aws_ecr_repository.ecr_repository.repository_url}:latest
#         EOT
#     }

#     depends_on = [aws_ecr_repository.ecr_repository]
# }

resource "aws_ecs_cluster" "ecs_cluster" {
    name = var.name_cluster_ecs

    setting {
        name  = "containerInsights"
        value = "enabled"
    }
    tags = {
        ENV = "PROD"
        SERVICE     = upper(var.name_main)
    }
}

resource "aws_cloudwatch_log_group" "ecs_tasks" {
    name = "/ecs/tasks-logs${var.name_main}"
}

resource "aws_ecs_task_definition" "task_definition" {
    family = var.name_tasks_ecs
    requires_compatibilities = ["EC2"]

    container_definitions = templatefile(var.container_path,{
        NAME_MAIN               = var.name_main
        REPOSITORY_URL          = aws_ecr_repository.ecr_repository.repository_url
        CLOUDWATCH_LOG_GROUP    = aws_cloudwatch_log_group.ecs_tasks.name
    })
    
    execution_role_arn = "arn:aws:iam::348484763444:role/ecsTaskExecutionRole"
    network_mode = "awsvpc"
    
}

resource "aws_ecs_service" "ecs_service" {
    name            = "service_${var.name_main}"
    cluster         = aws_ecs_cluster.ecs_cluster.id
    task_definition = aws_ecs_task_definition.task_definition.arn
    desired_count   = 1
    launch_type     = "EC2"
    # iam_role        = aws_iam_role.foo.arn
    # depends_on      = [aws_iam_role_policy.foo]
    health_check_grace_period_seconds = 0
    deployment_minimum_healthy_percent = 100
    deployment_maximum_percent = 200
    
    ordered_placement_strategy {
        type  = "spread"
        field = "attribute:ecs.availability-zone"
    }
    ordered_placement_strategy {
        type  = "spread"
        field = "instanceId"
    }
    network_configuration {
        subnets = var.subnets
        security_groups = [var.ec2_security_group_id]
        assign_public_ip = false
    }
    load_balancer {
        # elb_name = var.elb_name
        target_group_arn = var.target_group_arn
        container_name   = "container_${var.name_main}"
        container_port   = 80
    }
    lifecycle {
        ignore_changes = [desired_count]
    }
}

resource "aws_appautoscaling_target" "ecs_target" {
    max_capacity       = 10
    min_capacity       = 1
    role_arn = "arn:aws:iam::348484763444:role/ecsAutoscaleRole"
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
        cooldown                = 60
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

# Alarmas por CPU 
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
    alarm_name = "ecs-cpu-high-${var.name_main}"
    comparison_operator = "GreaterThanOrEqualToThreshold"
    evaluation_periods = 2
    metric_name = "CPUUtilization" 
    namespace = "AWS/ECS"
    period = 120
    statistic = "Average"
    unit = "Percent"
    # threshold = 70

    dimensions = {
        ClusterName = aws_ecs_cluster.ecs_cluster.name
        ServiceName = aws_ecs_service.ecs_service.name
    }

    alarm_actions = [aws_appautoscaling_policy.scale_up.arn]
}

resource "aws_cloudwatch_metric_alarm" "cpu_low" {
    alarm_name = "ecs-cpu-low-${var.name_main}"
    comparison_operator = "LessThanOrEqualToThreshold"
    evaluation_periods = 2
    metric_name = "CPUUtilization" 
    namespace = "AWS/ECS"
    period = 120
    statistic = "Average"
    unit = "Percent"
    # threshold = 30

    dimensions = {
        ClusterName = aws_ecs_cluster.ecs_cluster.name
        ServiceName = aws_ecs_service.ecs_service.name
    }

    alarm_actions = [aws_appautoscaling_policy.scale_down.arn]
}

# Alarmas por MEMORY 
resource "aws_cloudwatch_metric_alarm" "memory_high" {
    alarm_name = "ecs-memory-high-${var.name_main}"
    comparison_operator = "GreaterThanOrEqualToThreshold"
    evaluation_periods = 2
    metric_name = "MemoryUtilization" 
    namespace = "AWS/ECS"
    period = 120
    statistic = "Average"
    unit = "Percent"
    # threshold = 70

    dimensions = {
        ClusterName = aws_ecs_cluster.ecs_cluster.name
        ServiceName = aws_ecs_service.ecs_service.name
    }

    alarm_actions = [aws_appautoscaling_policy.scale_up.arn]
}
resource "aws_cloudwatch_metric_alarm" "memory_low" {
    alarm_name = "ecs-memory-low-${var.name_main}"
    comparison_operator = "LessThanOrEqualToThreshold"
    evaluation_periods = 2
    metric_name = "MemoryUtilization" 
    namespace = "AWS/ECS"
    period = 120
    statistic = "Average"
    unit = "Percent"
    # threshold = 30 

    dimensions = {
        ClusterName = aws_ecs_cluster.ecs_cluster.name
        ServiceName = aws_ecs_service.ecs_service.name
    }

    alarm_actions = [aws_appautoscaling_policy.scale_down.arn]
}
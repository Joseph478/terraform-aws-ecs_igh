variable "name_main" {
    description = "Name of the ECS"
    type        = string
}
variable "name_cluster_ecs" {
    description = "Name of the ECS cluster"
    type        = string
}
variable "name_ecr" {
    description = "Name of the ECR repository"
    type        = string
}
variable "name_service_ecs" {
    description = "Name of the ECS service"
    type        = string
}
variable "name_tasks_ecs" {
    description = "Name of the task definition"
    type        = string
}
variable "vpc_id" {
    description = "VPC id"
    type        = string
}
variable "target_group_arn" {
    description = "Target Group ARN from the load balancer"
    type        = string
}
variable "account_id" {
    description = "AWS account id"
    type        = string
}
variable "subnets" {
    description = "Subnets for ECS tasks/instances"
    type        = list(string)
}
variable "elb_name" {
    description = "Load Balancer name"
    type        = string
}
variable "ec2_security_group_id" {
    description = "Security group ID for EC2 instances or Fargate tasks"
    type        = string
}
variable "region" {
    default     = "us-east-1"
    description = "AWS region"
    type        = string
}
variable "container_path" {
    description = "Path to the container definition JSON template"
    type        = string
}
variable "launch_type" {
    default     = "EC2"
    description = "ECS launch type. Allowed values: 'EC2', 'FARGATE'"
    type        = string

    validation {
        condition     = contains(["EC2", "FARGATE"], var.launch_type)
        error_message = "launch_type must be 'EC2' or 'FARGATE'."
    }
}
variable "task_cpu" {
    default     = "512"
    description = "CPU units for the task definition. Required for Fargate. Valid Fargate values: 256, 512, 1024, 2048, 4096"
    type        = string
}
variable "task_memory" {
    default     = "1024"
    description = "Memory (MB) for the task definition. Required for Fargate. Must be a valid combination with task_cpu"
    type        = string
}
variable "assign_public_ip" {
    default     = false
    description = "Assign public IP to Fargate tasks. Set to true if tasks run in public subnets without NAT gateway"
    type        = bool
}

variable "secrets" {
    default     = []
    description = "List of SSM Parameter Store or Secrets Manager secrets to inject into the container. Each item must have {name, valueFrom}"
    type = list(object({
        name      = string
        valueFrom = string
    }))
}

variable "environment_vars" {
    default     = []
    description = "List of plain text environment variables to inject into the container. Each item must have {name, value}"
    type = list(object({
        name  = string
        value = string
    }))
}

variable "health_check_grace_period_seconds" {
    default     = 60
    description = "Seconds to ignore failing load balancer health checks on newly instantiated tasks"
    type        = number
}

variable "desired_count" {
    default     = 2
    description = "Initial number of ECS tasks to run"
    type        = number
}

variable "min_capacity" {
    default     = 2
    description = "Minimum number of ECS tasks for autoscaling"
    type        = number
}

variable "max_capacity" {
    default     = 10
    description = "Maximum number of ECS tasks for autoscaling"
    type        = number
}

variable "autoscaling_cpu_target" {
    default     = 50.0
    description = "Target CPU utilization percentage for autoscaling (Target Tracking)"
    type        = number
}

variable "autoscaling_memory_target" {
    default     = 70.0
    description = "Target Memory utilization percentage for autoscaling (Target Tracking)"
    type        = number
}

variable "type_project" {
    default     = "laravel"
    description = "Project type. Allowed values: 'laravel' (port 80), 'django' (port 8000)"
    type        = string

    validation {
        condition     = contains(["laravel", "django"], var.type_project)
        error_message = "type_project must be 'laravel' or 'django'."
    }
}

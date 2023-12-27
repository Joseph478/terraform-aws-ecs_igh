variable "name_main" {
    description = "Name of the ECS"
    type        = string
}
variable "name_cluster_ecs" {
    description = "Name of the ECS"
    type        = string
}
variable "name_ecr" {
    description = "Name of the ECR"
    type        = string
}
variable "name_service_ecs" {
    description = "Name of the service ECS"
    type        = string
}
variable "name_tasks_ecs" {
    description = "Name of tasks"
    type        = string
}
variable "vpc_id" {
    description = "Name of the load balancer"
    type        = string
}
variable "target_group_arn" {
    description = "Target Group Arn"
    type        = string
}
variable "account_id" {
    description = "Account id"
    type = string
}
variable "subnets" {
    description = "Subnets of VPC"
    type = list(string)
}
variable "elb_name" {
    description = "Load Balancer Name"
    type = string
}
variable "ec2_security_group_id" {
    description = "ID Security Group ALB"
    type = string
}
variable "region" {
    default = "us-east-1"
    description = "Name of region"
    type        = string
}
variable "container_path" {
    type = string
}
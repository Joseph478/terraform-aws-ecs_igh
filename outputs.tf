output "arn_ecr_repository" {
    value = aws_ecr_repository.ecr_repository.arn
}

output "arn_ecs_cluster" {
    value = aws_ecs_cluster.ecs_cluster.arn
}

output "name_ecs_cluster" {
    value = aws_ecs_cluster.ecs_cluster.name
}

output "id_ecs_service" {
    value = aws_ecs_service.ecs_service.id
}

output "name_ecs_service" {
    value = aws_ecs_service.ecs_service.name
}

output "url_ecr_repository" {
    value = aws_ecr_repository.ecr_repository.repository_url
}

output "registry_id_ecr" {
    value = aws_ecr_repository.ecr_repository.registry_id
}

output "id_ecs_cluster" {
    value = aws_ecs_cluster.ecs_cluster.id
}

output "arn_ecs_task_definition" {
    value = aws_ecs_task_definition.task_definition.arn
}

output "revision_ecs_task_definition" {
    value = aws_ecs_task_definition.task_definition.revision
}

output "arn_ecs_task_role" {
    value = aws_iam_role.ecs_task_role.arn
}

output "name_ecs_task_role" {
    value = aws_iam_role.ecs_task_role.name
}

output "name_cloudwatch_log_group" {
    value = aws_cloudwatch_log_group.ecs_tasks.name
}

output "arn_cloudwatch_log_group" {
    value = aws_cloudwatch_log_group.ecs_tasks.arn
}
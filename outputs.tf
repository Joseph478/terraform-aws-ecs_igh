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
# VPC Outputs (Default VPC)
output "vpc_id" {
  description = "ID of the default VPC"
  value       = data.aws_vpc.default.id
}

output "subnet_ids" {
  description = "IDs of the default subnets"
  value       = data.aws_subnets.default.ids
}

# ECR Outputs
output "ecr_main_job_repository_url" {
  description = "URL of the main job ECR repository"
  value       = aws_ecr_repository.main_job.repository_url
}

output "ecr_background_job_repository_url" {
  description = "URL of the background job ECR repository"
  value       = aws_ecr_repository.background_job.repository_url
}

# ECS Outputs
output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.main.name
}

output "ecs_main_job_service_name" {
  description = "Name of the main job ECS service"
  value       = aws_ecs_service.main_job.name
}

output "ecs_background_job_service_name" {
  description = "Name of the background job ECS service"
  value       = aws_ecs_service.background_job.name
}

# No Load Balancer in simplified deployment

# CloudWatch Outputs
output "cloudwatch_log_group_ecs" {
  description = "Name of the ECS CloudWatch log group"
  value       = aws_cloudwatch_log_group.ecs_task.name
}

output "cloudwatch_log_group_main_job" {
  description = "Name of the main job CloudWatch log group"
  value       = aws_cloudwatch_log_group.main_job.name
}

output "cloudwatch_log_group_background_job" {
  description = "Name of the background job CloudWatch log group"
  value       = aws_cloudwatch_log_group.background_job.name
}

output "cloudwatch_log_group_background_jobs" {
  description = "Name of the background jobs CloudWatch log group"
  value       = aws_cloudwatch_log_group.background_job.name
}

output "kms_key_id" {
  description = "ID of the KMS key for CloudWatch logs encryption"
  value       = aws_kms_key.cloudwatch_logs.key_id
}

output "kms_key_arn" {
  description = "ARN of the KMS key for CloudWatch logs encryption"
  value       = aws_kms_key.cloudwatch_logs.arn
}

# SNS Outputs
output "sns_alerts_topic_arn" {
  description = "ARN of the SNS topic for alerts"
  value       = aws_sns_topic.alerts.arn
}

# SQS Outputs
output "sqs_main_job_triggers_queue_url" {
  description = "URL of the SQS main job triggers queue"
  value       = aws_sqs_queue.main_job_triggers.url
}

output "sqs_background_jobs_queue_url" {
  description = "URL of the SQS background jobs queue"
  value       = aws_sqs_queue.background_jobs.url
}

output "sqs_main_job_triggers_dlq_url" {
  description = "URL of the SQS main job triggers dead letter queue"
  value       = aws_sqs_queue.main_job_triggers_dlq.url
}

output "sqs_background_jobs_dlq_url" {
  description = "URL of the SQS background jobs dead letter queue"
  value       = aws_sqs_queue.background_jobs_dlq.url
}

# Background Job Service Outputs
output "background_job_service_name" {
  description = "Name of the background job ECS service"
  value       = aws_ecs_service.background_job.name
}

# Note: No public endpoints in this simplified Fargate-only deployment
# The service runs in private subnets and logs to CloudWatch

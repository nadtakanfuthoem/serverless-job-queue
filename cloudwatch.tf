# KMS Key for CloudWatch Logs Encryption
resource "aws_kms_key" "cloudwatch_logs" {
  description             = "KMS Key for CloudWatch Logs encryption"
  deletion_window_in_days = 7

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow CloudWatch Logs"
        Effect = "Allow"
        Principal = {
          Service = "logs.${var.aws_region}.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
        Condition = {
          ArnEquals = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/ecs/${local.name_prefix}*"
          }
        }
      }
    ]
  })

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-cloudwatch-logs-key"
  })
}

# KMS Key Alias
resource "aws_kms_alias" "cloudwatch_logs" {
  name          = "alias/${local.name_prefix}-cloudwatch-logs"
  target_key_id = aws_kms_key.cloudwatch_logs.key_id
}

# CloudWatch Log Group for ECS Tasks
resource "aws_cloudwatch_log_group" "ecs_task" {
  name              = "/ecs/${local.name_prefix}"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.cloudwatch_logs.arn

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-ecs-logs"
  })
}

# CloudWatch Log Group for Main Job
resource "aws_cloudwatch_log_group" "main_job" {
  name              = "/ecs/${local.name_prefix}/main-job"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.cloudwatch_logs.arn

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-main-job-logs"
  })
}

# CloudWatch Log Group for Background Jobs with Job ID Streams
resource "aws_cloudwatch_log_group" "background_job" {
  name              = "/ecs/${local.name_prefix}/background-job"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.cloudwatch_logs.arn

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-background-job-logs"
  })
}

# Random ID for ULID-like identifier
resource "random_id" "ulid_suffix" {
  byte_length = 10
}

# CloudWatch Log Stream for ULID-based logs (using ULID-like format)
resource "aws_cloudwatch_log_stream" "ulid_example" {
  name           = "ulid-streams/${formatdate("YYYY-MM-DD", timestamp())}/01HK${upper(random_id.ulid_suffix.hex)}"
  log_group_name = aws_cloudwatch_log_group.main_job.name
}

# CloudWatch Metric Filters
resource "aws_cloudwatch_log_metric_filter" "error_count" {
  name           = "${local.name_prefix}-error-count"
  log_group_name = aws_cloudwatch_log_group.main_job.name
  pattern        = "[timestamp, request_id, level=\"ERROR\", ...]"

  metric_transformation {
    name      = "${local.name_prefix}-ErrorCount"
    namespace = "ECS/Application"
    value     = "1"
  }
}

# CloudWatch Alarms
resource "aws_cloudwatch_metric_alarm" "high_error_rate" {
  alarm_name          = "${local.name_prefix}-high-error-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "${local.name_prefix}-ErrorCount"
  namespace           = "ECS/Application"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "This metric monitors error rate"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "${local.name_prefix}-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors ECS CPU utilization"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    ServiceName = aws_ecs_service.main_job.name
    ClusterName = aws_ecs_cluster.main.name
  }

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "high_memory" {
  alarm_name          = "${local.name_prefix}-high-memory"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ECS"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors ECS memory utilization"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    ServiceName = aws_ecs_service.main_job.name
    ClusterName = aws_ecs_cluster.main.name
  }

  tags = local.tags
}

# SNS Topic for Alerts
resource "aws_sns_topic" "alerts" {
  name              = "${local.name_prefix}-alerts"
  kms_master_key_id = aws_kms_key.cloudwatch_logs.key_id

  tags = local.tags
}

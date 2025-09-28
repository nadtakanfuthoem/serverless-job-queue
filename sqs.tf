# SQS Queue for Main Job Triggers
resource "aws_sqs_queue" "main_job_triggers" {
  name                      = "${local.name_prefix}-main-job-triggers"
  delay_seconds             = 0
  max_message_size          = 262144
  message_retention_seconds = 1209600 # 14 days
  receive_wait_time_seconds = 20      # Long polling
  visibility_timeout_seconds = 300    # 5 minutes

  # Enable server-side encryption
  kms_master_key_id = aws_kms_key.cloudwatch_logs.key_id
  
  # Dead letter queue configuration
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.main_job_triggers_dlq.arn
    maxReceiveCount     = 5
  })

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-main-job-triggers-queue"
  })
}

# Dead Letter Queue for failed main job triggers
resource "aws_sqs_queue" "main_job_triggers_dlq" {
  name                      = "${local.name_prefix}-main-job-triggers-dlq"
  message_retention_seconds = 1209600 # 14 days
  kms_master_key_id        = aws_kms_key.cloudwatch_logs.key_id

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-main-job-triggers-dlq"
  })
}

# SQS Queue for Background Jobs
resource "aws_sqs_queue" "background_jobs" {
  name                      = "${local.name_prefix}-background-jobs"
  delay_seconds             = 0
  max_message_size          = 262144
  message_retention_seconds = 1209600 # 14 days
  receive_wait_time_seconds = 0
  visibility_timeout_seconds = 30

  # Enable server-side encryption
  kms_master_key_id = aws_kms_key.cloudwatch_logs.key_id
  
  # Dead letter queue configuration
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.background_jobs_dlq.arn
    maxReceiveCount     = 3
  })

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-background-jobs-queue"
  })
}

# Dead Letter Queue for failed background jobs
resource "aws_sqs_queue" "background_jobs_dlq" {
  name                      = "${local.name_prefix}-background-jobs-dlq"
  message_retention_seconds = 1209600 # 14 days
  kms_master_key_id        = aws_kms_key.cloudwatch_logs.key_id

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-background-jobs-dlq"
  })
}

# SQS Queue Policy to allow ECS tasks to send messages
resource "aws_sqs_queue_policy" "background_jobs" {
  queue_url = aws_sqs_queue.background_jobs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowECSTaskSendMessage"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.ecs_task_role.arn
        }
        Action = [
          "sqs:SendMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = aws_sqs_queue.background_jobs.arn
      },
      {
        Sid    = "AllowBackgroundJobConsumer"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.background_job_role.arn
        }
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:ChangeMessageVisibility"
        ]
        Resource = aws_sqs_queue.background_jobs.arn
      }
    ]
  })
}

# CloudWatch Alarm for SQS Queue Depth
resource "aws_cloudwatch_metric_alarm" "sqs_queue_depth" {
  alarm_name          = "${local.name_prefix}-sqs-queue-depth"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ApproximateNumberOfVisibleMessages"
  namespace           = "AWS/SQS"
  period              = "300"
  statistic           = "Average"
  threshold           = "50"
  alarm_description   = "This metric monitors SQS queue depth"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    QueueName = aws_sqs_queue.background_jobs.name
  }

  tags = local.tags
}

# CloudWatch Alarm for Dead Letter Queue
resource "aws_cloudwatch_metric_alarm" "sqs_dlq_messages" {
  alarm_name          = "${local.name_prefix}-sqs-dlq-messages"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "ApproximateNumberOfVisibleMessages"
  namespace           = "AWS/SQS"
  period              = "300"
  statistic           = "Average"
  threshold           = "0"
  alarm_description   = "This metric monitors messages in dead letter queue"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    QueueName = aws_sqs_queue.background_jobs_dlq.name
  }

  tags = local.tags
}

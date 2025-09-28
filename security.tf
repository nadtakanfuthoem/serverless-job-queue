# Security Groups
resource "aws_security_group" "ecs_task" {
  name_prefix = "${local.name_prefix}-ecs-task-"
  vpc_id      = data.aws_vpc.default.id

  # Allow outbound internet access for pulling container images and logging
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow inbound access on container port from anywhere (for testing)
  ingress {
    description = "Container Port"
    from_port   = var.container_port
    to_port     = var.container_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-ecs-task-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# IAM Role for Background Job Processor
resource "aws_iam_role" "background_job_role" {
  name = "${local.name_prefix}-background-job-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = local.tags
}

# IAM Policy for Background Job SQS Access
resource "aws_iam_role_policy" "background_job_sqs" {
  name = "${local.name_prefix}-background-job-sqs"
  role = aws_iam_role.background_job_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:ChangeMessageVisibility"
        ]
        Resource = [
          aws_sqs_queue.background_jobs.arn,
          aws_sqs_queue.background_jobs_dlq.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = [
          "${aws_cloudwatch_log_group.main_job.arn}*",
          "${aws_cloudwatch_log_group.background_job.arn}*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = aws_kms_key.cloudwatch_logs.arn
      }
    ]
  })
}

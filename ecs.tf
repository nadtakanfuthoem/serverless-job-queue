# ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = "${local.name_prefix}-cluster"

  configuration {
    execute_command_configuration {
      kms_key_id = aws_kms_key.cloudwatch_logs.arn
      logging    = "OVERRIDE"

      log_configuration {
        cloud_watch_encryption_enabled = true
        cloud_watch_log_group_name     = aws_cloudwatch_log_group.ecs_task.name
      }
    }
  }

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-cluster"
  })
}

# ECS Cluster Capacity Providers
resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name = aws_ecs_cluster.main.name

  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = "FARGATE"
  }
}

# Task Execution Role
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "${local.name_prefix}-ecs-task-execution-role"

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

# Task Role (for application permissions)
resource "aws_iam_role" "ecs_task_role" {
  name = "${local.name_prefix}-ecs-task-role"

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

# Task Execution Role Policy Attachments
resource "aws_iam_role_policy_attachment" "ecs_task_execution_role" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ECR Access Policy for Task Execution Role
resource "aws_iam_role_policy" "ecs_task_execution_ecr" {
  name = "${local.name_prefix}-ecs-task-execution-ecr"
  role = aws_iam_role.ecs_task_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.ecs_task.arn}*"
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = aws_kms_key.cloudwatch_logs.arn
      }
    ]
  })
}

# CloudWatch Logs Policy for Task Role (for custom ULID logging)
resource "aws_iam_role_policy" "ecs_task_cloudwatch" {
  name = "${local.name_prefix}-ecs-task-cloudwatch"
  role = aws_iam_role.ecs_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams",
          "logs:DescribeLogGroups"
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
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:SendMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = [
          aws_sqs_queue.main_job_triggers.arn,
          aws_sqs_queue.background_jobs.arn
        ]
      }
    ]
  })
}

# Main Job Task Definition (Message-Driven)
resource "aws_ecs_task_definition" "main_job" {
  family                   = "${local.name_prefix}-main-job"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.container_cpu
  memory                   = var.container_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name  = "main-job-message-driven"
      image = "${aws_ecr_repository.main_job.repository_url}:${var.image_tag}"
      
      # No port mappings - pure message-driven
      
      environment = [
        {
          name  = "AWS_REGION"
          value = var.aws_region
        },
        {
          name  = "INPUT_QUEUE_URL"
          value = aws_sqs_queue.main_job_triggers.url
        },
        {
          name  = "SQS_QUEUE_URL"
          value = aws_sqs_queue.background_jobs.url
        },
        {
          name  = "POLL_INTERVAL_MS"
          value = "5000"
        },
        {
          name  = "NODE_OPTIONS"
          value = "--enable-source-maps"
        }
      ]
      
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.main_job.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "main-job"
        }
      }
      
      essential = true
      
      healthCheck = {
        command = [
          "CMD-SHELL",
          "ps aux | grep -q '[n]ode.*message-driven-main' || exit 1"
        ]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 10
      }
    }
  ])

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-task-definition"
  })
}

# Background Job Task Definition
resource "aws_ecs_task_definition" "background_job" {
  family                   = "${local.name_prefix}-background-job"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name  = "background-job-processor"
      image = "${aws_ecr_repository.background_job.repository_url}:${var.image_tag}"
      
      environment = [
        {
          name  = "AWS_REGION"
          value = var.aws_region
        },
        {
          name  = "SQS_QUEUE_URL"
          value = aws_sqs_queue.background_jobs.url
        },
        {
          name  = "LOG_GROUP_NAME"
          value = aws_cloudwatch_log_group.background_job.name
        }
      ]
      
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.background_job.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "background-job"
        }
      }
      
      essential = true
      
      healthCheck = {
        command = [
          "CMD-SHELL",
          "ps aux | grep -q '[n]ode.*processor' || exit 1"
        ]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 10
      }
    }
  ])

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-background-job-task"
  })
}

# Main Job ECS Service
resource "aws_ecs_service" "main_job" {
  name            = "${local.name_prefix}-main-job-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.main_job.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    security_groups  = [aws_security_group.ecs_task.id]
    subnets          = data.aws_subnets.default.ids
    assign_public_ip = true
  }

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-main-job-service"
  })

  lifecycle {
    ignore_changes = [task_definition]
  }
}

# Background Job ECS Service
resource "aws_ecs_service" "background_job" {
  name            = "${local.name_prefix}-background-job-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.background_job.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    security_groups  = [aws_security_group.ecs_task.id]
    subnets          = data.aws_subnets.default.ids
    assign_public_ip = true
  }

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-background-job-service"
  })

  lifecycle {
    ignore_changes = [task_definition]
  }
}



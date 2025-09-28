# Main Job ECR Repository
resource "aws_ecr_repository" "main_job" {
  name                 = "${var.project_name}-main-job"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-main-job-repo"
  })
}

# Background Job ECR Repository
resource "aws_ecr_repository" "background_job" {
  name                 = "${var.project_name}-background-job"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-background-job-repo"
  })
}

# Main Job ECR Repository Policy
resource "aws_ecr_repository_policy" "main_job" {
  repository = aws_ecr_repository.main_job.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowPull"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability"
        ]
      }
    ]
  })
}

# Background Job ECR Repository Policy
resource "aws_ecr_repository_policy" "background_job" {
  repository = aws_ecr_repository.background_job.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowPull"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability"
        ]
      }
    ]
  })
}

# Main Job ECR Lifecycle Policy
resource "aws_ecr_lifecycle_policy" "main_job" {
  repository = aws_ecr_repository.main_job.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# Background Job ECR Lifecycle Policy
resource "aws_ecr_lifecycle_policy" "background_job" {
  repository = aws_ecr_repository.background_job.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# Project configuration
variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "message-driven-microservices"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

# Container configuration (No ports needed for message-driven)
variable "container_port" {
  description = "Port that the container exposes (not used in message-driven)"
  type        = number
  default     = 0
}

variable "container_cpu" {
  description = "CPU units for the container (256, 512, 1024, 2048, 4096)"
  type        = number
  default     = 256
}

variable "container_memory" {
  description = "Memory for the container in MB (512, 1024, 2048, 4096, 8192, 16384, 30720)"
  type        = number
  default     = 512
}

variable "desired_count" {
  description = "Number of desired tasks"
  type        = number
  default     = 1
}

# Networking configuration
variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.20.0/24"]
}

# CloudWatch configuration
variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 14
}

# ECR configuration
variable "ecr_repository_name" {
  description = "Name of the ECR repository"
  type        = string
  default     = "main-job-app"
}

variable "image_tag" {
  description = "Docker image tag"
  type        = string
  default     = "latest"
}

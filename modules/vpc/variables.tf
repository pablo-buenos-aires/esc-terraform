
variable "vpc_cidr" {
  type = string
  default = "10.0.0.0/16"
}
# списки зон для подсетей, для публичной - первая в списке
variable "vpc_azs" {
  type = list(string)
  default = ["sa-east-1a", "sa-east-1b"]

  validation {
    condition = length(var.vpc_azs) == 2
    error_message = "❌  Зон должно быть 2"
  }
}

variable "public_subnet_cidrs" {
  type = list(string)
  default = ["10.0.1.0/24", "10.0.12.0/24"]
  validation {
    condition = length(var.vpc_azs) == length(var.public_subnet_cidrs)
    error_message = "❌  Количество зон и подсетей не совпадают"
  }
}

variable "private_subnet_cidrs" {
  type = list(string)
  default = ["10.0.11.0/24", "10.0.12.0/24"]
  validation {
    condition = length(var.vpc_azs) == length(var.private_subnet_cidrs)
    error_message = "❌  Количество зон и подсетей не совпадают"
  }
}
// ------------------------------------------------------------- variables for ALB and ACM
variable "acm_certificate_arn" {
  type        = string
  description = "ARN сертификата ACM для api-домена"
}
variable "ecr_repository_url" {
  type        = string
  description = "ECR repo URL (без тега), типа 8369....dkr.ecr.sa-east-1.amazonaws.com/go-backend"
}

variable "image_tag" {
  type        = string
  default     = "latest"
  description = "Docker image tag"
}

# БД и другие настройки как env-переменные
variable "db_host"     { type = string }
variable "db_port"     { type = string }
variable "db_user"     { type = string }
variable "db_password" { type = string }
variable "db_name"     { type = string }

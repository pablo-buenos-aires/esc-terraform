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
  description = "Docker image tag, типа v15 или latest"
}

# БД и другие настройки как env-переменные
variable "db_host"     { type = string }
variable "db_port"     { type = string }
variable "db_user"     { type = string }
variable "db_password" { type = string }
variable "db_name"     { type = string }

variable "vpc_id"     { type = string }
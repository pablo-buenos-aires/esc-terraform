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


variable "vpc_id"     { type = string }

variable "public_subnet_ids" {
  type        = list(string)
  description = "Публичные подсети для ALB"
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "Приватные подсети для ECS"
}
#------------------------------------------------------------ дополнительные параметры
variable "alb_name" {
  type        = string
  default     = "backend-alb"
  description = "Имя ALB"
}

variable "ecs_cluster_name" {
  type        = string
  default     = "backend-cluster"
  description = "Имя кластера ECS"
}

variable "task_family" {
  type        = string
  default     = "backend-task"
  description = "Имя семейства task definition"
}

variable "container_name" {
  type        = string
  default     = "backend-container"
  description = "Имя контейнера в задаче ECS"
}


variable "ecs_service_name" {
  type        = string
  default     = "ecs-service"
  description = "Имя сервиса ECS"
}

variable "service_port" {
  type        = number
  default     = 8080
  description = "Порт, на котором работает контейнер и target group"
}

variable "task_cpu" {
  type        = string
  default     = "256"
  description = "Количество CPU единиц для Fargate задачи"
}

variable "task_memory" {
  type        = string
  default     = "512"
  description = "Объём памяти для Fargate задачи в МБ"
}

variable "desired_count" {
  type        = number
  default     = 1
  description = "Желаемое количество задач в сервисе"
}

variable "log_group_name" {
  type        = string
  default     = "/ecs/backend"
  description = "Имя лог-группы CloudWatch"
}

# Секрет с учётными данными базы

# БД и другие настройки как env-переменные
variable "db_host"     { type = string }
variable "db_port"     { type = string }

variable "db_secret_arn" {
  type        = string
  description = "ARN секрета в Secrets Manager с полями username, password и dbname"
}

variable "db_username_secret_key" {
  type        = string
  default     = "username"
  description = "Ключ в SecretString для имени пользователя"
}

variable "db_password_secret_key" {
  type        = string
  default     = "password"
  description = "Ключ в SecretString для пароля"
}

variable "db_name_secret_key" {
  type        = string
  default     = "dbname"
  description = "Ключ в SecretString для имени БД"
}
# БД и другие настройки как env-переменные
variable "db_host" { type = string }
variable "db_port" { type = string }

// определяются снаружи модуля
variable "ecs_sg_id" { type = string }
variable "alb_sg_id" { type = string }

variable "ecr_repository_url" {  type  = string}
variable "image_tag" {
  type    = string
  default = "latest"
}
variable "vpc_id" { type = string }
variable "public_subnet_ids" {  type  = list(string)}
variable "private_subnet_ids" { type = list(string) }
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


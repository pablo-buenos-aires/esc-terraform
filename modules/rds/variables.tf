variable "rds_sg_id" {
  description = "Security Group RDS, которой разрешим доступ от ECS задач"
  type        = string
}

variable "ecs_sg_id" {
  description = "Security Group ECS задач, которой разрешим доступ к RDS"
  type        = string
}


variable "vpc_id" {
  description = "ID VPC, где живут приватные подсети"
  type        = string
}

variable "private_subnet_ids" {
  description = "Список приватных подсетей для RDS subnet group"
  type        = list(string)
}


variable "db_credentials" {
  description = "Имя секрета в Secrets Manager с JSON {username,password,dbname}"
  type        = string
}

variable "db_identifier" {
  description = "Идентификатор RDS инстанса"
  type        = string
  default     = "db-postgres-id"
}

variable "instance_class" {
  description = "Класс инстанса RDS"
  type        = string
  default     = "db.t4g.micro"
}

variable "allocated_storage" {
  description = "Размер диска в ГБ"
  type        = number
  default     = 20
}

variable "engine_version" {
  description = "Версия PostgreSQL"
  type        = string
  default     = "16.3"
}

variable "multi_az" {
  description = "Включить Multi-AZ"
  type        = bool
  default     = false
}
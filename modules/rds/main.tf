data "aws_secretsmanager_secret" "db_credentials" { name = var.db_credentials }
data "aws_secretsmanager_secret_version" "db_credentials" { secret_id = data.aws_secretsmanager_secret.db_credentials.id }

# не годятся динамические строки с арн , поэтому парсим здесь
locals {
  db_creds = jsondecode(data.aws_secretsmanager_secret_version.db_credentials.secret_string)
}


# Subnet group для RDS
resource "aws_db_subnet_group" "db_subnet_group" {
  name       = "db-subnet-group"
  subnet_ids = var.private_subnet_ids
}
# Сам RDS Postgres
resource "aws_db_instance" "db_instance" {
  identifier = var.db_identifier

  engine         = "postgres"
 // engine_version = var.engine_version

  instance_class    = var.instance_class
  allocated_storage = var.allocated_storage
  storage_type      = "gp3"

  db_name  = local.db_creds.dbname
  username = local.db_creds.username
  password = local.db_creds.password

  db_subnet_group_name   = aws_db_subnet_group.db_subnet_group.name
  # Привязываем отдельную SG для БД, которая пропускает трафик только от ECS задач
  vpc_security_group_ids = [var.rds_sg_id] # разрешаем доступ из ECS задач

  # Приватный инстанс
  publicly_accessible = false

  # Простые настройки
  backup_retention_period = 0
  skip_final_snapshot     = true

  # Multi-AZ опционально
  multi_az = var.multi_az

  # Авто minor updates
  auto_minor_version_upgrade = true // c false - error

  deletion_protection = false

}

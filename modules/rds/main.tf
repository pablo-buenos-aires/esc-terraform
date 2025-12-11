data "aws_secretsmanager_secret" "db_credentials" { name = var.db_credentials }
data "aws_secretsmanager_secret_version" "db_credentials" { secret_id = data.aws_secretsmanager_secret.db_credentials.id }

# не годятся динамические строки с арн , поэтому парсим здесь
locals {
  db_creds = jsondecode(data.aws_secretsmanager_secret_version.db_credentials.secret_string)
}

resource "aws_security_group" "rds_sg" {
  name        = "rds-sg"
  vpc_id      = var.vpc_id

  # Вход с ECS SG, порт 5432
  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.ecs_sg_id]
  }

  # Выход: весь трафик наружу (для обновлений, бэкапов и т.п. через NAT)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Subnet group для RDS
resource "aws_db_subnet_group" "this" {
  name       = "dbsubnet-group"
  subnet_ids = var.private_subnet_ids
}
# Сам RDS Postgres
resource "aws_db_instance" "this" {
  identifier = var.db_identifier

  engine         = "postgres"
  engine_version = var.engine_version

  instance_class    = var.instance_class
  allocated_storage = var.allocated_storage
  storage_type      = "gp3"

  db_name  = local.db_creds.dbname
  username = local.db_creds.username
  password = local.db_creds.password

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]

  # Приватный инстанс
  publicly_accessible = false

  # Простые настройки
  backup_retention_period = 7
  skip_final_snapshot     = true

  # Multi-AZ опционально
  multi_az = var.multi_az

  # Авто minor updates
  auto_minor_version_upgrade = true

  deletion_protection = false

}

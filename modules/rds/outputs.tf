output "rds_endpoint" {
  description = "DNS endpoint RDS"
  value       = aws_db_instance.db_instance.address
}

output "rds_port" {
  description = "Порт RDS"
  value       = aws_db_instance.db_instance.port
}

output "db_name" {
  description = "Имя БД"
  value       = aws_db_instance.db_instance.db_name
}

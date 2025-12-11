output "rds_endpoint" {
  description = "DNS endpoint RDS"
  value       = aws_db_instance.this.address
}

output "rds_port" {
  description = "Порт RDS"
  value       = aws_db_instance.this.port
}

output "security_group_id" {
  description = "Security Group, которую использует RDS"
  value       = aws_security_group.rds_sg.id
}

output "db_name" {
  description = "Имя БД"
  value       = aws_db_instance.this.db_name
}

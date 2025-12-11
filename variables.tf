variable "t3" {
  type        = string
  default     = "t3.micro"
}

variable "iam_user" {
  type        = string
  default     = "pablo"
}

variable "service_port" {
  description = "Порт, на котором сервис принимает трафик"
  type        = number
  default     = 8080
}
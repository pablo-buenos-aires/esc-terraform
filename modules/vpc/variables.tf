
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

// для маршрутов в нат
variable "pub_ubuntu_nat" { type = string }

// для sg в модуле esc

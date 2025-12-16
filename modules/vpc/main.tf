#variable "vpc_name" { type = string }

# делаем регион для ssm endpoints
locals {
  az1    = try(element(var.vpc_azs, 0), error("❌ Количество зон = 0"))
  region = substr(local.az1, 0, length(local.az1) - 1)
  #err_priv = length(var.private_subnet_cidrs) != length(var.vpc_azs) ?  error("❌ Кол. зон != кол. подсетей") : true
}

# основная VPC
resource "aws_vpc" "main_vpc" {
 
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
}
 
# подсети
resource "aws_subnet" "public_subnet" {
  count             = length(var.public_subnet_cidrs)
  vpc_id            = aws_vpc.main_vpc.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  availability_zone = var.vpc_azs[count.index]
  #map_public_ip_on_launch = true             # Автоназначение публичных IP в этой подсети
  # tags = {  Name = "${var.vpc_name}-public" }
}

resource "aws_subnet" "private_subnet" {
  count             = length(var.private_subnet_cidrs) #
  vpc_id            = aws_vpc.main_vpc.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.vpc_azs[count.index]
}


resource "aws_internet_gateway" "igw" { vpc_id = aws_vpc.main_vpc.id } # IGW для доступа VPC в интернет
# NAT gateway и EIP для него
resource "aws_eip" "nat_eip" {
  domain = "vpc"
  depends_on = [aws_internet_gateway.igw]
  tags = { Name = "nat-eip" }
}
resource "aws_nat_gateway" "nat_gw" {
  # allocation_id = aws_eip.nat_eip.id
  allocation_id = aws_eip.nat_eip.allocation_id

  subnet_id     = aws_subnet.public_subnet[0].id # в 1 публичной подсети
  tags = { Name = "nat-gateway" }
  depends_on = [aws_internet_gateway.igw]
}
# -------------------------------------------------------------------------------------------  bastion/nat SG
resource "aws_security_group" "alb_sg" { # для ALB
   vpc_id       = aws_vpc.main_vpc.id
   ingress { 
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
   ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress { #  ходить куда угодно 
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {Name = "alb-sg"}
}

resource "aws_security_group" "ecs_sg" { # для ECS tasks
  vpc_id            = aws_vpc.main_vpc.id
  # Пускаем трафик на 8080 только от ALB
  ingress {
    from_port       = var.service_port
    to_port         = var.service_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }
  # Таски могут ходить наружу (через NAT) и к другим сервисам
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
    tags = {Name = "ecs-sg"}
}
resource "aws_security_group" "rds_sg" {
  vpc_id      = aws_vpc.main_vpc.id

  # Вход с ECS SG, порт 5432
  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_sg.id]
  }

  # Выход: весь трафик наружу (для обновлений, бэкапов и т.п. через NAT)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
    tags = {Name = "rds-sg"}
}


resource "aws_security_group" "public_sg" { # разрешаем входящий трафик по SSH и любой из приватной подсети, для NAT
  vpc_id = aws_vpc.main_vpc.id
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # со всех адресов
  }

  ingress { # for private subnet, NAT
    from_port   = 0
    to_port     = 0
    protocol    = "-1" #  любой протокол
    cidr_blocks = var.private_subnet_cidrs
  }

  egress { # исходящий трафик открыт
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
   tags = {Name = "public_sg"}
}
# ------------------------------------------------------------------------------------------- SG приватный инстанс
resource "aws_security_group" "private_sg" {
  vpc_id = aws_vpc.main_vpc.id
  ingress { # разрешаем входящий трафик по SSH от бастиона
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.public_sg.id]
  }
  egress { # исходящий трафик открыт
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
    tags = {Name = "private_sg"}
}
# ------------------------------------------------------------------------------------------- SG endpoints
resource "aws_security_group" "endpoint_sg" { # для SSM endpoints
  vpc_id = aws_vpc.main_vpc.id
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main_vpc.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {Name = "endpoint_sg"}
}


# ---------------------------------------------------------------------------------------- маршруты
resource "aws_route_table" "rt_pub" { # марш. таблица для публичной подсети
  vpc_id = aws_vpc.main_vpc.id
  route {
    cidr_block = "0.0.0.0/0"                 # исходящий трафик во все подсети
    gateway_id = aws_internet_gateway.igw.id # идёт через igw
  }
}

resource "aws_route_table" "rt_priv" { vpc_id = aws_vpc.main_vpc.id }
# исходящий трафик приватных подсетей через NAT
resource "aws_route" "rt_priv_route" { 
  route_table_id         = aws_route_table.rt_priv.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_gw.id
}


# связь приватных таблиц с подсетями
resource "aws_route_table_association" "rt_priv_ass" { # связь с приват 
  count          = length(var.private_subnet_cidrs)
  subnet_id      = aws_subnet.private_subnet[count.index].id
  route_table_id = aws_route_table.rt_priv.id
}

resource "aws_route_table_association" "rt_pub_ass" { # Привязка таблицы к публичной подсети
  count          = length(var.public_subnet_cidrs)
  subnet_id      = aws_subnet.public_subnet[count.index].id
  route_table_id = aws_route_table.rt_pub.id
}


# -вкключим маршрут гна НАТ, доступ по SSM теперь

# resource "aws_route" "rt_priv_route" { # нужен отдельно маршрут, инлайн нельзя для instance_id
#   route_table_id         = aws_route_table.rt_priv.id
#   destination_cidr_block = "0.0.0.0/0"
#   # instance_id = aws_instance.pub_ubuntu.id  #  NAT/bastion инстанс
#   network_interface_id   = var.nat_network_interface_id
#   #n etwork_interface_id = aws_instance.pub_ubuntu.primary_network_interface_id # в новых провайдерах через ENI
#   # depends_on           = [var.nat_network_interface_id]                            # дождаться инстанса
# }

#------------------------------------------------------------------------- настройка  endpoints


resource "aws_vpc_endpoint" "endpoints" {
   for_each = {
    ssm         = "com.amazonaws.${local.region}.ssm"
    ec2messages = "com.amazonaws.${local.region}.ec2messages"
    ssmmessages = "com.amazonaws.${local.region}.ssmmessages"
  }
  vpc_id              = aws_vpc.main_vpc.id
  service_name        = each.value
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  subnet_ids          = aws_subnet.private_subnet[*].id # в каждой подсети эндпоинты
  security_group_ids  = [aws_security_group.endpoint_sg.id]
}







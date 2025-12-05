#variable "vpc_name" { type = string }

# делаем регион для ssm endpoints
locals {
  az1 = try(element(var.vpc_azs, 0),  error("❌ Количество зон = 0"))
  region = substr(local.az1, 0, length(local.az1) - 1)
  #err_priv = length(var.private_subnet_cidrs) != length(var.vpc_azs) ?  error("❌ Кол. зон != кол. подсетей") : true
 }

# основная VPC
resource "aws_vpc" "main_vpc" {
  cidr_block = var.vpc_cidr
  enable_dns_hostnames = true
}

 # подсети
resource "aws_subnet" "public_subnet" {
  count = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.main_vpc.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.vpc_azs[count.index]
  #map_public_ip_on_launch = true             # Автоназначение публичных IP в этой подсети
  # tags = {  Name = "${var.vpc_name}-public" }
}

resource "aws_subnet" "private_subnet" {
  count = length(var.private_subnet_cidrs) #
  vpc_id = aws_vpc.main_vpc.id
  cidr_block = var.private_subnet_cidrs[count.index]
  availability_zone = var.vpc_azs[count.index]
}


resource "aws_internet_gateway" "igw" { vpc_id = aws_vpc.main_vpc.id } # IGW для доступа VPC в интернет

# -------------------------------------------------------------------------------------------  bastion/nat SG
resource "aws_security_group" "public_sg" {  # разрешаем входящий трафик по SSH и любой из приватной подсети, для NAT
   	vpc_id      = aws_vpc.main_vpc.id
	ingress {
    	from_port   = 22
    	to_port     = 22
    	protocol    = "tcp"
    	cidr_blocks = ["0.0.0.0/0"] # со всех адресов
   	}

   	ingress { # for private subnet, NAT
    	from_port   = 0
    	to_port     = 0
    	protocol    = "-1"  #  любой протокол
    	cidr_blocks = var.private_subnet_cidrs
  	}

  	egress { # исходящий трафик открыт
    	from_port   = 0
    	to_port     = 0
    	protocol    = "-1"
    	cidr_blocks = ["0.0.0.0/0"]
  	}
}
# ------------------------------------------------------------------------------------------- SG приватный инстанс
resource "aws_security_group" "private_sg" {
   	vpc_id      = aws_vpc.main_vpc.id
	ingress { # разрешаем входящий трафик по SSH от бастиона
        from_port   = 22
        to_port     = 22
        protocol    = "tcp"
        security_groups = [aws_security_group.public_sg.id]
    }
  	egress { # исходящий трафик открыт
    	from_port   = 0
    	to_port     = 0
    	protocol    = "-1"
    	cidr_blocks = ["0.0.0.0/0"]
  	}
}
# ------------------------------------------------------------------------------------------- SG endpoints
resource "aws_security_group" "endpoint_sg" { # для SSM endpoints
   	vpc_id      = aws_vpc.main_vpc.id
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
}

resource "aws_security_group" "alb_sg" { # для ALB
   vpc_id      = aws_vpc.main_vpc.id
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
}

resource "aws_security_group" "ecs_sg" { # для ECS tasks
  vpc_id      = aws_vpc.main_vpc.id
  # Пускаем трафик на 8080 только от ALB
  ingress {
    from_port       = 8080
    to_port         = 8080
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

}

resource "aws_lb" "alb" {
  name               = "backend-alb"
  load_balancer_type = "application"
  internal           = false              # публичный ALB
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = aws_subnet.public_subnet_ids # в публичных подсетях
}

resource "aws_lb_target_group" "alb_tg" {
  port        = 8080
  protocol    = "HTTP"
  target_type = "ip"                      # важно для Fargate
  vpc_id      = aws_vpc.main_vpc.id

  health_check {
    path                = "/health"
    protocol            = "HTTP"
    matcher             = "200-399"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

# HTTP -> редирект на HTTPS
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action { # на алб ходятт только по реез
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# Основной HTTPS listener
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = var.acm_certificate_arn # передашь из ACM

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb_tg.arn
  }
}

data "aws_iam_policy_document" "ecs_task_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "task_execution_role" {
 assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json
}

resource "aws_iam_role_policy_attachment" "task_execution_policy" {
  role       = aws_iam_role.task_execution_role.name // -name
  # эта политика позволяет таскам скачивать образы из ECR и отправлять логи в CloudWatch и др
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "task_role" {
   assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json
}


//------------------------------- cluster, task definition и service  для ECS Fargate
resource "aws_ecs_cluster" "ecs_cluster" {
    name = "backend-cluster"
    setting {
    name  = "containerInsights" // CloudWatch Container Insights, логи и метрики
    value = "enabled"
  }
}

data "aws_region" "current" {}
resource "aws_cloudwatch_log_group" "log_group" {
  name              = "/ecs/backend"
  retention_in_days = 14
}

resource "aws_ecs_task_definition" "ecs_task_definition" {
  family                   = "backend-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"   # 0.25 vCPU
  memory                   = "512"   # 512 MB

  execution_role_arn = aws_iam_role.task_execution_role.arn
  task_role_arn      = aws_iam_role.task_role.arn

  container_definitions = jsonencode([
    {
      name      = "backend-container"
      image     = "${var.ecr_repository_url}:${var.image_tag}"
      essential = true

      portMappings = [
        {
          containerPort = 8080
          protocol      = "tcp"
        }
      ]

      environment = [
        { name = "DB_HOST",     value = var.db_host },
        { name = "DB_PORT",     value = var.db_port },
        { name = "DB_USER",     value = var.db_user },
        { name = "DB_PASSWORD", value = var.db_password },
        { name = "DB_NAME",     value = var.db_name },
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.app.name
          awslogs-region        = data.aws_region.current.name
          awslogs-stream-prefix = "go-backend-"
        }
      }
    }
  ])
}


resource "aws_ecs_service" "ecs_service" {
  name            = "ecs-service"
  cluster         = aws_ecs_cluster.ecs_cluster.id
  task_definition = aws_ecs_task_definition.ecs_task_definition.arn
  launch_type     = "FARGATE"
  desired_count   = 1

  network_configuration {
    subnets          =  aws_subnet.private_subnet_ids  # приватные подсети
    security_groups  = [aws_security_group.ecs_sg.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.alb_tg.arn
    container_name   = "backend-container" //local.app_name
    container_port   = 8080
  }
  depends_on = [aws_lb_listener.https]
}

# ---------------------------------------------------------------------------------------- маршруты
resource "aws_route_table" "rt_pub" { # марш. таблица для публичной подсети
  	vpc_id = aws_vpc.main_vpc.id
  	route {
    		cidr_block = "0.0.0.0/0"                 # исходящий трафик во все подсети
    		gateway_id = aws_internet_gateway.igw.id # идёт через igw
  		}
	}

resource "aws_route_table" "rt_priv" { vpc_id = aws_vpc.main_vpc.id  }

# связь приватных таблиц с подсетями
resource "aws_route_table_association" "rt_priv_ass" { # связь с приват 1.
  count = length(var.private_subnet_cidrs) #
  subnet_id      = aws_subnet.private_subnet[count.index].id
  route_table_id = aws_route_table.rt_priv.id
}

resource "aws_route_table_association" "rt_pub_ass" { # Привязка таблицы к публичной подсети
  count = length(var.public_subnet_cidrs) #
 	subnet_id      = aws_subnet.public_subnet[count.index].id
  route_table_id = aws_route_table.rt_pub.id
	}


# -вкключим маршрут гна НАТ, доступ по SSM теперь

resource "aws_route" "rt_priv_route" { # нужен отдельно маршрут, инлайн нельзя для instance_id
  route_table_id         = aws_route_table.rt_priv.id
  destination_cidr_block = "0.0.0.0/0"
 # instance_id = aws_instance.pub_ubuntu.id  #  NAT/bastion инстанс
  network_interface_id   = aws_instance.pub_ubuntu.primary_network_interface_id # в новых провайдерах через ENI
  depends_on = [aws_instance.pub_ubuntu]   # дождаться инстанса
  }

#------------------------------------------------------------------------- настройка  endpoints

/*
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

//*/





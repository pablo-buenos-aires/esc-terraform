
resource "aws_security_group" "alb_sg" { # для ALB
   vpc_id       = var.vpc_id
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
  vpc_id            = var.vpc_id
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
  subnets            = var.public_subnet_ids # в публичных подсетях
}

resource "aws_lb_target_group" "alb_tg" {
  port        = 8080
  protocol    = "HTTP"
  target_type = "ip"                      # важно для Fargate
  vpc_id      =  var.vpc_id

  health_check {
    path                = "/health"
    protocol            = "HTTP"
    matcher             = "200-399"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2 # Количество успешных проверок для признания экземпляра здоровым
    unhealthy_threshold = 2 # Количество неудачных проверок для признания экземпляра нездоровым
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
          awslogs-group         = aws_cloudwatch_log_group.log_group.name
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
    subnets          = var.private_subnet_ids  # приватные подсети
    security_groups  = [aws_security_group.ecs_sg.id]
    assign_public_ip = false
  }

  load_balancer { # alb для сер
    target_group_arn = aws_lb_target_group.alb_tg.arn
    container_name   = "backend-container" //local.app_name
    container_port   = 8080
  }
  depends_on = [aws_lb_listener.https]
}

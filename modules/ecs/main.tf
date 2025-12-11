


resource "aws_lb" "alb" {
  name               = var.alb_name
  load_balancer_type = "application"
  internal           = false              # публичный ALB
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = var.public_subnet_ids # в публичных подсетях
}

resource "aws_lb_target_group" "alb_tg" {
  port        = var.service_port
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

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb_tg.arn
  }
}

# # Основной HTTPS listener
# resource "aws_lb_listener" "https" {
#   load_balancer_arn = aws_lb.alb.arn
#   port              = 443
#   protocol          = "HTTPS"
#   ssl_policy        = "ELBSecurityPolicy-2016-08"
#   certificate_arn   = var.acm_certificate_arn # передашь из ACM

#   default_action {
#     type             = "forward"
#     target_group_arn = aws_lb_target_group.alb_tg.arn
#   }
# }

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
    name = var.ecs_cluster_name
    setting {
    name  = "containerInsights" // CloudWatch Container Insights, логи и метрики
    value = "enabled"
  }
}

data "aws_region" "current" {}

resource "aws_cloudwatch_log_group" "log_group" {
  name              = var.log_group_name
  retention_in_days = 14
}

resource "aws_ecs_task_definition" "ecs_task_definition" {
   family                   = var.task_family
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.task_cpu
  memory                   = var.task_memory
 # executionRoleArn: "arn:aws:iam::836940249137:role/ecsTaskExecutionRole",
 # taskRoleArn: "arn:aws:iam::836940249137:role/ecsAppTaskRole",
  execution_role_arn = aws_iam_role.task_execution_role.arn
  task_role_arn      = aws_iam_role.task_role.arn

  container_definitions = jsonencode([
    {
      name      = var.container_name
      image     = "${var.ecr_repository_url}:${var.image_tag}"
      essential = true # контейнер упал, падает вся задача 

      portMappings = [
        {
          containerPort = var.service_port # порт внутри контейнера
          hostPort      = var.service_port # порт на котором контейнер доступен в таске
          protocol      = "tcp"
        }
      ]

      environment = [
        { name = "DB_HOST",     value = var.db_host },
        { name = "DB_PORT",     value = var.db_port },
      ]

      secrets = [
        {
          name      = "DB_USER"
          valueFrom = "${data.aws_secretsmanager_secret_version.db_credentials.arn}:username::"
        },
        {
          name      = "DB_PASSWORD"
          valueFrom = "${data.aws_secretsmanager_secret_version.db_credentials.arn}:password::"
        },
        {
          name      = "DB_NAME"
          valueFrom = "${data.aws_secretsmanager_secret_version.db_credentials.arn}:dbname::"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.log_group.name
          awslogs-region        = data.aws_region.current.region
          awslogs-stream-prefix = "go-backend-"
        }
      }
    }
  ])
}


resource "aws_ecs_service" "ecs_service" {
  name            = var.ecs_service_name
  cluster         = aws_ecs_cluster.ecs_cluster.id
  task_definition = aws_ecs_task_definition.ecs_task_definition.arn
  launch_type     = "FARGATE"
  desired_count   = var.desired_count

  network_configuration {
    subnets          = var.private_subnet_ids  # приватные подсети
    security_groups  = [aws_security_group.ecs_sg.id]
    assign_public_ip = false
  }

  load_balancer { # alb для сер
    target_group_arn = aws_lb_target_group.alb_tg.arn
    container_name   = var.container_name
    container_port   = var.service_port
  }
  depends_on = [aws_lb_listener.http]
}

# секрет с учётными данными базы
data "aws_secretsmanager_secret" "db_credentials" {
  name = "db_credentials"  # точное имя как в консоли
}

data "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = data.aws_secretsmanager_secret.db_credentials.id
}
# resource "aws_secretsmanager_secret" "db_credentials" { # секрет с учётными данными БД
#   name = "db_credentials"
# }

# resource "aws_secretsmanager_secret_version" "db_credentials_version" { # версия секрета с учётными данными БД
#   secret_id     = aws_secretsmanager_secret.db_credentials.id
#   secret_string = jsonencode({
#     username = "db_admin"
#     password = "12345678"
#     dbname   = "userdb"
#   })
# }

# IAM политика для тасков ECS, чтобы читать секреты из Secrets Manager
resource "aws_iam_policy" "task_read_db_secret" {
  name        = "ecs-task-read-db-secret"
  description = "Allow ECS tasks to read DB credentials from Secrets Manager"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = data.aws_secretsmanager_secret.db_credentials.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "task_execution_read_db_secret" {
  role       = aws_iam_role.task_execution_role.name
  policy_arn = aws_iam_policy.task_read_db_secret.arn
}
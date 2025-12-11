resource "aws_security_group" "alb_sg" { # для ALB
   vpc_id       = module.vpc.vpc_id
   ingress { 
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  #  ingress {
  #   from_port   = 443
  #   to_port     = 443
  #   protocol    = "tcp"
  #   cidr_blocks = ["0.0.0.0/0"]
  # }

  egress { #  ходить куда угодно 
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "ecs_sg" { # для ECS tasks
  vpc_id            = module.vpc.vpc_id
  # Пускаем трафик на 8080 только от ALB
  ingress {
    from_port       = module.ecs.service_port
    to_port         = module.ecs.service_port
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
# ------------------------------------------------------------------------------- /modules
module "vpc" {
  source               = "./modules/vpc"
  vpc_cidr             = "10.0.0.0/16"
  public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24"] # для каждой подсети должно быть ссответствие azs

  //pub_ubuntu_nat = module.ec2.pub_ubuntu_nat // 
  //nat_network_interface_id = module.ec2.nat_network_interface_id

  vpc_azs = ["sa-east-1a", "sa-east-1b"] # из первого возьмется регион для эндпоинтов ssm
}

module "ec2" {
  source   = "./modules/ec2"
  vpc_cidr = module.vpc.vpc_cidr
  key_name = aws_key_pair.ssh_aws_key.key_name

  ami_id = data.aws_ami.ubuntu24_nat.id // образ с  net-persistant
  // проброс подсетей и групп безопасности
  public_subnet_ids  = module.vpc.public_subnet_ids
  private_subnet_ids = module.vpc.private_subnet_ids

  private_sg_id         = module.vpc.private_sg_id
  public_sg_id          = module.vpc.public_sg_id
  instance_profile_name = aws_iam_instance_profile.ssm_profile.name # профиль от роли SSM
}

module "ecs" {
  source             = "./modules/ecs"
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  public_subnet_ids  = module.vpc.public_subnet_ids


  db_host = module.rds.db_host
  db_port = module.rds.db_port
  # зашито desired_count 1, имена кластера, службы, алб, логи зашиты в variables.tf

  ecr_repository_url = "836940249137.dkr.ecr.sa-east-1.amazonaws.com/go-backend"
  image_tag          = "latest"
  # acm_certificate_arn = "arn:aws:acm:sa-east-1:836940249137:certificate/your-certificate-id"
}

module "rds" {
  source             = "./modules/rds"
  vpc_id             = module.vpc.vpc_id
  
  private_subnet_ids = module.vpc.private_subnet_ids
  ecs_sg_id = aws_security_group.ecs_sg.id

  db_credentials = "db_credentials" # имя секрета в Secrets Manager
  
}

# --------------------------------------------------------------------- маршрут в нат
resource "aws_route" "private_nat_route" {
  route_table_id         = module.vpc.route_table_private # Берем из output VPC
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = module.ec2.nat_network_interface_id # Берем из output EC2
}


# -------------------------------------------------------------------- ключи здесь оставим
resource "tls_private_key" "ssh_key" { # генерация ключа через встроенного провайдера
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "aws_key_pair" "ssh_aws_key" {                   # регистрируем ключ
  public_key = tls_private_key.ssh_key.public_key_openssh # ключ в формате Openssh
  key_name   = "tf-ssh-key"                               # без этого не связывает ключи корректно

}

resource "local_file" "file_ssh_priv" { # без provisioner — через local_file
  content         = tls_private_key.ssh_key.private_key_pem
  filename        = "${path.module}/ssh-key.pem"
  file_permission = "0400"
}

resource "local_file" "file_ssh_pub" {
  content  = tls_private_key.ssh_key.public_key_openssh
  filename = "${path.module}/ssh-key.pub"
}
# --------------------------------------------------------------------------------------- инстансы



# Null resource, который зависим от ASG, и выполняет команду AWS CLI
# resource "null_resource" "get_priv_instances" {
#   depends_on = [aws_autoscaling_group.priv_asg]

#   provisioner "local-exec" {
#     command = <<EOT
#       aws autoscaling describe-auto-scaling-groups \
#         --auto-scaling-group-names ${aws_autoscaling_group.priv_asg.name} \
#         --query 'AutoScalingGroups[0].Instances[*].InstanceId' \
#         --output json > asg_instances.json
#     EOT
#   }
# } 

#--------------------------------------------------------------------------- настройка SSM для инстансов
resource "aws_iam_role" "ssm_role" { # роль создаем
  name = "ssm_role_name"
  assume_role_policy = jsonencode({ # для получения JSON для амазон
    Version = "2012-10-17"          # обязательное поле
    Statement = [{                  #  список правил
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" } # кто может эту роль использовать, в т.ч инстансы ec2s

    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_core" { # добавление политики к роли для SSM длоступа
  role       = aws_iam_role.ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ssm_profile" { # профиль на базе роли, для привязки к инстансам
  name = "ssm_profile_name"
  role = aws_iam_role.ssm_role.name
}

# для обновления списка инстансов в asg
# resource "terraform_data" "get_priv_instances" {
#   # форсируем замену ресурса на каждом плане/аплае
#   triggers_replace = timestamp()  # <<< меняется каждый apply => ресурс пересоздаётся
#   depends_on = [module.ec2.asg_arn]

# #   provisioner "local-exec" {
# #     interpreter = ["/bin/bash", "-lc"] # без этого в одну строу команды
# #     command = <<EOT
# # set -euo pipefail
# # aws autoscaling describe-auto-scaling-groups \
# #   --auto-scaling-group-names "${module.ec2.asg_name}" \
# #   --query 'AutoScalingGroups[0].Instances[*].InstanceId' \
# #   --output json > asg_instances.json
# # EOT
# #   }
# # }

# # for Windows
# provisioner "local-exec" {
#   environment = {
#     AWS_PROFILE = var.iam_user
#   }

#   interpreter = ["PowerShell", "-Command"]
#   command     = <<-EOT
# $ErrorActionPreference = "Stop"
# aws autoscaling describe-auto-scaling-groups `
#   --auto-scaling-group-names "${module.ec2.asg_name}" `
#   --query 'AutoScalingGroups[0].Instances[*].InstanceId' `
#   --output json |
#   Out-File -FilePath "asg_instances.json" -Encoding ascii
# EOT
#   }
# }




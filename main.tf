terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region  = "ap-northeast-2"
  profile = "terraform-user"
}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "my-vpc"
  cidr = "10.0.0.0/16"

  azs                          = ["ap-northeast-2a", "ap-northeast-2c"]
  private_subnets              = ["10.0.1.0/24", "10.0.3.0/24"]
  public_subnets               = ["10.0.101.0/24", "10.0.103.0/24"]
  database_subnets             = ["10.0.201.0/24", "10.0.203.0/24"]
  create_database_subnet_group = true

  map_public_ip_on_launch = true

  tags = {
    Name = "my-vpc"
  }
}

resource "aws_route" "nat_route" {
  count                  = 2
  route_table_id         = module.vpc.private_route_table_ids[count.index]
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = module.nat_instance.primary_network_interface_id
}

module "bastion" {
  source = "terraform-aws-modules/ec2-instance/aws"

  name = "bastion-host"

  instance_type = "t3.micro"
  key_name      = "bastion-host-key"
  monitoring    = true
  subnet_id     = module.vpc.public_subnets[0]
  ami           = "ami-00e73adb2e2c80366"
  tags = {
    Name = "bastion-host"
  }

  vpc_security_group_ids = [module.bastion_sg.security_group_id]
}

module "bastion_sg" {
  # 22 허용
  source = "terraform-aws-modules/security-group/aws"

  name            = "bastion-sg"
  use_name_prefix = false
  description     = "bastion-host"
  vpc_id          = module.vpc.vpc_id

  ingress_with_cidr_blocks = [
    {
      rule        = "ssh-tcp"
      cidr_blocks = "0.0.0.0/0"
    },
  ]
  egress_with_cidr_blocks = [
    {
      rule        = "all-all"
      cidr_blocks = "0.0.0.0/0"
    },
  ]
}

module "nat_instance" {
  source = "terraform-aws-modules/ec2-instance/aws"

  name = "nat-instance"

  instance_type = "t3.micro"
  key_name      = "bastion-host-key"
  monitoring    = true
  subnet_id     = module.vpc.public_subnets[1]
  ami           = "ami-0eb63419e063fe627"
  tags = {
    Name = "nat-instance"
  }
  source_dest_check      = false
  vpc_security_group_ids = [module.nat_sg.security_group_id]
  user_data              = file("nat-setting.sh")
}

module "nat_sg" {
  # all 허용
  source = "terraform-aws-modules/security-group/aws"

  name            = "nat-sg"
  use_name_prefix = false
  description     = "nat-instance"
  vpc_id          = module.vpc.vpc_id

  ingress_with_cidr_blocks = [
    {
      rule        = "all-all"
      cidr_blocks = "0.0.0.0/0"
    },
  ]
  egress_with_cidr_blocks = [
    {
      rule        = "all-all"
      cidr_blocks = "0.0.0.0/0"
    },
  ]
}

module "web_ec2" {
  source = "terraform-aws-modules/ec2-instance/aws"
  count  = 2
  name   = "web-instance"

  instance_type = "t3.micro"
  key_name      = "web-server-key"
  monitoring    = true
  subnet_id     = module.vpc.private_subnets[count.index]
  ami           = "ami-00e73adb2e2c80366"
  tags = {
    Name = "web-instance"
  }

  vpc_security_group_ids = [module.web_sg.security_group_id]

  user_data = templatefile("${path.module}/tomcat-setting.sh.tpl", {
    DB_ADDRESS     = module.db.db_instance_address,
    DB_USERNAME    = var.db_username,
    DB_PASSWORD    = var.db_password,
    S3_BUCKET_NAME = module.S3.bucket_name
  })
  iam_instance_profile = module.IAM.iam_instance_profile
  depends_on           = [module.nat_instance]
}


module "web_sg" {
  # 22, 8080 허용
  source = "terraform-aws-modules/security-group/aws"

  name            = "web-sg"
  use_name_prefix = false
  description     = "Security group for http-8080-service with custom ports open within VPC"
  vpc_id          = module.vpc.vpc_id

  ingress_with_cidr_blocks = [
    {
      rule        = "ssh-tcp"
      cidr_blocks = "0.0.0.0/0"
    },
    {
      rule        = "http-8080-tcp"
      cidr_blocks = "0.0.0.0/0"
    },
  ]
  egress_with_cidr_blocks = [
    {
      rule        = "all-all"
      cidr_blocks = "0.0.0.0/0"
    },
  ]
}

module "db" {
  source = "terraform-aws-modules/rds/aws"

  identifier = "database-1"

  engine            = "mariadb"
  engine_version    = "11.4"
  instance_class    = "db.t4g.micro"
  allocated_storage = 20

  db_name                     = "care"
  username                    = var.db_username
  password                    = var.db_password
  manage_master_user_password = false

  vpc_security_group_ids = [module.rds_sg.security_group_id]

  tags = {
    Name = "quiz-rds"
  }

  db_subnet_group_name      = module.vpc.database_subnet_group_name
  create_db_option_group    = false
  create_db_parameter_group = false

  # Database Deletion Protection
  deletion_protection = false
  skip_final_snapshot = true
  apply_immediately   = true
}


module "rds_sg" {
  # 3306 허용
  source = "terraform-aws-modules/security-group/aws"

  name            = "rds-sg"
  use_name_prefix = false
  description     = "mariadb"
  vpc_id          = module.vpc.vpc_id

  ingress_with_source_security_group_id = [
    {
      rule                     = "mysql-tcp"
      source_security_group_id = module.web_sg.security_group_id
    },
  ]
  egress_with_cidr_blocks = [
    {
      rule        = "all-all"
      cidr_blocks = "0.0.0.0/0"
    },
  ]
}

locals {
  env = "stage"
}

module "S3" {
  source = "./local_modules/s3"
  env    = local.env
}

module "IAM" {
  source      = "./local_modules/iam"
  env         = local.env
  bucket_name = module.S3.bucket_name
}

module "AMI" {
  source            = "./local_modules/ami"
  env               = local.env
  bastion_public_ip = module.bastion.public_ip
  web_instance      = module.web_ec2[0]
}

module "alb" {
  source = "terraform-aws-modules/alb/aws"

  name                       = "${local.env}-alb"
  vpc_id                     = module.vpc.vpc_id
  subnets                    = module.vpc.public_subnets
  enable_deletion_protection = false

  # Security Group
  security_group_ingress_rules = {
    all_http = {
      from_port   = 80
      to_port     = 80
      ip_protocol = "tcp"
      description = "HTTP web traffic"
      cidr_ipv4   = "0.0.0.0/0"
    }
  }

  security_group_egress_rules = {
    all = {
      ip_protocol = "-1"
      cidr_ipv4   = "0.0.0.0/0"
    }
  }

  listeners = {
    ex-http = {
      port     = 80
      protocol = "HTTP"
      forward = {
        target_group_key = "ex-instance"
      }
    }
  }

  target_groups = {
    ex-instance = {
      create_attachment = false # aws_lb_target_group_attachment 생성하지마
      protocol    = "HTTP"
      port        = 8080
      target_type = "instance"

      stickiness = {
        enabled = true
        type    = "lb_cookie"
      }

      health_check = {
        enabled  = true
        path     = "/boot/"
        protocol = "HTTP"
        port     = 8080
      }
    }

  }

  tags = {
    Name = "alb"
  }
}

module "asg" {
  source = "terraform-aws-modules/autoscaling/aws"

  # Autoscaling group
  name = "${local.env}-asg"

  min_size                  = 2
  max_size                  = 4
  desired_capacity          = 2
  wait_for_capacity_timeout = 0
  health_check_type         = "ELB"
  vpc_zone_identifier       = module.vpc.private_subnets

  # Launch template
  launch_template_name        = "${local.env}-asg"
  launch_template_description = "Launch template ${local.env}"
  launch_template_version     = "$Latest"

  image_id        = module.AMI.ami_instance_id
  instance_type   = "t3.micro"
  key_name        = "web-server-key"
  security_groups = [module.web_sg.security_group_id]

  traffic_source_attachments = {
    ex-alb = {
      traffic_source_identifier = module.alb.target_groups["ex-instance"].arn
      traffic_source_type       = "elbv2" # default
    }
  }

  scaling_policies = {
    my-policy = {
      policy_type = "TargetTrackingScaling"
      target_tracking_configuration = {
        predefined_metric_specification = {
          predefined_metric_type = "ASGAverageCPUUtilization"
          # resource_label         = "MyLabel"
        }
        target_value = 50.0
      }
    }
  }
}

# PS C:\terraform\workspace\26_quiz> $env:TF_VAR_db_username = "admin"
# PS C:\terraform\workspace\26_quiz> $env:TF_VAR_db_password = "mariaPassw0rd"
# PS C:\terraform\workspace\26_quiz> terraform init
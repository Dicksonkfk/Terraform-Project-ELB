provider "aws" {
  region = var.aws_region
}

data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "zone-type"
    values = ["availability-zone"]
  }
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "3.14.2"

  for_each = var.projects
  cidr = var.vpc_cidr_block

  azs             = data.aws_availability_zones.available.names
  private_subnets = slice(var.private_subnet_cidr_blocks, 0, each.value.private_subnets_per_vpc)
  public_subnets  = slice(var.public_subnet_cidr_blocks, 0, each.value.public_subnets_per_vpc)

  enable_nat_gateway = true
  enable_vpn_gateway = false

  map_public_ip_on_launch = false
}

module "app_security_group" {
  source  = "terraform-aws-modules/security-group/aws//modules/web"
  version = "4.9.0"

  for_each    = var.projects 
  name        = "web-server-sg-${each.key}-${each.value.environment}"
  description = "Security group for web-servers with HTTP ports open within VPC"
  vpc_id      = module.vpc[each.key].vpc_id

  ingress_cidr_blocks = module.vpc[each.key].public_subnets_cidr_blocks
}

module "lb_security_group" {
  source  = "terraform-aws-modules/security-group/aws//modules/web"
  version = "4.9.0"

  for_each = var.projects
  name = "load-balancer-sg-${each.key}-${each.value.environment}"

  description = "Security group for load balancer with HTTP ports open within VPC"
  vpc_id      = module.vpc[each.key].vpc_id

  ingress_cidr_blocks = ["0.0.0.0/0"]
}

resource "random_string" "lb_id" {
  length  = 4
  special = false
}

module "elb_http" {
  source  = "terraform-aws-modules/elb/aws"
  version = "3.0.1"

  for_each = var.projects

  # To Comply with ELB name restrictions
  
  name     = trimsuffix(substr(replace(join("-", ["lb", random_string.lb_id.result, each.key, each.value.environment]), "/[^a-zA-Z0-9-]/", ""), 0, 32), "-")
  internal = false

  security_groups = [module.lb_security_group[each.key].security_group_id]
  subnets         = module.vpc[each.key].public_subnets

  number_of_instances = length(aws_instance.app.instance_ids)
  instances           = aws_instance.app.instance_ids

  listener = [{
    instance_port     = "80"
    instance_protocol = "HTTP"
    lb_port           = "80"
    lb_protocol       = "HTTP"
  }]

  health_check = {
    target              = "HTTP:80/index.html"
    interval            = 10
    healthy_threshold   = 3
    unhealthy_threshold = 10
    timeout             = 5
  }
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

resource "aws_instance" "app" {
# count = var.instance_count
  for_each = var.projects

  ami           = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type

  subnet_id              = var.subnet_ids[count.index % length(var.subnet_ids)]
  vpc_security_group_ids = var.security_group_ids

  user_data = <<-EOF
    #!/bin/bash
    sudo yum update -y
    sudo yum install httpd -y
    sudo systemctl enable httpd
    sudo systemctl start httpd
    echo "<html><body><div>Hello, world!</div></body></html>" > /var/www/html/index.html
    EOF

    project_name = each.key
    environment  = each.value
}
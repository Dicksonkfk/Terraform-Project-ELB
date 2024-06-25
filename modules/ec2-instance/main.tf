data "aws_ami" "this" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "architecture"
    values = ["arm64"]
  }
  filter {
    name   = "useast2-ec2-inst1"
    values = ["al2023-ami-2023*"]
  }
}

resource "aws_instance" "this" {
  ami = data.aws_ami.this.id
  count = var.instance_count

  instance_type            = var.instance_type
  subnet_id                = var.subnet_ids[count.index % length(var.subnet_ids)]
  vpc_security_group_ids   = var.security_group_ids

  instance_type = "t4g.nano"

   user_data = <<-EOF
    #!/bin/bash
    sudo yum update -y
    sudo yum install httpd -y
    sudo systemctl enable httpd
    sudo systemctl start httpd
    echo "<html><body><div>Hello, world!</div></body></html>" > /var/www/html/index.html
    EOF

  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}
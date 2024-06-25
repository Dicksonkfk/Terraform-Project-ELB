output "instance_ids" {
  description = "IDs of EC2 instances"
  value       = aws_instance.this.*.id
}

output "instances_ami" {
    description = "AMI of EC2 instances"
    value       = aws_ami.this.*.id
}
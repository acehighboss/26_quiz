output "ami_instance_id" {
  value = aws_ami_from_instance.quiz_ami_instance.id
}

output "quiz_web_ec2_terminate" {
  value = null_resource.quiz_web_ec2_terminate
}
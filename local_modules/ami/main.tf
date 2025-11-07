resource "null_resource" "quiz_web_ec2_time_wait" {
  depends_on = [var.web_instance]
  provisioner "remote-exec" {
    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = file("~/.ssh/bastion-host-key.pem")
      host        = var.bastion_public_ip
    }

    inline = [
      "until curl -f http://${var.web_instance.private_ip}:8080/boot/; do echo '웹 서비스 준비 중'; sleep 10;  done"
    ]
  }
}

resource "aws_ami_from_instance" "quiz_ami_instance" {
  name               = "${var.env}-web-ami"
  source_instance_id = var.web_instance.id
  tags = {
    "Name" = "${var.env}-web-ami"
  }

  depends_on = [null_resource.quiz_web_ec2_time_wait]
}

resource "null_resource" "quiz_web_ec2_terminate" {
  depends_on = [aws_ami_from_instance.quiz_ami_instance]

  provisioner "local-exec" {
    command = "aws ec2 terminate-instances --instance-ids ${var.web_instance.id} --profile terraform-user"
  }
}

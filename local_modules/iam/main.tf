resource "aws_iam_role" "quiz_s3_ec2_role" {
  name = "${var.env}-s3-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })

  tags = {
    "Name" = "${var.env}-s3-ec2-role"
  }
}

resource "aws_iam_role_policy" "quiz_s3_ec2_policy" {
  name = "${var.env}-s3-ec2-policy"
  role = aws_iam_role.quiz_s3_ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:GetObject",
        ]
        Effect = "Allow"
        # Resource = "*"
        Resource = "arn:aws:s3:::${var.bucket_name}/*"
      },
    ]
  })
}

resource "aws_iam_instance_profile" "quiz_instance_profile" {
  name = "${var.env}-instance-profile"
  role = aws_iam_role.quiz_s3_ec2_role.name
}

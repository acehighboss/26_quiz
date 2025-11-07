resource "aws_s3_bucket" "quiz_s3_bucket" {
  bucket = "${var.env}-kyes-bucket"

  tags = {
    Name = "${var.env}-kyes-bucket"
  }
}

resource "aws_s3_object" "quiz_s3_object" {
  bucket = aws_s3_bucket.quiz_s3_bucket.id
  key    = "boot.war"
  source = "${path.module}/boot.war"
  etag   = filemd5("${path.module}/boot.war")
}

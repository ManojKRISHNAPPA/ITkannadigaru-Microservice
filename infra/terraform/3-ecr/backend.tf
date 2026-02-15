terraform {
  backend "s3" {
    bucket         = "bindu-deployecho-tfstate-826828992763-us-east-1"
    key            = "deployecho/3-ecr/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "deployecho-terraform-locks"
    encrypt        = true
  }
}

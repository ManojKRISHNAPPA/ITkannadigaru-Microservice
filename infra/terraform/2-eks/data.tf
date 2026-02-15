data "terraform_remote_state" "network" {
  backend = "s3"

  config = {
    bucket = "bindu-deployecho-tfstate-826828992763-us-east-1"
    key    = "deployecho/1-network/terraform.tfstate"
    region = "us-east-1"
  }
}

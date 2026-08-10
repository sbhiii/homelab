terraform {
  backend "s3" {
    bucket       = "srehomelab-tfstate"
    key          = "aws/terraform.tfstate"
    region       = "eu-west-1"
    encrypt      = true
    use_lockfile = true
  }
}

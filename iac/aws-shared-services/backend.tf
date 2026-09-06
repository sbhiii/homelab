terraform {
  backend "s3" {
    bucket       = "sbhi-homelab-tfstate"
    key          = "aws/terraform.tfstate"
    region       = "eu-west-1"
    encrypt      = true
    use_lockfile = true
  }
}

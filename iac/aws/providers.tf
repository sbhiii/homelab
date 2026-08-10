terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    external = {
      source  = "hashicorp/external"
      version = "~> 2.3"
    }
  }
}

provider "aws" {
  region = var.region
}

# CloudFront only accepts ACM certificates issued in us-east-1, wherever the
# rest of the stack lives.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

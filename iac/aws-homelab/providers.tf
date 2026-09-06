terraform {
  required_version = "~> 1.15"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region              = var.region
  allowed_account_ids = [var.workload_account_id]

  default_tags {
    tags = {
      Owner      = "sbhi"
      ManagedBy  = "Terraform"
      Repository = "homelab"
    }
  }
}

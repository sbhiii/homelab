variable "region" {
  description = "AWS region hosting the terraform state bucket."
  type        = string
  default     = "eu-west-1"
}

variable "shared_services_account_id" {
  description = "Account this stack applies into. Guard rail for allowed_account_ids."
  type        = string
}

variable "state_bucket_name" {
  description = "Globally unique name for the terraform state bucket."
  type        = string
}

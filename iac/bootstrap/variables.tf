variable "region" {
  description = "AWS region hosting the terraform state bucket."
  type        = string
  default     = "eu-west-1"
}

variable "state_bucket_name" {
  description = "Globally unique name for the terraform state bucket."
  type        = string
}

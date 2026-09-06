variable "region" {
  description = "Primary AWS region."
  type        = string
  default     = "eu-west-1"
}

variable "workload_account_id" {
  description = "Account this stack applies into. Guard rail for allowed_account_ids."
  type        = string
}

variable "dns_zone_name" {
  description = "Zone delegated to this account, created by the landing zone repository and looked up by name."
  type        = string
}

variable "oidc_subdomain" {
  description = "Label under dns_zone_name serving the OIDC discovery documents."
  type        = string
  default     = "oidc"
}

variable "external_secrets_namespace" {
  description = "Namespace running external-secrets."
  type        = string
  default     = "external-secrets"
}

variable "external_secrets_service_account" {
  description = "ServiceAccount external-secrets runs as."
  type        = string
  default     = "external-secrets-ssm"
}

locals {
  issuer_host = "${var.oidc_subdomain}.${var.dns_zone_name}"
  issuer_url  = "https://${local.issuer_host}"
}

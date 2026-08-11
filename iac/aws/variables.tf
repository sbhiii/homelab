variable "region" {
  description = "Primary AWS region."
  type        = string
  default     = "eu-west-1"
}

variable "dns_zone_name" {
  description = "Hosted zone delegated from Cloudflare."
  type        = string
  default     = "srehomelab.sbhi.io"
}

variable "oidc_subdomain" {
  description = "Label under dns_zone_name serving the OIDC discovery documents."
  type        = string
  default     = "oidc"
}

variable "state_bucket_name" {
  description = "Bucket holding the hetzner stack's state, read for the public key."
  type        = string
}

variable "cert_manager_namespace" {
  description = "Namespace running cert-manager."
  type        = string
  default     = "cert-manager"
}

variable "cert_manager_service_account" {
  description = "ServiceAccount cert-manager runs as."
  type        = string
  default     = "cert-manager"
}

locals {
  issuer_host = "${var.oidc_subdomain}.${var.dns_zone_name}"
  issuer_url  = "https://${local.issuer_host}"
}

data "terraform_remote_state" "hetzner" {
  backend = "s3"
  config = {
    bucket = var.state_bucket_name
    key    = "hetzner/terraform.tfstate"
    region = var.region
  }
}

variable "ingress_node_id" {
  description = "Key of the node carrying the Ingress, within the hetzner stack's nodes map."
  type        = string
  default     = "01"
}

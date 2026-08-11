# provider
variable "hcloud_token" {
  sensitive = true
}

# common

variable "project_code" {
  description = "Project code."
  type        = string
}

variable "environment" {
  description = "Environment."
  type        = string
}

# network

variable "vpc_cidr" {
  description = "CIDR block"
  type        = string
  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "Must be a valid CIDR block."
  }
}

variable "subnet_ip_range" {
  description = "CIDR block representing a subnet."
  type        = string
  validation {
    condition     = can(cidrhost(var.subnet_ip_range, 0))
    error_message = "Must be a valid CIDR block."
  }
}

variable "server_private_ip" {
  description = "Static private IP address for the server hosting k3s (must be in the same IP range as the network)."
  type        = string
  validation {
    condition     = can(cidrnetmask("${var.server_private_ip}/32"))
    error_message = "server_private_ip must be a valid IPv4."
  }
}

variable "allowed_mgmt_ips" {
  description = "List of CIDRs allowed for administration (SSH port 22 & K8s API port 6443)."
  type        = list(string)

  validation {
    condition     = alltrue([for ip in var.allowed_mgmt_ips : can(cidrnetmask(ip))])
    error_message = "Each entry must be a valid CIDR block (e.g., '82.123.45.67/32' or '0.0.0.0/0')."
  }
}

# server

variable "nodes" {
  description = "Cluster node configuration."
  # The map key becomes the name suffix (e.g. '01', 'master', 'worker-gpu').
  type = map(object({
    server_type = string
    ip          = string
    labels      = optional(map(string), {}) # To tag a specific node
  }))
}

# k3s Cluster configuration
variable "github_token" {
  description = "GitHub Personal Access Token (scope: repo)"
  type        = string
  sensitive   = true
}

variable "github_repo_url" {
  description = "HTTPS URL of the gitops repo."
  type        = string
  default     = "https://github.com/sbhiii/sre-homelab-gitops.git"
}

# variable "realdebrid_api_key" {
#   description = "RealDebrid API token"
#   type        = string
#   sensitive   = true
# }

variable "oidc_issuer_url" {
  description = "Public URL serving the cluster's OIDC discovery documents."
  type        = string
  default     = "https://oidc.srehomelab.sbhi.io"

  validation {
    condition     = startswith(var.oidc_issuer_url, "https://")
    error_message = "The issuer must use HTTPS: AWS rejects any other scheme."
  }
}

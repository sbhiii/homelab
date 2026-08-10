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
  description = "Configuration des noeuds du cluster"
  # La clé de la map sera le suffixe du nom (ex: '01', 'master', 'worker-gpu')
  type = map(object({
    server_type = string
    ip          = string
    labels      = optional(map(string), {}) # Pour tagger spécifiquement un noeud
  }))
}

# k3s Cluster configuration
variable "github_token" {
  description = "GitHub Personal Access Token (scope: repo)"
  type        = string
  sensitive   = true
}

variable "github_repo_url" {
  description = "URL HTTPS du repo gitops"
  type        = string
  default     = "https://github.com/sbhiii/sre-homelab-gitops.git"
}

# variable "realdebrid_api_key" {
#   description = "API Token pour RealDebrid"
#   type        = string
#   sensitive   = true
# }

variable "oidc_issuer_url" {
  description = "URL publique servant les documents de découverte OIDC du cluster."
  type        = string
  default     = "https://oidc.srehomelab.sbhi.io"

  validation {
    condition     = startswith(var.oidc_issuer_url, "https://")
    error_message = "L'issuer doit être en HTTPS : AWS refuse tout autre schéma."
  }
}

# ssh access
data "hcloud_ssh_key" "samy-ssh" {
  name = "samy-macbook-pro-ssh"
}
# Network

locals {
  network_name       = lower("${var.project_code}-${var.environment}-vpc")
  server_name_prefix = lower("${var.project_code}-${var.environment}-server")

  # common labels for governance (FinOps / Ops)
  common_labels = {
    Environment = var.environment
    Project     = var.project_code
    ManagedBy   = "Terraform"
  }
}


resource "hcloud_network" "private-network" {
  name     = local.network_name
  ip_range = var.vpc_cidr
  labels   = local.common_labels
}

resource "hcloud_network_subnet" "network-subnet" {
  type         = "cloud"
  network_id   = hcloud_network.private-network.id
  network_zone = "eu-central"
  ip_range     = var.subnet_ip_range
}

resource "hcloud_firewall" "homelab_fw" {
  name = "${local.network_name}-fw"

  # HTTP (Port 80)
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "80"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  # HTTPS (Port 443)
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "443"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  # UDP Gaming / WireGuard (Optional)
  # rule {
  #   direction  = "in"
  #   protocol   = "udp"
  #   port       = "51820"
  #   source_ips = ["0.0.0.0/0", "::/0"]
  # }

  # SSH (Port 22)
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = var.allowed_mgmt_ips
  }

  # Kubernetes API (Port 6443)
  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "6443"
    source_ips = concat(
      [var.vpc_cidr],
      var.allowed_mgmt_ips
    )
  }

  # ICMP (Ping)
  rule {
    direction  = "in"
    protocol   = "icmp"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  apply_to {
    label_selector = "Project=${var.project_code}"
  }
}

# server(s)

resource "hcloud_server" "nodes" {
  for_each = var.nodes
  name     = "${local.server_name_prefix}-${each.key}"

  server_type = each.value.server_type
  image       = "debian-12"
  location    = "nbg1"
  ssh_keys    = [data.hcloud_ssh_key.samy-ssh.id]

  user_data = templatefile("${path.module}/scripts/init-cluster.sh.tftpl", {
    argocd_manifest = templatefile("${path.module}/manifests/argocd.yml", {})
    argocd_repo_secret = templatefile("${path.module}/manifests/argocd-repo-secret.yml.tftpl", {
      git_repo_url = var.github_repo_url
      git_token    = var.github_token
    })
    argocd_root_app = templatefile("${path.module}/manifests/argocd-root-app.yml.tftpl", {
      git_repo_url = var.github_repo_url
    })
    oidc_issuer_url = var.oidc_issuer_url
    sa_private_key  = tls_private_key.sa_signing.private_key_pem
    sa_public_key   = tls_private_key.sa_signing.public_key_pem
  })

  network {
    network_id = hcloud_network.private-network.id
    ip         = each.value.ip
  }

  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }

  labels = merge(
    local.common_labels,
    each.value.labels,
    {
      "node_id" = each.key
    }
  )

  depends_on = [
    hcloud_network_subnet.network-subnet
  ]
}

[← Back to README](../README.md) · [Architecture](architecture.md) · [Operations](operations.md) · [Security model](security.md)

# Getting started

## Prerequisites

### Tools

| Tool | Used for | Notes |
|---|---|---|
| [Terraform](https://developer.hashicorp.com/terraform) | everything under `iac/` | developed against 1.14.x; no `required_version` is pinned in code |
| [AWS CLI v2](https://docs.aws.amazon.com/cli/) | applying `iac/aws` and `iac/bootstrap`, and diagnosing the trust chain | needs credentials the Terraform AWS provider can actually read — see the gotcha below |
| `hcloud` token | applying `iac/hetzner` | a Hetzner Cloud API token, not the CLI itself |
| `kubectl` | talking to the cluster once it exists | |
| `helm` | required by `kubectl kustomize --enable-helm` when validating the gitops repo locally | ArgoCD's repo-server needs the equivalent server-side; this is only for local checks |
| `ssh` | reaching the node directly (cloud-init logs, emergency access) | |
| `dig` / `openssl` / `curl` | verifying DNS delegation and the OIDC discovery endpoints | |
| Python 3 | `terraform apply` in `iac/aws` shells out to it | `pem_to_jwk.py` is invoked as a Terraform `external` data source, stdlib only — no `pip install` needed |

**A credentials gotcha worth knowing before you start:** if your AWS CLI is configured via `aws sso login` / `aws login` (i.e. it stores a session rather than static keys), the Terraform AWS provider often cannot read that session directly. The reliable pattern is:

```bash
eval "$(aws configure export-credentials --format env)" && terraform apply
```

Both halves in the same shell invocation — the exported variables don't persist across separate commands.

### Accounts

- **A Hetzner Cloud project**, with an API token and an SSH key already uploaded to it. The SSH key must exist under a name that matches `data "hcloud_ssh_key" "samy-ssh"` in [`iac/hetzner/main.tf`](../iac/hetzner/main.tf) — either rename your key to `samy-macbook-pro-ssh` or edit that data source to look up your own.
- **An AWS account.** IAM permissions to create S3 buckets, CloudFront distributions, ACM certificates, a Route53 hosted zone, and IAM OIDC providers/roles. In this project's own deployment that's an IAM user with broad rights (`iamadmin`) — see [Known limitations](security.md#known-limitations) for why that's not ideal and what a real deployment would do instead.
- **A domain, or a subdomain you can delegate.** This deployment delegates `srehomelab.sbhi.io` — a subdomain of a domain registered at Cloudflare — to Route53 via NS records, while the domain's apex stays at Cloudflare. Terraform cannot perform that delegation itself; it's the one genuinely manual step in the whole bootstrap (see [Bootstrapping the stack](#bootstrapping-the-stack) below).
- **A GitHub repository forked from [`sre-homelab-gitops`](https://github.com/sbhiii/sre-homelab-gitops)**, plus a token ArgoCD can use to read it — classic PAT with `repo` scope, or a fine-grained PAT scoped to that repository with `Contents: Read`.

### Background knowledge

This project assumes comfort with, roughly in order of how load-bearing they are:

- **Terraform**: modules, remote state, the `data "terraform_remote_state"` pattern, and why a `-target` apply is sometimes the right call rather than a smell (see below).
- **AWS IAM and OIDC federation**: what `sts:AssumeRoleWithWebIdentity` actually checks, what an OIDC provider's thumbprint is for, and why trust-policy conditions matter. If IRSA on EKS is unfamiliar, read up on that first — this repo builds the same thing by hand.
- **Kubernetes fundamentals**: ServiceAccounts, projected tokens, and enough `kubectl` to read logs and describe resources. ArgoCD-specific knowledge helps but isn't required to understand this repo.
- **DNS**: NS delegation between providers, A vs. ALIAS records, and how ACME DNS-01 challenges work.
- Enough shell/bash to read `init-cluster.sh.tftpl` and follow what cloud-init is doing to the node.

For the reasoning behind the pieces below rather than just the steps, see [Architecture](architecture.md).

## Bootstrapping the stack

This walks through bootstrapping the whole stack from nothing. It assumes you've forked both repos and have the tools and accounts above.

**1. Create the state bucket.**

```bash
cd iac/bootstrap
terraform init
terraform apply -var state_bucket_name=<a-globally-unique-name>
```

This is local state, on purpose — see [`iac/bootstrap/README.md`](../iac/bootstrap/README.md). Keep that state file safe; losing it means `terraform import`-ing the bucket back rather than just re-applying.

**2. Point the other two modules at that bucket.** Edit the hardcoded `bucket = "srehomelab-tfstate"` in [`iac/hetzner/backend.tf`](../iac/hetzner/backend.tf) and [`iac/aws/backend.tf`](../iac/aws/backend.tf) to the name you just chose — backend blocks can't reference variables, so this is a literal string edit, not a `tfvars` change.

**3. Fill in `iac/hetzner/terraform.tfvars`** (gitignored, never commit it):

```hcl
hcloud_token       = "..."
project_code       = "homelab"
environment        = "dev"
vpc_cidr           = "10.100.0.0/16"
subnet_ip_range    = "10.100.0.0/24"
server_private_ip  = "10.100.0.2"
allowed_mgmt_ips   = ["<your-public-ip>/32"]
nodes = {
  "01" = { server_type = "cpx32", ip = "10.100.0.2" }
}
github_token       = "..."
github_repo_url    = "https://github.com/<you>/sre-homelab-gitops.git"
oidc_issuer_url    = "https://oidc.<your-subdomain>"
```

`allowed_mgmt_ips` gates both SSH (22) and the Kubernetes API (6443) to that CIDR. It has to match your *current* public IP, and it will drift — see [Operations](operations.md#ip-drift-and-the-firewall).

**4. Apply the `hetzner` stack.**

```bash
cd iac/hetzner
terraform init
terraform apply
```

This creates the network, firewall, signing key, and server, and boots k3s with OIDC federation already configured. The issuer URL won't resolve yet — that's expected and harmless, since nothing has tried to validate a token against it so far.

**5. Fill in `iac/aws/terraform.tfvars`:**

```hcl
state_bucket_name = "<the bucket from step 1>"
dns_zone_name      = "<your-subdomain>"
```

Then create only the DNS zone first:

```bash
cd iac/aws
terraform init
terraform apply -target=aws_route53_zone.homelab
```

`-target` here is deliberate, not a smell: everything else in this stack blocks on a delegation that only exists once you've completed the next step, and that step needs the nameservers this creates.

**6. Delegate DNS at your registrar.** `terraform output zone_nameservers` prints four nameservers. Create NS records for your subdomain at whichever provider hosts your domain's apex, pointing at those four — DNS-only, not proxied if your registrar offers that toggle. Confirm propagation before continuing:

```bash
dig +short NS <your-subdomain> @1.1.1.1
```

Nothing further will work until this resolves.

**7. Finish the `aws` apply.**

```bash
terraform apply
```

This validates the ACM certificate, stands up CloudFront, publishes the JWKS, creates the IAM OIDC provider, and creates the `cert-manager-route53` role. Note `terraform output hosted_zone_id` and `terraform output cert_manager_role_arn` — you need both next.

**8. Wire the outputs into your gitops fork.** `apps/cert-manager/cluster-issuer.yml` in [`sre-homelab-gitops`](https://github.com/sbhiii/sre-homelab-gitops) hardcodes `hostedZoneID` and `role` as literal values — they are not templated across repos. Edit that file with the two outputs from the previous step, and set `apps/cert-manager/cluster-issuer.yml`'s `email` field to a real address you control (Let's Encrypt sends expiry notices there and doesn't verify deliverability). Commit and push.

**9. Watch it converge.** ArgoCD is already running and pointed at your gitops fork from step 4. Within a few minutes, `cert-manager` should sync, obtain a certificate for your ArgoCD hostname via DNS-01 through the role you just created, and Traefik should start serving it.

```bash
export KUBECONFIG=./k3s-config.yaml   # see Operations for how to fetch this
kubectl -n argocd get applications
kubectl get certificate -A
```

Next: [Operations](operations.md) for what running this day-to-day looks like, or [Security model](security.md) for what is and isn't protected.

---

[← Back to README](../README.md) · [Architecture →](architecture.md)

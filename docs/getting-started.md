[← Back to README](../README.md) · [Architecture](architecture.md) · [Operations](operations.md) · [Security model](security.md)

# Getting started

## Prerequisites

### Tools

| Tool | Used for | Notes |
|---|---|---|
| [Terraform](https://developer.hashicorp.com/terraform) | everything under `iac/` | `required_version = "~> 1.15"` in all three modules |
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

- **A Hetzner Cloud project**, with an API token and an SSH key already uploaded to it. The SSH key must exist under a name that matches `data "hcloud_ssh_key" "samy_ssh"` in [`iac/hetzner/main.tf`](../iac/hetzner/main.tf) — either rename your key to `samy-macbook-pro-ssh` or edit that data source to look up your own.
- **An AWS account.** IAM permissions to create S3 buckets, CloudFront distributions, ACM certificates, and IAM OIDC providers/roles. This deployment applies into a member account of an AWS Organization, authenticating through IAM Identity Center rather than an IAM user, so no long-lived AWS credential exists for these stacks.
- **A delegated subdomain, with its hosted zone already created.** This repository does not create the zone. It looks one up by name and writes records into it, so the zone and its NS delegation must both exist first. They belong to whatever owns your DNS structure, which for this deployment is [`sbhi-aws-landing-zone`](https://github.com/sbhiii/sbhi-aws-landing-zone); the reasoning is recorded there as decision 14. Terraform cannot perform the delegation itself, so that remains the one genuinely manual step, it just happens before this walkthrough rather than inside it.
- **A GitHub repository forked from [`homelab-gitops`](https://github.com/sbhiii/homelab-gitops)**, plus a token ArgoCD can use to read it — classic PAT with `repo` scope, or a fine-grained PAT scoped to that repository with `Contents: Read`.

### Background knowledge

This project assumes comfort with, roughly in order of how load-bearing they are:

- **Terraform**: modules, remote state, and the `data "terraform_remote_state"` pattern, which is how the `aws` stack reads the signing public key out of the `hetzner` stack.
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
cp terraform.tfvars.example terraform.tfvars   # then fill it in
terraform init
terraform apply
```

This is local state, on purpose — see [`iac/bootstrap/README.md`](../iac/bootstrap/README.md). Keep that state file safe; losing it means `terraform import`-ing the bucket back rather than just re-applying.

**2. Point the other two modules at that bucket.** Edit the hardcoded `bucket = "sbhi-homelab-tfstate"` in [`iac/hetzner/backend.tf`](../iac/hetzner/backend.tf) and [`iac/aws/backend.tf`](../iac/aws/backend.tf) to the name you just chose — backend blocks can't reference variables, so this is a literal string edit, not a `tfvars` change.

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
github_repo_url    = "https://github.com/<you>/homelab-gitops.git"
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

**5. Confirm the delegation resolves.** The zone is looked up by name, not created here, so the whole stack fails at plan time if it does not exist, and `aws_acm_certificate_validation` hangs until the delegation actually resolves.

```bash
dig +short NS <your-subdomain> @1.1.1.1
```

Nothing further will work until this returns the zone's nameservers.

**6. Fill in `iac/aws/terraform.tfvars` and apply.**

```hcl
shared_services_account_id = "<the account this applies into>"
state_bucket_name          = "<the bucket from step 1>"
dns_zone_name              = "<your-subdomain>"
```

```bash
cd iac/aws
terraform init
terraform apply
```

This validates the ACM certificate, stands up CloudFront, publishes the JWKS, creates the IAM OIDC provider, and creates the `cert-manager-route53` role. Note `terraform output hosted_zone_id` and `terraform output cert_manager_role_arn` — you need both next.

**7. Wire the outputs into your gitops fork.** `apps/cert-manager/cluster-issuer.yml` in [`homelab-gitops`](https://github.com/sbhiii/homelab-gitops) hardcodes `hostedZoneID` and `role` as literal values — they are not templated across repos. Edit that file with the two outputs from the previous step, and set `apps/cert-manager/cluster-issuer.yml`'s `email` field to a real address you control (Let's Encrypt sends expiry notices there and doesn't verify deliverability). Commit and push.

**8. Watch it converge.** ArgoCD is already running and pointed at your gitops fork from step 4. Within a few minutes, `cert-manager` should sync, obtain a certificate for your ArgoCD hostname via DNS-01 through the role you just created, and Traefik should start serving it.

```bash
export KUBECONFIG=./k3s-config.yaml   # see Operations for how to fetch this
kubectl -n argocd get applications
kubectl get certificate -A
```

Next: [Operations](operations.md) for what running this day-to-day looks like, or [Security model](security.md) for what is and isn't protected.

---

[← Back to README](../README.md) · [Architecture →](architecture.md)

[← Back to README](../README.md) · [Architecture](architecture.md) · [Getting started](getting-started.md) · [Operations](operations.md)

# Security model

## What has genuinely no credential

`cert-manager`'s path to Route53. No access key exists in this repo, in the cluster, or in any Kubernetes Secret. A token is minted, exchanged, and expires within the hour. See [Architecture: the OIDC trust chain](architecture.md#the-oidc-trust-chain) for the mechanism.

## What's still a secret, and where it lives

The ServiceAccount signing private key, which sits in Terraform state (in the S3 bucket from `iac/bootstrap`, encrypted at rest and access-controlled) and briefly in the rendered `user_data` during cloud-init. Anyone holding that key can forge a token for *any* ServiceAccount in the cluster and assume the AWS role. This was a deliberate, documented trade-off against the alternative of holding it in AWS SSM instead — see the design notes in the commit history for `iac/hetzner/keys.tf` if you want the full reasoning.

## The metadata-service mitigation

Hetzner serves cloud-init `user_data` unauthenticated at `http://169.254.169.254/hetzner/v1/userdata` — confirmed against Hetzner's own cloud-init datasource source code, not just inference. That endpoint is not internet-reachable (`169.254.0.0/16` is link-local, non-routable), but it *is* reachable from inside any pod on the cluster by default. Verified directly: a throwaway pod with no special privileges reading that address recovered both the signing private key and the GitHub PAT in one `curl`.

`iac/hetzner/scripts/init-cluster.sh.tftpl` installs a `systemd` unit that adds one `iptables` rule on the node's `FORWARD` chain, blocking `10.42.0.0/16` (the pod network) from reaching `169.254.169.254`, while leaving the node's own access on `OUTPUT` untouched — it needs that access, earlier in the same script, to look up its own public IP. `hostNetwork` DaemonSets (a CSI driver, a cloud-controller-manager, if this cluster ever grows one) traverse `OUTPUT` too and are unaffected. This is host-level containment: it protects every namespace equally and requires no per-namespace configuration, unlike a Kubernetes `NetworkPolicy` (which the gitops repo also carries, as defense in depth, but which cannot cover namespaces it isn't explicitly applied to).

**Known gap:** this rule is a mitigation for one specific address, not a general pod-egress policy. A pod can still reach the wider internet, and nothing here restricts lateral movement between pods.

## Known limitations

Listed plainly, because a project that hides its rough edges is less useful to read than one that doesn't:

- **The JWKS publishes a single key.** No rotation-with-overlap is supported; see [Operations: rotating the signing key](operations.md#rotating-the-signing-key).
- **`ClusterIssuer` values are copied by hand across repos.** `hosted_zone_id` and `cert_manager_role_arn` are Terraform outputs in this repo, but literal hardcoded strings in the gitops repo's YAML. There is no automation gluing the two together — a `terraform_remote_state` data source consumed by a script, or an ArgoCD `ApplicationSet` generator, would close this gap at the cost of more moving parts.
- **`server_private_ip` in `iac/hetzner/variables.tf` is declared, validated, and never actually used** by any resource — each node's IP comes from `var.nodes[key].ip` instead. Harmless, but worth knowing before assuming it does something.
- **The SSH key lookup is by a hardcoded name**, not a variable — see [Getting started: Accounts](getting-started.md#accounts).
- **This deployment's own AWS credentials are an admin-scoped IAM user (`iamadmin`)**, not a dedicated role or account. A more careful setup would use a separate AWS account (via AWS Organizations, which is free) or at minimum a purpose-built IAM role assumed via `sts:AssumeRole`, since these stacks create IAM roles and an OIDC provider — permissions close to administrative by nature regardless of how tightly they're scoped.
- **No CI.** Nothing currently runs `terraform fmt -check` / `terraform validate` on a pull request; it's done by hand before merging.
- **Single node, single region.** There's no failure-domain redundancy here — this is a homelab, not a production SLA.

---

[← Back to README](../README.md)

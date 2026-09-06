[← Back to README](../README.md) · [Architecture](architecture.md) · [Getting started](getting-started.md) · [Operations](operations.md)

# Security model

## What has genuinely no credential

`cert-manager`'s path to Route53, and External Secrets' path to SSM Parameter Store. No access key exists in this repo, in the cluster, or in any Kubernetes Secret. A token is minted, exchanged, and expires within the hour. See [Architecture: the OIDC trust chain](architecture.md#the-oidc-trust-chain) for the mechanism.

The second consumer crosses an account boundary: External Secrets assumes a role in `sbhi-homelab` using a token signed by this cluster, validated against a JWKS this repo publishes. Adding it needed one more `aws_iam_openid_connect_provider` and one more role, and no new credential mechanism.

## What's still a secret, and where it lives

The ServiceAccount signing private key, and nothing else. It sits in Terraform state (in the S3 bucket from `iac/bootstrap`, encrypted at rest and access-controlled) and briefly in the rendered `user_data` during cloud-init. Anyone holding that key can forge a token for *any* ServiceAccount in the cluster and assume either AWS role. This was a deliberate, documented trade-off against the alternative of holding it in AWS SSM instead — see the design notes in the commit history for `iac/hetzner/keys.tf` if you want the full reasoning.

SSM parameter *values* are deliberately outside Terraform. `aws_ssm_parameter.value` is a `computed` attribute, so it is read back into state on every refresh whatever `ignore_changes` says; managing values there would move every application secret into the bucket that already holds the signing key. They are written by hand with `aws ssm put-parameter`, and `iac/aws-homelab` grants access to a path prefix without ever seeing what is at it.

## The metadata-service mitigation

Hetzner serves cloud-init `user_data` unauthenticated at `http://169.254.169.254/hetzner/v1/userdata` — confirmed against Hetzner's own cloud-init datasource source code, not just inference. That endpoint is not internet-reachable (`169.254.0.0/16` is link-local, non-routable), but it *is* reachable from inside any pod on the cluster by default. Verified directly: a throwaway pod with no special privileges reading that address recovered the signing private key in one `curl`.

`iac/hetzner/scripts/init-cluster.sh.tftpl` installs a `systemd` unit that adds one `iptables` rule on the node's `FORWARD` chain, blocking `10.42.0.0/16` (the pod network) from reaching `169.254.169.254`, while leaving the node's own access on `OUTPUT` untouched — it needs that access, earlier in the same script, to look up its own public IP. `hostNetwork` DaemonSets (a CSI driver, a cloud-controller-manager, if this cluster ever grows one) traverse `OUTPUT` too and are unaffected. This is host-level containment: it protects every namespace equally and requires no per-namespace configuration, unlike a Kubernetes `NetworkPolicy` (which the gitops repo also carries, as defense in depth, but which cannot cover namespaces it isn't explicitly applied to).

**Known gap:** this rule is a mitigation for one specific address, not a general pod-egress policy. A pod can still reach the wider internet, and nothing here restricts lateral movement between pods.

## Known limitations

Listed plainly, because a project that hides its rough edges is less useful to read than one that doesn't:

- **The JWKS publishes a single key.** No rotation-with-overlap is supported; see [Operations: rotating the signing key](operations.md#rotating-the-signing-key).
- **Cross-repo values are copied by hand.** `hosted_zone_id`, `cert_manager_role_arn` and `external_secrets_role_arn` are Terraform outputs in this repo, but literal hardcoded strings in the gitops repo's YAML. There is no automation gluing the two together — a `terraform_remote_state` data source consumed by a script, or an ArgoCD `ApplicationSet` generator, would close this gap at the cost of more moving parts.
- **`server_private_ip` in `iac/hetzner/variables.tf` is declared, validated, and never actually used** by any resource — each node's IP comes from `var.nodes[key].ip` instead. Harmless, but worth knowing before assuming it does something.
- **The SSH key lookup is by a hardcoded name**, not a variable — see [Getting started: Accounts](getting-started.md#accounts).
- **These stacks apply with administrator rights**, obtained through IAM Identity Center rather than an IAM user, into a member account separate from the organization's management account. The earlier admin-scoped `iamadmin` IAM user is gone, and no static AWS credential exists for this repository. The residual weakness is scope rather than credential type: creating IAM roles and an OIDC provider needs permissions close to administrative by nature, so the session is far wider than the four resources it manages. A deploy role with a permissions boundary is the fix, and it becomes worth building when this repo gains CI rather than before.
- **No CI.** Nothing currently runs `terraform fmt -check` / `terraform validate` on a pull request; it's done by hand before merging.
- **Single node, single region.** There's no failure-domain redundancy here — this is a homelab, not a production SLA.

---

[← Back to README](../README.md)

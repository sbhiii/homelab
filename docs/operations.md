[← Back to README](../README.md) · [Architecture](architecture.md) · [Getting started](getting-started.md) · [Security model](security.md)

# Operations

## Fetching a kubeconfig

The API server's certificate is SAN'd to the node's public IP, so:

```bash
IP=$(terraform -chdir=iac/hetzner output -json nodes_public_ips | python3 -c 'import json,sys;print(list(json.load(sys.stdin).values())[0])')
scp root@$IP:/etc/rancher/k3s/k3s.yaml ./k3s-config.yaml
# then edit the `server:` field from 127.0.0.1 to $IP
```

Keep this file outside both repos — it grants cluster-admin. `.gitignore` in this repo blocks `k3s-config.yaml` / `k3s.yaml` as a backstop, but that's not a substitute for actually keeping it elsewhere.

## Re-applying after a node rebuild

Any change to `user_data` — the k3s install flags, the injected manifests, the signing-key logic — forces a full server replacement, not an in-place update. After it lands: the node has a new public IP, so the wildcard record in `iac/aws/apps_dns.tf` is now stale until you `terraform apply` in `iac/aws` again; your kubeconfig needs refetching; and every certificate gets re-issued from scratch (Let's Encrypt allows five duplicate certificates per registered domain per week — don't rebuild repeatedly in one sitting). The signing key, the JWKS, and the entire AWS trust chain are **not** affected — that persistence is the entire point of keeping the key in Terraform state instead of on the node. See [Architecture: the OIDC trust chain](architecture.md#the-oidc-trust-chain) for why.

## IP drift and the firewall

`allowed_mgmt_ips` in `terraform.tfvars` is a static list. When your home or office IP rotates, SSH and the Kubernetes API both silently stop answering until you update it and re-apply. This is the single most common way to lock yourself out of this stack.

## Rotating the signing key

There's no supported way to do this without a rebuild — the JWKS in `iac/aws/discovery.tf` publishes exactly one key, not an old-and-new pair during an overlap window. Rotating means: `terraform destroy` (or `-replace`) the `hcloud_server` resource in `iac/hetzner`, then `terraform apply` in `iac/aws` to republish the new public key. Budget for a short certificate-issuance gap while that happens.

## Adding a node

`var.nodes` in [`iac/hetzner/variables.tf`](../iac/hetzner/variables.tf) is a map — add a second entry with its own key, IP, and labels. Note `location = "nbg1"` and `network_zone = "eu-central"` are hardcoded in `main.tf`, not exposed as variables; multi-region requires editing the module.

## Cost

This deployment runs a `cpx32` (4 vCPU / 8 GB / 160 GB) Hetzner server at roughly €35/month. Hetzner's cheaper shared-CPU lines (`cx*`, `cax*`) have had little to no stock in EU datacenters at various points — check availability *and* price before picking a `server_type`, since equivalently-specced tiers can differ by several multiples. On the AWS side: a Route53 hosted zone (~$0.50/month), a handful of tiny S3 objects, and a low-traffic CloudFront distribution are all effectively free at this scale.

## Troubleshooting

**`kubectl get --raw /.well-known/openid-configuration` doesn't show your issuer.** The `--kube-apiserver-arg=service-account-issuer` flag didn't take. Check `journalctl -u k3s` on the node for the flags k3s actually launched with.

**`AccessDenied` when a workload tries to assume the role.** This is actually good news, in a narrow sense: it means AWS successfully fetched your JWKS, verified the token's signature, and matched the issuer — and rejected it purely on the trust policy's `sub` or `aud` condition. Check that the calling pod's ServiceAccount and namespace exactly match `system:serviceaccount:cert-manager:cert-manager`, and that it requested the token with `audience=sts.amazonaws.com`.

**`InvalidIdentityToken` instead.** This is the other failure mode, and it means something upstream of the trust policy is actually broken — the `kid` doesn't match, the JWKS is stale or unreachable, or the issuer URL string doesn't match character-for-character (a trailing slash is enough). Start by diffing `curl https://<issuer>/openid/v1/jwks` against `kubectl get --raw /openid/v1/jwks` run directly on the node.

**Certificates stop issuing after a node rebuild, but only briefly.** Expected — see [Re-applying after a node rebuild](#re-applying-after-a-node-rebuild) above. If it doesn't recover within a few minutes, check `kubectl get challenge -A` for the DNS-01 challenge's own status; Route53 errors surface there verbatim.

**SSH or `kubectl` suddenly time out with no config change.** Almost always `allowed_mgmt_ips` no longer matching your current public IP. `curl https://api.ipify.org`, update `terraform.tfvars`, re-apply.

---

[← Back to README](../README.md) · [Security model →](security.md)

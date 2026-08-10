# Enregistrement DNS des applications exposées par l'Ingress du cluster.
#
# Un wildcard plutôt qu'un enregistrement par application : les enregistrements
# explicites l'emportent toujours sur le wildcard, donc oidc.srehomelab.sbhi.io
# continue de pointer vers CloudFront, et toute nouvelle application exposée par
# un Ingress fonctionne sans modifier ce fichier.
#
# L'IP vient du remote state de la stack hetzner, comme la clé publique de
# signature. Un remplacement du noeud change l'IP : il faut alors réappliquer
# cette stack pour mettre l'enregistrement à jour.
resource "aws_route53_record" "apps_wildcard" {
  zone_id = aws_route53_zone.homelab.zone_id
  name    = "*.${var.dns_zone_name}"
  type    = "A"
  ttl     = 300
  records = [local.node_public_ip]
}

locals {
  # La stack hetzner expose une map indexée par identifiant de noeud.
  node_public_ip = data.terraform_remote_state.hetzner.outputs.nodes_public_ips[var.ingress_node_id]
}

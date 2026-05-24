# NOTE: *.hosts.<apex> entries are Njalla "Dynamic" records, not plain A —
# Njalla stores the per-record DDNS update key in the `content` field
# instead of an IP, and the unauthenticated njal.la/update endpoint each
# host's njalla-ddns systemd unit uses only works with that record type.
# Sighery's terraform-provider-njalla doesn't model the Dynamic type, so
# these records are created + rotated in Njalla's web UI and live outside
# tofu state. If a future provider adds Dynamic support we can fold them
# in here.

# CNAME each Caddy-fronted service subdomain on moon to the DDNS-managed
# host. Resolution chases the CNAME → DDNS A record, so a LAN-IP change is
# picked up by every subdomain without any tofu run.
#
# Subdomain list is the same JSON file moon's Caddy config reads, so add/
# remove there and both apply.
locals {
  moon_domains_file = "${path.module}/../../modules/nixos/hosts/moon/domains.json"
  moon_subdomains   = toset(keys(jsondecode(file(local.moon_domains_file))))
}

resource "njalla_record_cname" "moon_service" {
  for_each = local.moon_subdomains

  domain  = var.apex_domain
  name    = each.value
  content = "moon.hosts.moreirafernandes.com"
  ttl     = var.dns_ttl
}

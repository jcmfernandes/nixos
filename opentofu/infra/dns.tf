# Each host's njalla-ddns systemd unit publishes its address through
# njal.la/update, which only works with Njalla "Dynamic" records: Njalla
# generates the record's DDNS update key, kept in sops on the host.
# Replacing a record generates a new key and breaks that host's updates.
locals {
  ddns_hosts = toset(["anuchka", "karma", "moon", "moon.internal", "vivivi"])
}

resource "njalla_record_dynamic" "host" {
  for_each = local.ddns_hosts

  domain = var.apex_domain
  name   = "${each.value}.hosts"

  lifecycle {
    prevent_destroy = true
  }
}

# CNAME each Caddy-fronted service subdomain on moon to the DDNS-managed
# host. Resolution chases the CNAME → DDNS A record, so an address change is
# picked up by every subdomain without any tofu run. moon publishes its
# tailscale IP there, so these services resolve usefully only on the tailnet.
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

# Same services under <name>.internal, CNAMEd to the DDNS record holding
# moon's LAN IP, for LAN devices that can't join the tailnet.
resource "njalla_record_cname" "moon_service_internal" {
  for_each = local.moon_subdomains

  domain  = var.apex_domain
  name    = "${each.value}.internal"
  content = "moon.internal.hosts.moreirafernandes.com"
  ttl     = var.dns_ttl
}

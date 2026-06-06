# vivivi access model — tailscale-only

vivivi has a public OCI IP but it is **firewalled to inbound UDP 41641
only** (tailscale's WireGuard port). Everything else — SSH, the attic
binary cache on 8080, future services — is reachable **only through
the tailnet** (`tailscale0` is a trusted interface, so the NixOS firewall
doesn't block traffic arriving on it). Two defenses are stacked:

- **OCI security list** (`opentofu/infra/builder.tf`,
  `oci_core_security_list.vivivi`): the only `ingress_security_rule` is
  UDP 41641 from `0.0.0.0/0`. Egress is unrestricted (tailscale's
  control-plane + DERP relay traffic to `*.tailscale.com` and DERP
  nodes needs that).
- **NixOS firewall** (`modules/nixos/hosts/vivivi/configuration.nix`):
  `firewall.allowedTCPPorts = []`. `services.tailscale.openFirewall`
  (default `true`) adds the UDP 41641 hole and the trusted-interface
  rule for `tailscale0`.

## Reaching vivivi

```sh
# Via MagicDNS (any tailnet member):
ssh jcmfernandes@vivivi

# Or by tailscale IP if MagicDNS isn't configured:
tailscale status | awk '/vivivi/ {print $1}'
ssh jcmfernandes@<that-100.x.x.x>
```

The public IP is intentionally **not** an access path. If tailscale on
vivivi breaks (e.g. authkey rotation gone wrong, daemon crash), recovery
goes through the OCI serial console — see the broader OCI debugging
section of the OCI docs or use:

```sh
# from opentofu/, with oci-config + oci.pem extracted from sops:
oci compute instance-console-connection create \
  --instance-id <vivivi-ocid> \
  --ssh-public-key-file console-rsa.pub
```

(generate `console-rsa.pub` once via
`ssh-keygen -t rsa -b 2048 -f console-rsa -N ''`; OCI rejects ed25519
for console connections.)

## Deploy order when changing the firewall

Both layers can be changed at any time, but the **order matters** when
tightening (loosening is always safe):

1. **First** confirm tailscale access to vivivi works
   (`ssh jcmfernandes@vivivi` from a tailnet member returns a prompt).
2. **Then** `tofu apply` the OCI security-list change.
3. **Then** `nixos-rebuild switch --flake .#vivivi --target-host
   root@vivivi --build-host root@vivivi` to land the NixOS-side
   firewall.

If you skip step 1 and the apply in step 2 closes public-IP SSH while
tailscale isn't yet reachable, the only recovery is the OCI serial
console.

## Bootstrapping a fresh vivivi (or recreating it)

The steady-state firewall above has a chicken-and-egg problem when the
instance is *first* provisioned (or recreated): the fresh OCI image is
plain Ubuntu without tailscale installed, so the only inbound it can
accept is SSH-22 — which the security list normally blocks.

There's a **commented-out `ingress_security_rules` block for TCP 22**
in `opentofu/infra/builder.tf` for exactly this case. Workflow:

1. Uncomment the TCP-22 block (restricted to `var.ssh_allowed_cidr`).
2. `tofu apply` to open the hole.
3. `tofu apply -replace=oci_core_instance.vivivi` (or the initial
   `tofu apply` if you're provisioning from zero).
4. Run `nixos-anywhere` against the fresh Ubuntu instance over SSH-22
   (see the install runbook elsewhere).
5. Once vivivi has booted into NixOS and tailscale has registered with
   the tailnet, **re-comment the TCP-22 block** and `tofu apply` again
   to close the hole. From this point on, day-to-day access is
   tailnet-only as described above.

Skipping step 5 leaves the public IP accepting SSH long after vivivi
has tailscale-based access — the auth is still key-based so it's not a
disaster, but it widens the attack surface vivivi was specifically set
up to avoid.

# TODO

Rollout of Calibre-Web and the `*.internal` LAN names on moon.

1. Put `opentofu/infra/terraform.tfvars` on karma: copy it from the machine
   that has it, or fill in `terraform.tfvars.example`.
2. In the Njalla web UI, create a **Dynamic** record `moon.internal.hosts`
   and copy its key.
3. `sops secrets/moon.yaml`: in `njalla_ddns_env`, add
   `DDNS_KEY_INTERNAL=<key>`. Do this before deploying, or the DDNS job
   fails every 5 minutes.
4. `cd opentofu/infra && tofu plan && tofu apply`. Expect new CNAMEs:
   `calibre` and one `<name>.internal` per entry in
   `modules/nixos/hosts/moon/domains.json`.
5. Deploy moon:
   `nixos-rebuild switch -S --flake .#moon --target-host root@moon --build-host root@moon`
6. From a device at home: `nslookup calibre.internal.moreirafernandes.com`
   must return moon's LAN IP. No answer means the router's DNS rebind
   protection blocks it; allow the name there.
7. Open Calibre-Web, log in as `admin` / `admin123`, change the password.
8. In KOReader, add the OPDS catalog
   `https://calibre.internal.moreirafernandes.com/opds`.
9. Once step 8 works, close port 8083 on moon (drop
   `services.calibre-web.openFirewall`).

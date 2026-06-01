# Homelab TODO

Persistent backlog so context can be closed/reopened without losing momentum.
When picking up work, scan the **In progress** and **Next up** sections.

## Done

- [x] Ansible bootstrap working end-to-end (`make bootstrap REMOTE_USER=u1frob PRIVATE_KEY=~/.ssh/<key>`)
- [x] `make ping` succeeds against `homeserver` (192.168.88.6) as the `ansible` user

## In progress

_(nothing yet — pick from Next up)_

## Next up: Immich + restic to Backblaze B2

### Decided
- **Container runtime:** Podman (rootless) + Quadlets (systemd `.container` units) — no Docker daemon
- **ML:** All features enabled (smart search via CLIP + face recognition). No GPU — initial indexing will be slow but day-to-day is fine.
- **Access:** Start LAN-only, add Cloudflare Tunnel later as a separate step

### Server facts
- **OS:** Ubuntu 24.04.4 LTS
- **ZFS pool:** `data` (3.51T avail), dataset `data/photos` → `/data/photos` (96K used, effectively empty)
- **Proposed layout:** create `data/immich` → `/data/immich` for postgres + ML model cache; use `/data/photos` as Immich upload/library dir
- **Podman:** available in Ubuntu 24.04 repos (4.9.x), Quadlets supported

### Still open (need your answers before writing playbooks)
1. ZFS layout — confirm: `data/immich` for app data + `/data/photos` for library? Or put everything under one dataset?
2. Backblaze B2 bucket name + keyID + applicationKey (create in B2 dashboard if not done)?
   - Credentials go in `ansible-vault`, not plain text
4. Restic repo password — save in Bitwarden **now** before starting

### Tasks (in order)
- [x] Answer open questions above
- [x] Playbook: `playbooks/podman.yml` — install Podman + slirp4netns
- [x] Playbook: `playbooks/zfs.yml` — install ZFS, create pool + datasets (idempotent)
- [x] `host_vars/homeserver.yml` — pool disk + dataset config
- [x] Quadlet templates: postgres, redis, server, machine-learning + immich.network
- [x] Playbook: `playbooks/immich.yml` — dirs, env file, Quadlets, systemd
- [x] Vault automation: `ansible.cfg` vault_password_file = .vault_password (gitignored)
- [ ] Create `.vault_password` locally: `openssl rand -base64 20 > .vault_password`
- [ ] Create vault: `make vault CMD="create group_vars/homelab_vault.yml"` (keys: immich_db_password, immich_secret_key)
- [ ] Run `make run` (kör alla playbooks i ordning)
- [ ] Verify Immich is reachable at http://192.168.88.6:2283
- [ ] Playbook: install restic, configure B2 backend, ZFS snapshot + daily systemd timer
- [ ] Test restore from B2 to scratch directory (verify backups actually work)
- [ ] DNS / TLS — Cloudflare Tunnel (separate playbook, later)
  - Familjeåtkomst via delade album i Immich (inte hela biblioteket)
  - Tailscale för eget bruk, Cloudflare Tunnel för familj

## Next up: GitHub Actions pipeline

Upplägg:
- PR öppnad → GitHub-hosted runner → ansible-lint (ingen server-access)
- PR öppnad → self-hosted runner   → make check (dry-run mot server, read-only)
- Merge → main → du kör `make run` manuellt (ingen automatisk deploy)

Säkerhet:
- Repot görs publikt — "Require approval for all outside collaborators" aktiveras i GitHub Settings
- YubiKey som 2FA på GitHub-kontot (redan planerat)
- Self-hosted runner kör som dedikerad användare med begränsade sudo-rättigheter
- Inga hemligheter som GitHub Secrets — vault-lösenord och SSH-nyckel stannar på servern
- Pinea ALLA externa Actions till commit-hash (inte @v4-taggar)
- Aktivera Dependabot för automatiska PR:ar när pinnade actions uppdateras

Tasks:
- [ ] Playbook: installera och registrera GitHub Actions self-hosted runner på servern
- [ ] `.github/workflows/ci.yml` — lint (GitHub-hosted) + dry-run (self-hosted)
- [ ] Pinea alla actions till commit-hash
- [ ] Aktivera Dependabot för GitHub Actions
- [ ] Aktivera "Require approval for outside collaborators" i repo-inställningar
- [ ] Gör repot publikt

## Backlog: migrera till SOPS

- [ ] Byt från ansible-vault till SOPS + age-nyckel
- [ ] Lokalt: age-nyckel på YubiKey via PIV-sloten — hårdvarubundet, ingen nyckel i klartext
- [ ] CI: age-nyckel som GitHub Secret (eller Bitwarden SM machine token)
- [ ] SOPS stödjer flera mottagare — samma vault-fil krypteras för YubiKey-nyckeln + CI-nyckeln
- [ ] Installera `community.sops` Ansible-plugin
- [ ] Migrera `group_vars/homelab/vault.yml` till SOPS-format
- [ ] Git-historiken innehåller ansible-vault-krypterad vault.yml — rotera lösenordet efter migration
- [ ] OBS: `bws` CLI autentiserar med access token, inte YubiKey — SOPS+PIV är rätt väg för hårdvarubundet lokalt flöde

## Backlog: secrets & pipeline

- [ ] Sätt upp Bitwarden Secrets Manager (gratisnivå räcker)
  - Installera `bws` CLI: `brew install bitwarden-secrets-manager`
  - Skapa secret för vault-lösenordet, notera secret-ID
  - Byt ut `.vault_password`-filen mot `scripts/vault-password.sh` som kör `bws secret get <id>`
  - Skapa machine account + access token för CI
- [ ] Välj CI/CD-platform (GitHub Actions?)
- [ ] Pipeline: `make run` triggas på push till main, secrets från Bitwarden SM

## Backlog / polish

- [ ] Pin `ansible_python_interpreter: /usr/bin/python3.12` in `group_vars/all.yml` to silence discovery warning
- [ ] Update `allowed_networks` in `group_vars/all.yml` — currently `192.168.0.0/26`, but actual LAN is `192.168.88.0/24`. UFW playbook will lock you out otherwise.
- [ ] Disable `PasswordAuthentication` in sshd for u1frob (after confirming key auth works)
- [ ] Save `~/.ssh/ansible` private key to Bitwarden as a secure note (currently only on this mac)
- [ ] Replace `ansible.cfg` `host_key_checking = False` with a checked-in `known_hosts` once the server is stable

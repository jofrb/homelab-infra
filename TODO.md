# Homelab TODO

Persistent backlog so context can be closed/reopened without losing momentum.
When picking up work, scan the **In progress** and **Next up** sections.

## Current setup

- **Server:** Ubuntu 24.04.4 LTS, 32 GB RAM, ZFS pool `data` (3.51T, single 4TB NVMe)
- **VPN:** WireGuard on router, Mac, and phone
- **Ansible:** Dockerized runner on Mac
- **Immich:** Running via Podman Quadlets, accessible at `http://192.168.88.6:2283`
  - ZFS datasets: `data/photos` → `/data/photos` (library), `data/immich` → `/data/immich` (postgres + ML cache)
  - Podman rootless + Quadlets (systemd `.container` units)
  - Vault credentials in `group_vars/homelab/vault.yml` (ansible-vault encrypted)

## Done

- [x] Ansible bootstrap working end-to-end (`make bootstrap REMOTE_USER=u1frob PRIVATE_KEY=~/.ssh/<key>`)
- [x] `make ping` succeeds against `homeserver` (192.168.88.6) as the `ansible` user
- [x] Immich deployed and reachable at http://192.168.88.6:2283

## In progress

### 1. Restic + Backblaze B2
- [x] Playbook: install restic, configure B2 backend, daily systemd timer for `/data/photos`
- [ ] Create B2 bucket + application key in Backblaze dashboard
- [ ] Add B2 credentials + restic repo password to ansible-vault
- [ ] Test restore from B2 to scratch directory (verify backups actually work)

## Roadmap

### 1. Restic + Backblaze B2 — backup Immich

See **In progress** section.

### 2. AdGuard Home — DNS ad blocking + parental controls

- Run directly on router (no server dependency, survives reboots)
- Per-device scheduling, category blocking, clean dashboard
- [ ] Install and configure AdGuard Home on router

### 3. Traefik — reverse proxy

- Clean URLs (`immich.home`, `uptime.home` etc) instead of raw IPs and ports
- Automatic TLS via Let's Encrypt when exposing via Cloudflare Tunnel
- Single entry point — do this before adding more services
- [ ] Playbook: deploy Traefik container + config
- [ ] Migrate Immich to sit behind Traefik

### 4. Cloudflare Tunnel — external access

- Expose services externally without opening ports on the router
- Family access via shared Immich albums
- [ ] Playbook: deploy Cloudflare Tunnel (after Traefik)
- [ ] DNS for Immich and other services

### 5. Monitoring stack — Uptime Kuma + Grafana + Prometheus

- **Uptime Kuma:** uptime checks for all services + GitHub Pages
- **Grafana + Prometheus + Node Exporter:** CPU, RAM, disk, network, ZFS health, per-container usage
- [ ] Playbook: deploy Prometheus + Node Exporter
- [ ] Playbook: deploy Grafana with dashboards
- [ ] Playbook: deploy Uptime Kuma
- [ ] Configure monitors for all running services + GitHub Pages

### 6. Ntfy — push notifications

- Self-hosted push notification server
- Used by Uptime Kuma, restic, Healthchecks, Watchtower etc
- [ ] Playbook: deploy Ntfy container
- [ ] Wire up Uptime Kuma + restic alerts to Ntfy

### 7. Umami — website analytics

- Cookieless, GDPR-compliant, no banner needed
- Tracks pageviews, referrers, devices for GitHub Pages site
- Single container + Postgres
- [ ] Playbook: deploy Umami
- [ ] Add script tag to GitHub Pages site

### 8. Knowledge repository — Syncthing + git history + Codex CLI access

- **Sync:** Syncthing, three peers — Mac, phone, server — all over WireGuard only
  (disable public discovery/relay servers, no NAT traversal needed)
- Obsidian vault lives at `/data/knowledge` on the server (own ZFS dataset,
  mirrors the `data/photos` pattern); iOS via Möbius Sync (~$10 one-time,
  since Syncthing itself doesn't run standalone on iOS)
- **History:** small watcher on the server (`inotify` + debounce, systemd
  path unit) auto-commits `/data/knowledge` to a local git repo on every
  change — catches edits from any peer (Mac, phone, or agent) without
  needing a git client on mobile. Improves conflict *resolution*
  (diff/merge a `.sync-conflict` file) — doesn't prevent Syncthing conflicts
  from occurring in the first place
- **Intelligence access:** Codex CLI installed on the server, run inside
  `tmux` for persistence; ChatGPT mobile app's remote relay (QR-pair) gives
  phone-initiated *new* sessions, not just reattach — the gap Claude Code's
  remote control has today. Inference always runs on OpenAI's servers
  regardless of where the CLI is invoked from, so server hardware is a
  non-issue
- **Backup:** extend the restic → B2 setup (see item 1) to also cover
  `/data/knowledge`, with its own tag; consider a tighter retention window
  than the daily photos timer since text changes are cheap to snapshot —
  decide when picking this up
- [ ] Playbook: deploy Syncthing (Mac + phone + server peers)
- [ ] Create `data/knowledge` ZFS dataset, mount at `/data/knowledge`
- [ ] Set up Obsidian vault sync (Mac, phone via Möbius Sync)
- [ ] Playbook: git auto-commit watcher for `/data/knowledge`
- [ ] Install Codex CLI on server, verify `tmux` persistence works over SSH
- [ ] Pair ChatGPT mobile app remote relay to the server
- [ ] Extend restic backup paths + tag for `/data/knowledge` (after item 1
      is done)

### 9. Paperless-ngx — document archive

- OCRs scanned documents, makes PDFs searchable
- Auto-tags by rules (sender, type etc), ML-assisted suggestions
- Self-hosted archive for deklarationer, kvitton, försäkringar
- [ ] Playbook: deploy Paperless-ngx

### 10. Vaultwarden — self-hosted Bitwarden

- Bitwarden app caches passwords locally — works offline if server is down
- Consider keeping Bitwarden subscription as fallback or export vault regularly
- [ ] Playbook: deploy Vaultwarden
- [ ] Migrate Bitwarden account to self-hosted server

### 11. Forgejo — GitHub mirror

- Lightweight self-hosted Git (GitHub-like UI)
- Use push mirrors to auto-sync GitHub repos locally — GitHub stays primary
- [ ] Playbook: deploy Forgejo
- [ ] Configure push mirrors for GitHub repos

### 12. Home Assistant — home automation

- [ ] Playbook: deploy Home Assistant container
- [ ] Future: Frigate (IP cameras + local AI detection) + ESPHome (DIY sensors)

### 13. Security hardening

- **Fail2ban:** host-level IP banning after repeated failed logins
- **CrowdSec:** intrusion detection, watches logs and auto-bans suspicious IPs — good once services are exposed via Cloudflare Tunnel
- [ ] Playbook: install and configure Fail2ban
- [ ] Playbook: deploy CrowdSec

### 14. Changedetection.io — website change monitoring

- Monitors any website for changes, notifies via Ntfy
- Useful for price tracking, pages without RSS
- [ ] Playbook: deploy Changedetection.io

### 15. Watchtower — container update notifications

- Watches for new container image versions, notifies via Ntfy
- Set to notify only, not auto-update
- [ ] Playbook: deploy Watchtower

### 16. Renovate — dependency update PRs

- Opens PRs when container image tags or Ansible roles have updates
- Self-hosted bot, works with GitHub or Forgejo
- [ ] Deploy Renovate bot
- [ ] Configure for this repo

### 17. Healthchecks — cron job monitoring

- Pings via Ntfy if a scheduled job (e.g. restic backup) doesn't check in
- Essential companion to restic
- [ ] Playbook: deploy Healthchecks
- [ ] Wire up restic backup timer to Healthchecks

### 18. GitHub Actions CI pipeline

- PR opened → GitHub-hosted runner → ansible-lint (no server access)
- PR opened → self-hosted runner → `make check` (dry-run against server, read-only)
- Merge to main → run `make run` manually (no auto-deploy)

Security considerations:
- Pin all external Actions to commit hash (not `@v4` tags)
- Enable Dependabot for pinned Actions
- Self-hosted runner runs as dedicated user with limited sudo
- No secrets as GitHub Secrets — vault password + SSH key stay on server
- Enable "Require approval for outside collaborators"

Tasks:
- [ ] Playbook: install and register GitHub Actions self-hosted runner
- [ ] `.github/workflows/ci.yml` — lint (GitHub-hosted) + dry-run (self-hosted)
- [ ] Pin all Actions to commit hash
- [ ] Enable Dependabot for GitHub Actions
- [ ] Enable "Require approval for outside collaborators"
- [ ] Make repo public

### 19. SOPS secrets migration

- Replace ansible-vault with SOPS + age key
- age key on YubiKey via PIV slot — hardware-bound, no plaintext key
- SOPS supports multiple recipients — same vault file encrypted for YubiKey + CI key
- [ ] Install `community.sops` Ansible plugin
- [ ] Migrate `group_vars/homelab/vault.yml` to SOPS format
- [ ] Rotate vault password after migration (git history contains old encrypted vault)

## Backlog / polish

- [ ] Pin `ansible_python_interpreter: /usr/bin/python3.12` in `group_vars/all.yml` to silence discovery warning
- [x] Update `allowed_networks` in `group_vars/all.yml` — `192.168.88.0/24`
- [ ] Disable `PasswordAuthentication` in sshd for u1frob (after confirming key auth works)
- [ ] Save `~/.ssh/ansible` private key to Bitwarden as a secure note (currently only on this Mac)
- [ ] Replace `ansible.cfg` `host_key_checking = False` with a checked-in `known_hosts` once server is stable
- [ ] Immich CLI on Mac for bulk photo import (`npm install -g @immich/cli`)

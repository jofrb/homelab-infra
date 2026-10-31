# Homelab TODO

Persistent backlog so context can be closed/reopened without losing momentum.
When picking up work, scan the **In progress** and **Next up** sections.

## Current setup

- **Server:** Ubuntu 24.04.4 LTS, 32 GB RAM, ZFS pool `data` (3.51T, single 4TB NVMe)
- **VPN:** WireGuard on router, Mac, and phone
- **Ansible:** Dockerized runner on Mac — image pinned by digest, `ansible==10.7.0`,
  Galaxy collections pinned in `requirements.yml`. Server-side apt packages
  (podman, zfsutils-linux, restic) stay unpinned on purpose — Ubuntu's archive only
  keeps the latest revision per release, so hardcoding a version there risks
  breaking a from-scratch reprovision later; the OS layer tracks Ubuntu's own
  update cadence instead. Renovate (`renovate.json`) keeps the client-side pins
  current. Darwin-vs-Linux controller-runtime parity is a separate, deliberately
  deferred question — see item 18, it stops mattering once the self-hosted runner
  exists and real applies move there.
- **Immich:** Running via Podman Quadlets, accessible at `http://192.168.88.6:2283`
  - ZFS datasets: `data/photos` → `/data/photos` (library), `data/immich` → `/data/immich` (postgres + ML cache)
  - Podman rootless + Quadlets (systemd `.container` units)
  - Vault credentials in `group_vars/homelab/vault.yml` (ansible-vault encrypted)

## Done

- [x] Ansible bootstrap working end-to-end (`make bootstrap REMOTE_USER=u1frob PRIVATE_KEY=~/.ssh/<key>`)
- [x] `make ping` succeeds against `homeserver` (192.168.88.6) as the `ansible` user
- [x] Immich deployed and reachable at http://192.168.88.6:2283
- [x] Restic + Backblaze B2 backup for `/data/photos`, restore verified end-to-end
      (97.6 GiB restored to `/data/restic-restore-test`, `diff` against live data clean)
- [x] Server-down heartbeat: `heartbeat.timer` pings healthchecks.io every 10 min,
      which alerts via ntfy.sh when pings stop (`playbooks/heartbeat.yml`)

## In progress

_(nothing yet — pick from Next up)_

## Next up

_(nothing yet — pick from the Roadmap)_

## Roadmap

### 1. Restic + Backblaze B2 — integrity checks

Base backup/restore done (see Done section). Follow-up hardening:

**Context — single-disk ZFS pool, no ECC RAM (both accepted risks):**
`data` pool is one NVMe (`host_vars/homeserver.yml`), no mirror/raidz — confirmed via
`zpool create` in `playbooks/zfs.yml` (single disk arg, no `mirror` keyword) and `lsblk`
showing only one `zfs_member` device. No ECC means a RAM bit-flip before a file is
checksummed can't be caught by anything (ZFS, restic, or manual diffing) — already
accepted, not actionable. Everything below is about the *catchable* corruption: bits
rotting on disk after being written correctly.

**The plan — detect via ZFS, repair via restic (self-healing without a mirror):**
ZFS checksums every block at write time regardless of redundancy; scrub re-verifies
those checksums by reading the whole pool. On a single disk it can't auto-repair (no
second copy locally) — but restic in B2 *is* that second copy, one manual/scripted
step away instead of instant. That's the loop to build:

1. **Detect:** `zpool scrub data`, **weekly**. This is a drive-class call, not an
   NVMe-vs-spinning one: OpenZFS's own guidance is weekly for consumer-grade disks,
   monthly for enterprise-grade — this is a single consumer NVMe, so weekly is the
   correct default, and scrubs are read-only so there's no wear-cost reason to
   stretch the interval.
2. **Identify:** after scrub finishes (`zpool wait -t scrub data`), check
   `zpool status -v data` for a `errors: Permanent errors have been detected in the
   following files:` section — this lists the exact damaged file paths, no manual
   hunting needed.
3. **Repair:** for each flagged path, `restic restore latest --target / --include
   <path>` — restores just that file from B2, not a full 97GB restore.
4. Wrap 1–3 in a script + systemd service/timer (mirrors the `restic-backup` pattern:
   script in `playbooks/templates/`, deployed + enabled via a playbook). Report to
   healthchecks.io like the restic jobs do (slug `zfs-scrub`) — that alerts via
   ntfy.sh on failure *and* on a scrub that never ran.

**Current state on the server (checked 2026-10-23):**
- Scrub only runs via Ubuntu's stock `/etc/cron.d/zfsutils-linux`: **2nd Sunday
  of the month** at 00:24 (server is UTC). TRIM runs the 1st Sunday. No `zfs-*`
  systemd timers exist.
- Last scrub: **2026-09-13**, 0 errors, 32 s (~100 GiB on NVMe). The **2026-10-11
  scrub never happened** because the server was off: `journalctl --list-boots`
  shows boot `254b44d7…` ending 2026-10-04 08:02 and the next boot starting
  2026-10-18 11:44. Cron has no catch-up for missed runs (unlike a systemd timer
  with `Persistent=true`), so the scrub was simply lost.
- `zpool history data` also has **no June scrub** (2026-06-14). Boot history only
  goes back to 2026-06-17, so the cause can't be confirmed, but it fits the same
  pattern.
- `zfs-zed` is active but has no notification target configured, so a scrub that
  *finds* errors (or a degraded pool) alerts no one today. OpenZFS on the server
  is **2.2.2** (`zfs-2.2.2-0ubuntu9.5`), and its `zed.rc` has no `ZED_NTFY_*`
  settings — ZED can't push to ntfy natively.

Caveat (not a blocker): this only works if a restic snapshot *older than the
corruption event* still exists. In practice this is rarely an issue — ZFS returns an
I/O error instead of silently serving corrupted data, so `restic backup` would itself
have errored trying to read an already-corrupted file rather than faithfully backing
up garbage. Common case is "B2 already has a clean copy from before the bit flip."

**Dedup nuance — snapshot count ≠ redundancy:** restic is content-addressed. If a
photo's bytes are unchanged between two snapshots, both point at the *same* stored
blob in B2 — there is one physical copy, not many. Snapshot history gives rollback
for content that *changed* or was deleted; it does **not** give extra copies of
unchanged files to fall back on if that one blob rots. Don't rely on "we have 300
daily snapshots" as redundancy against B2-side bit rot — it isn't.

**The other direction — healing B2 *from* the server, when a B2 blob is the one
that's corrupted:** `restic check --read-data[-subset]` finds it, but a naive
`restic backup` afterwards does **not** fix it — restic's index says that hash
already exists in the repo, so it skips re-uploading without re-verifying the
actual bytes in B2. The real repair sequence:
1. `restic check --read-data` reports the damaged pack ID(s).
2. `restic find --pack <id>` to see which snapshots/files reference it.
3. Remove the bad pack and rebuild the index so restic believes that data is
   genuinely missing (`restic rebuild-index`, possibly after manually deleting the
   corrupt pack object from the bucket).
4. Re-run `restic backup` — now it re-chunks and re-uploads fresh from the
   still-good local copy.

This only works if the local copy is still intact at the time you notice — i.e. it's
mutual healing (B2 heals from server, server heals from B2), not automatic, and it
fails if *both* sides are corrupted for the same file at once. With a single local
disk + single off-site copy (2 copies total, not 3), that joint-failure case has no
recovery path — accepted risk, see risk math below.

**Cadence — final decision: weekly `zpool scrub` + monthly `restic check
--read-data-subset=n/6` (full B2 repo covered every 6 months).**
`--read-data-subset` takes either a random `X%` or a deterministic `n/t` (splits the
repo into `t` equal non-overlapping parts, checks part `n` this run). Cycling `n`
from 1→6 across 6 monthly runs with `t=6` guarantees exactly 100% of the repo
checked every 6 months with zero overlap — better than a random %, which never
guarantees full coverage.

Cost and risk (2026-09, B2 pricing ~$6/TB-month, $0.01/GB egress beyond free tier,
worked for a ~2TB repo):
- ~333GB/month downloaded (1/6 of 2TB) — comfortably under B2's free-egress
  allowance (3× average monthly storage, i.e. ~6TB/month free), so this cadence
  costs **$0** in practice, ~$3.33/month worst-case if ever billed.
- B2 quotes 11 nines annual durability per object (~1e-11/object/year). For a ~2TB
  repo (order 1e5 pack objects) that's roughly a 1-in-100,000 chance of *any*
  single B2-side object loss over 3 years. Requiring the *same* file to *also* be
  corrupted locally in the *same* window multiplies two small independent
  probabilities together — library-wide irreversible-loss risk over a 3-year
  window is comfortably below 1-in-a-million, dominated by B2's durability claim,
  not by how often we check.
- What this math does *not* cover: correlated failures (bad `forget --prune`,
  ransomware hitting both live and backup, lapsed B2 billing, human error) — those
  aren't mitigated by checking more often, they need separate controls (e.g. B2
  Object Lock, currently disabled/accepted).

Tasks:
- [x] Playbook: monthly `restic check --read-data-subset=n/6` timer (cycling `n`
      1→6, restarting every 6 months) to catch B2-side repo corruption before we
      need a restore, not during one — this is a *different* failure mode than ZFS
      scrub (verifies B2's copy, not the local disk)
- [x] Find out why the 2026-10-11 scrub was skipped — server was off 10-04 → 10-18
      (see "Current state" above)
- [x] Check how that boot ended — someone pressed the power button, not a crash
- [x] Playbook: weekly `zpool scrub data` + parse `zpool status -v` + targeted
      restic restore for any flagged files (the detect→identify→repair loop above).
      systemd timer with `Persistent=true` so a missed run catches up after boot;
      ping healthchecks.io check `zfs-scrub` (cron weekly, UTC)
- [x] Decide on the stock cron scrub once the timer exists: comment out only the
      scrub line in `/etc/cron.d/zfsutils-linux` (dpkg conffile — local edit is kept
      on upgrade) and keep the TRIM line, or leave it as a harmless extra run
- [x] ZED → ntfy.sh for pool faults between scrubs (degraded pool, device
      errors). ZED 2.2.2 has no native ntfy support, so deploy a custom zedlet
      (e.g. `/etc/zfs/zed.d/statechange-ntfy.sh`) that curls ntfy.sh with the
      `ZEVENT_*` details. Scrub errors themselves are already covered by the
      scrub script's exit code via healthchecks.io

### 2. AdGuard Home — DNS ad blocking + parental controls

- Runs on the **server** as a Podman Quadlet (`playbooks/adguard.yml`), not the
  router: the MikroTik hEX S is MMIPS, which RouterOS's container package doesn't
  support (check: `/system resource print` → `architecture-name`)
- Per-device scheduling, category blocking, clean dashboard
- Clients get the server as DNS **directly from DHCP**. Going via the router's DNS
  forwarder would make every query look like it came from the router, so per-device
  rules and stats stop working
- Trade-off: DNS depends on server uptime (it was off 2026-10-04 → 10-18). Regular
  devices get `[server, router]` as DNS so they fail open (some OSes query the
  secondary anyway and bypass the filter); kids' devices get the server only
  (fail closed)
- Config goes in git, but only after first-run: the repo file is `AdGuardHome.yaml`
  exactly as AdGuard wrote it (byte-stable, so re-applying is a no-op). `make
  adguard-pull` fetches it from the server (admin hash swapped for a vault
  variable), `make check` shows UI drift as a diff, `make run` writes the repo
  version (stop → write → start), so temporary UI changes last until the next
  apply. Until then it is UI-managed (AdGuard rewrites its own YAML)
- [x] Playbook: deploy AdGuard Home (host network on the LAN IP, first-run setup
      via the install API, ufw rules, `data/adguard` dataset)
- [x] Add `adguard_admin_password` to the vault, apply `playbooks/adguard.yml`,
      verify with `dig @192.168.88.6` (2026-10-25). Upstream is Cloudflare Security
      over DoH, set in the UI like on the router; latency is on par with the router
- [x] Router: DHCP `dns-server=192.168.88.6,192.168.88.1` on `192.168.88.0/26`. The
      router's own upstream (1.1.1.2 + DoH) is independent of AdGuard. Fallback to
      the router tested by stopping AdGuard
- [x] Server's own resolver doesn't depend on AdGuard. The server gets its address
      from a DHCP reservation (not netplan), so its lease carries the DHCP option
      `dns-router-only` (code 6, `0xC0A85801` = 192.168.88.1); a per-lease option
      beats the network's `dns-server`. Checked 2026-10-25 with `resolvectl status`.
      Keep the router's upstream DNS independent of AdGuard, or restic, heartbeat
      and ntfy lose DNS when it's down
- [ ] PR: config in git — `adguard-pull` + templated config, `adguard_admin_password_hash`
      in the vault. Do after the first apply and UI setup; second apply must
      report 0 changed. Also narrow the web UI from `0.0.0.0:3000` to the LAN IP
      via `http.address` (setup mode can't move to a specific IP on the same port)
- [x] ufw: DNS (53) allowed from the WireGuard network `10.0.0.0/24` via
      `adguard_allowed_networks`, not `allowed_networks` (that also opens SSH and
      Immich)
- [ ] Own iPhone (replaces NextDNS): WireGuard profile with `DNS = 192.168.88.6` and
      `AllowedIPs = 192.168.88.6/32, 192.168.88.1/32` (the router address is for the
      pause shortcuts), On-Demand on cellular. The router must not NAT WG→LAN, or
      AdGuard only sees the router IP. Run NextDNS in parallel for a month before
      cancelling: away from home the phone has no DNS if the server or home uplink
      is down
- [ ] Pause switch (router-side, instant): firewall rules at the top of `forward`
      drop traffic from/to addresses in the `paused` list; scripts
      `pause-phone-1`/`resume-phone-1` (and `pause-phones`/`resume-phones`) add or
      remove the IP and flush its connections. Run from an iPhone Shortcut ("Run
      Script Over SSH") as the restricted router user `pause` (LAN + WG only). It
      only covers Wi-Fi: a phone with mobile data falls back to cellular, so use
      Screen Time Downtime for a full stop. Devices are `phone-1`/`phone-2`, no
      names in the router, AdGuard or this repo
- [ ] The two kids' iPhones: static leases with `address-lists=phones` and the DHCP
      option `dns-adguard-only` (code 6, `0xC0A85806` = 192.168.88.6, same mechanism
      as the server's `dns-router-only`), so they never see the router as DNS.
      Identify them with a unique lookup (`identify-1.example.com` in Safari, read
      the client in the Query Log). Use the Wi-Fi address shown in the phone's Wi-Fi
      details; it can change if the network is forgotten. Router forward rule
      dropping port 53/853 from their IPs except to AdGuard; block
      `mask.icloud.com` + `mask-h2.icloud.com` (makes iOS turn Private Relay off on
      the network); per-client blocked services + schedules in the UI (verify each
      on a device)
- [ ] Kids off home Wi-Fi: WireGuard (DNS-only profile, On-Demand) as soft
      enforcement. iOS can't lock an always-on VPN without MDM/supervision, so they
      *can* switch it off; accepted because they're unlikely to look (iOS shows a
      VPN badge and a Settings toggle, so revisit if that changes). Their
      router-side peers must reach only 192.168.88.6:53 (router forward rule),
      never SSH/Immich. Otherwise use Screen Time's web filter, and lock "Cellular
      Data Changes" if the phone should be Wi-Fi-only
- [ ] Once the config has matured (phones, pause switch and per-client rules settled
      in the UI), run `make adguard-pull` (needs the "PR: config in git" item above)
      and commit `AdGuardHome.yaml`. Pulling earlier only captures churn
- [ ] Reminder: progress AdGuard maturity soon. Last touched 2026-10-25; the phone,
      pause switch and kids' items above are what decide when the config is ready
- [ ] Add `/data/adguard/conf` to the restic backup (config is not in git)
- [ ] Renovate regex manager for `adguard_version` (Quadlet `.container.j2` files
      aren't picked up by default)

### 3. Traefik — reverse proxy

- Clean URLs (`immich.froeb.se`, `uptime.froeb.se` etc) instead of raw IPs and ports
- Names are LAN-only for now: AdGuard rewrites `*.froeb.se` to the server. The
  public name for Immich (`foto.froeb.se`) comes with the tunnel, under the same
  wildcard cert
- TLS: one wildcard `*.froeb.se` from Let's Encrypt via Cloudflare DNS-01
  (`playbooks/traefik.yml`, token in vault as `traefik_cf_dns_api_token`). Cert
  state is in `/etc/traefik/acme` and isn't backed up
- Single entry point — do this before adding more services
- [x] Playbook: deploy Traefik container + config (`playbooks/traefik.yml`, routes
      in `playbooks/templates/traefik/routes.yaml.j2`). Wildcard issued 2026-10-31
- [x] AdGuard rewrite (UI): wildcard `*.froeb.se` → `192.168.88.6`. One rule
      covers every Traefik service, so no per-service DNS. Lives in the UI until
      `adguard-pull` captures it with the rest of the config
- [x] Cloudflare: public wildcard `*.froeb.se` → `192.168.88.6`, DNS only (not
      proxied, since Cloudflare can't reach a private IP). Makes the public answer
      match AdGuard's. Without it, clients that query the router got the proxied
      Cloudflare IPs and bypassed the rewrite. Loopia-parked `froeb.se`, `www` and
      the proxied `*.froeb.se` records were removed
- [x] Router DHCP DNS: `192.168.88.6,192.168.88.1`. The router is the fallback
      again, safe now that its answer for `*.froeb.se` matches AdGuard's. Clients
      that query the router first skip AdGuard filtering. Clients pick up the
      change on lease renewal (Wi-Fi off/on)
- [ ] Migrate Immich to sit behind Traefik (close the direct `:2283` publish)

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
- [ ] Wire up Uptime Kuma + restic alerts to Ntfy (restic already alerts via
      healthchecks.io → ntfy.sh)
- Self-hosting on *this* server is fine for app/service notifications, but
  server-down and backup alerts must keep going to ntfy.sh — a local ntfy dies
  with the server it's supposed to report on

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
- Self-hosted bot, works with GitHub or Forgejo — this is about a Renovate
  *instance* for tracking container updates across the whole homelab
  (Immich, future services), a bigger separate project
- For **this repo specifically**, the free GitHub App + `renovate.json` (see
  item 18) already covers it — no need to wait for this item
- [ ] Deploy Renovate bot
- [ ] Configure for this repo

### 17. Healthchecks — cron job monitoring

- Pings via Ntfy if a scheduled job (e.g. restic backup) doesn't check in
- Essential companion to restic
- Currently using hosted healthchecks.io (free tier) → ntfy.sh. Keep it off-box:
  a self-hosted instance on this server can't alert when the server itself is down
- [ ] Playbook: deploy Healthchecks (only if moved to a *different* host)
- [x] Wire up restic backup + check timers to Healthchecks

### 18. GitHub Actions CI pipeline

- PR opened → GitHub-hosted runner → ansible-lint (no server access)
- PR opened → self-hosted runner → `make check` (dry-run against server, read-only)
- Merge to main → run `make run` manually (no auto-deploy)

Security considerations:
- Pin all external Actions to commit hash (not `@v4` tags)
- Renovate keeps pinned Actions current, not Dependabot — Dependabot only covers
  Actions here, Renovate also handles the Dockerfile digest and Galaxy
  collections pinned above with one config file (`renovate.json`)
- Self-hosted runner runs as dedicated user with limited sudo
- No secrets as GitHub Secrets — vault password + SSH key stay on server
- Enable "Require approval for outside collaborators"

Tasks:
- [ ] Playbook: install and register GitHub Actions self-hosted runner
- [ ] `.github/workflows/ci.yml` — lint (GitHub-hosted) + dry-run (self-hosted)
- [x] Pin all Actions to commit hash (already the case in `ci.yml`)
- [ ] Add `renovate.json` (Actions digests, Dockerfile digest, Galaxy collections)
- [ ] Install the Renovate GitHub App on this repo (config alone doesn't run it —
      see item 16 note)
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

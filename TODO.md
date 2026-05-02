# Homelab TODO

Persistent backlog so context can be closed/reopened without losing momentum.
When picking up work, scan the **In progress** and **Next up** sections.

## Done

- [x] Ansible bootstrap working end-to-end (`make bootstrap REMOTE_USER=u1frob PRIVATE_KEY=~/.ssh/<key>`)
- [x] `make ping` succeeds against `homeserver` (192.168.88.6) as the `ansible` user

## In progress

_(nothing yet — pick from Next up)_

## Next up: Immich + restic to Backblaze B2

Open questions to answer before writing playbooks:

1. Is Docker installed on the server, or does the playbook need to install it?
2. ZFS pool/dataset name and mount path for Immich data (e.g. `tank/immich` → `/tank/immich`)?
3. Linux distribution on the server (Debian / Ubuntu / other)?
4. Backblaze B2 bucket created? Bucket name + application key (keyID + applicationKey)?
   - Store credentials in `ansible-vault`, not plain text.
5. Restic repo password chosen and saved in Bitwarden?
   - Without it the backups are unrecoverable.
6. Immich domain (e.g. `immich.<domain>`)? Cloudflare Tunnel vs Traefik+LE vs LAN-only-no-TLS?

Tasks (in order):

- [ ] Decide on the open questions above
- [ ] Playbook: install Docker + compose plugin on homeserver
- [ ] Playbook: deploy Immich via docker-compose (server, microservices, ML, postgres, redis)
- [ ] Playbook: install restic, configure B2 backend, daily systemd timer for `/tank/immich/library`
- [ ] Test restore from B2 to a scratch directory (verify backups actually work)
- [ ] DNS / TLS for Immich

## Backlog / polish

- [ ] Pin `ansible_python_interpreter: /usr/bin/python3.12` in `group_vars/all.yml` to silence discovery warning
- [ ] Update `allowed_networks` in `group_vars/all.yml` — currently `192.168.0.0/26`, but actual LAN is `192.168.88.0/24`. UFW playbook will lock you out otherwise.
- [ ] Disable `PasswordAuthentication` in sshd for u1frob (after confirming key auth works)
- [ ] Save `~/.ssh/ansible` private key to Bitwarden as a secure note (currently only on this mac)
- [ ] Replace `ansible.cfg` `host_key_checking = False` with a checked-in `known_hosts` once the server is stable

IMAGE  := homelab-ansible
DOCKER := docker run --rm -it \
            -v $(CURDIR):/ansible \
            -v $(HOME)/.ssh:/root/.ssh:ro \
            $(IMAGE)

.PHONY: build ping bootstrap check run playbook lint test vault edit-vault view-vault explain

## Build the Ansible Docker image
build:
	docker build -t $(IMAGE) .

## Test connectivity — ansible all -m ping
ping: build
	$(DOCKER) ansible all -m ping

## First-time setup: create the ansible user on the server.
## Usage: make bootstrap REMOTE_USER=youruser [PRIVATE_KEY=~/.ssh/yourkey]
## Without PRIVATE_KEY, falls back to password auth (--ask-pass).
bootstrap: build
	$(DOCKER) ansible-playbook playbooks/bootstrap.yml \
	  -u $(REMOTE_USER) --ask-become-pass \
	  $(if $(PRIVATE_KEY),--private-key=$(PRIVATE_KEY),--ask-pass)

## Dry-run: show what would change without applying
check: build
	$(DOCKER) ansible-playbook site.yml --check --diff

## Apply all playbooks
run: build
	$(DOCKER) ansible-playbook site.yml

## Run a single playbook. Usage: make playbook PLAYBOOK=playbooks/foo.yml [ARGS=--ask-vault-pass]
playbook: build
	$(DOCKER) ansible-playbook $(PLAYBOOK) $(ARGS)

## Lint the repo with ansible-lint (same check as CI)
lint: build
	$(DOCKER) ansible-lint

## Run all tests: lint, then the knowledge store checks on the server over ssh.
## scripts/zfs-scrub-test.sh is not included: it runs as root on the server and
## creates a scratch pool, so run it by hand.
test: lint
	scripts/knowledge-store-test.sh

## Run ansible-vault commands. Usage: make vault CMD="create group_vars/homelab_vault.yml"
vault: build
	$(DOCKER) ansible-vault $(CMD)

## Edit group_vars/homelab/vault.yml in $EDITOR (decrypts and re-encrypts)
edit-vault: build
	$(DOCKER) ansible-vault edit group_vars/homelab/vault.yml

## Print the decrypted group_vars/homelab/vault.yml (read-only)
view-vault: build
	$(DOCKER) ansible-vault view group_vars/homelab/vault.yml

## Show all available make targets with descriptions
explain:
	@echo ""
	@echo "Usage: make <target>"
	@echo ""
	@echo "  build                       Build the Ansible Docker image (auto-runs before other targets)"
	@echo "  ping                        Test SSH connectivity to all hosts (ansible all -m ping)"
	@echo "  bootstrap REMOTE_USER=      First-time setup: create the ansible user on the server"
	@echo "  check                       Dry-run: show what would change without applying anything"
	@echo "  run                         Apply all playbooks (site.yml)"
	@echo "  playbook PLAYBOOK=path.yml  Run a single playbook (optional: ARGS=...)"
	@echo "  lint                        Run ansible-lint (same check as CI)"
	@echo "  test                        Run lint and the knowledge store checks on the server"
	@echo "  vault CMD='...'             Run an ansible-vault command"
	@echo "  edit-vault                  Edit group_vars/homelab/vault.yml in \$$EDITOR"
	@echo "  view-vault                  Print the decrypted group_vars/homelab/vault.yml"
	@echo "  explain                     Show this help message"
	@echo ""

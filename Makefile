IMAGE  := homelab-ansible
DOCKER := docker run --rm -it \
            -v $(CURDIR):/ansible \
            -v $(HOME)/.ssh:/root/.ssh:ro \
            $(IMAGE)

.PHONY: build ping bootstrap check run playbook vault explain

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

## Run ansible-vault commands. Usage: make vault CMD="create group_vars/homelab_vault.yml"
vault: build
	$(DOCKER) ansible-vault $(CMD)

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
	@echo "  vault CMD='...'             Run an ansible-vault command"
	@echo "  explain                     Show this help message"
	@echo ""

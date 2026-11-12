# Pinned by digest (not just the floating "3.12-slim" tag) for reproducible
# builds — Renovate (see renovate.json) keeps this current.
FROM python:3.12-slim@sha256:5e2bdb1b0d542d5039cffb8181c65930093949194a65c365dfb1b0fe13a4fa5b

RUN apt-get update \
    && apt-get install -y --no-install-recommends openssh-client sshpass vim-tiny less \
    && ln -s /usr/bin/vim.tiny /usr/local/bin/vi \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir ansible==10.7.0 ansible-lint==26.6.0

WORKDIR /ansible

COPY requirements.yml .
RUN ansible-galaxy collection install -r requirements.yml

# Repo is mounted at /ansible at runtime — no ENTRYPOINT so we can call
# both `ansible` and `ansible-playbook` explicitly via the Makefile.

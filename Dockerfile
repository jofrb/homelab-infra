FROM python:3.12-slim

RUN pip install --no-cache-dir ansible==10.7.0

WORKDIR /ansible

COPY requirements.yml .
RUN ansible-galaxy collection install -r requirements.yml

# Repo is mounted at /ansible at runtime — no ENTRYPOINT so we can call
# both `ansible` and `ansible-playbook` explicitly via the Makefile.

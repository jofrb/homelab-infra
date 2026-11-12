#!/usr/bin/env bash
# Checks the knowledge store end to end: a dry run of playbooks/knowledge.yml from
# the Mac, then the layout, git repo and kb CLI on the server over ssh.
# The remote part creates one smoke-test project and removes it again.
#
# Run from the repo root, after `make playbook PLAYBOOK=playbooks/zfs.yml` and
# `make playbook PLAYBOOK=playbooks/knowledge.yml` have been applied:
#   scripts/knowledge-store-test.sh
#
# Override the host with KB_HOST (default: strutserver).
set -euo pipefail

HOST=${KB_HOST:-strutserver}

echo "== dry run: playbooks/knowledge.yml"
make playbook PLAYBOOK=playbooks/knowledge.yml ARGS=--check

echo "== server checks on $HOST"
ssh "$HOST" bash -s <<'REMOTE'
set -euo pipefail
ROOT=/data/knowledge
SLUG=smoke-test-$$
PROJECT=$ROOT/projects/$SLUG

fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "ok    $*"; }
cleanup() { if [[ -d "$PROJECT" ]]; then rm -rf -- "$PROJECT"; fi; }
trap cleanup EXIT

[[ $(findmnt -n -o SOURCE "$ROOT") == data/knowledge ]] || fail "$ROOT is not the data/knowledge dataset"
ok "dataset data/knowledge mounted at $ROOT"

[[ $(stat -c %U "$ROOT") == "$(whoami)" ]] || fail "$ROOT is not owned by $(whoami)"
ok "$ROOT owned by $(whoami)"

for d in projects areas _inbox _templates/project _templates/conversation raw; do
  [[ -d "$ROOT/$d" ]] || fail "missing $ROOT/$d"
done
ok "layout directories present"

[[ -f "$ROOT/_templates/project/README.md" ]] || fail "missing project template"
[[ -f "$ROOT/_templates/conversation/conversation.md" ]] || fail "missing conversation template"
ok "templates present"

git -C "$ROOT" rev-parse --git-dir >/dev/null || fail "$ROOT is not a git repo"
ok "git repo in $ROOT"

[[ -x /usr/local/bin/kb ]] || fail "kb not installed at /usr/local/bin/kb"
ok "kb installed"

kb new "$SLUG" >/dev/null || fail "kb new $SLUG failed"
[[ -f "$PROJECT/README.md" ]] || fail "no README.md in new project"
for sub in notes conversations sources; do
  [[ -f "$PROJECT/$sub/.gitkeep" ]] || fail "missing $sub/ in new project"
done
grep -q "^slug: $SLUG$" "$PROJECT/README.md" || fail "slug not filled in README.md"
grep -q '{{' "$PROJECT/README.md" && fail "unfilled placeholder in README.md"
ok "kb new creates README and subfolders"

if kb new "$SLUG" >/dev/null 2>&1; then fail "kb new overwrote an existing project"; fi
ok "kb new refuses an existing project"

if kb new Bad_Slug >/dev/null 2>&1; then fail "kb new accepted a bad slug"; fi
ok "kb new refuses a bad slug"

cleanup
[[ ! -e "$PROJECT" ]] || fail "smoke-test project was not removed"
ok "smoke-test project removed"

echo "all knowledge store checks passed"
REMOTE

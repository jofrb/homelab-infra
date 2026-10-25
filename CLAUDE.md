# Homelab Infra — Claude Guidelines

## Branching and Pull Requests

- Always pull the latest `main` before creating a new branch (`git checkout main && git pull`).
- Always create a new branch for every piece of work before making changes.
- One feature or fix per PR — keep each PR tightly scoped to a single concern.
- Never commit directly to `main`.
- After completing the work on a branch, create a PR for review.

Branch naming: use short, descriptive kebab-case names prefixed by type, e.g. `feat/add-monitoring`, `fix/ansible-ssh-timeout`, `chore/update-dependencies`.

## Commits

- Every commit must leave the repo working. Don't leave "fix the previous commit" commits on a branch; fold them into the commit they belong to before pushing.
- Before pushing, regroup the branch into logical commits with one concern each (e.g. vault key, the feature, docs/TODO), ordered so each stands alone: a vault key comes before the playbook that needs it.
- Only rewrite history that hasn't been pushed, and make a backup branch first.

## Suggesting commands

- When suggesting commands that belong together, chain them with `&&` in one line instead of listing them separately, e.g. `git push && gh pr create`.
- For PRs, suggest `gh pr create` with an explicit `--title` and `--body`, never `--fill`.

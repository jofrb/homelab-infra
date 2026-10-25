# Homelab Infra — Claude Guidelines

## Branching and Pull Requests

- Always pull the latest `main` before creating a new branch (`git checkout main && git pull`).
- Always create a new branch for every piece of work before making changes.
- One feature or fix per PR — keep each PR tightly scoped to a single concern.
- Never commit directly to `main`.
- After completing the work on a branch, create a PR for review.

Branch naming: use short, descriptive kebab-case names prefixed by type, e.g. `feat/add-monitoring`, `fix/ansible-ssh-timeout`, `chore/update-dependencies`.

## Suggesting commands

- When suggesting commands that belong together, chain them with `&&` in one line instead of listing them separately, e.g. `git push && gh pr create`.
- For PRs, suggest `gh pr create` with an explicit `--title` and `--body`, never `--fill`.

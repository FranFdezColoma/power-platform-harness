# {{project_name}}

{{project_description}}

Spec-driven delivery for Power Platform / Dynamics 365 with OpenSpec. This file is for people;
agents start at `AGENTS.md`.

## Getting started

Install the `power-platform-harness` plugin in Claude Code and run `/set-power-platform` in this
folder: it prepares your machine and your sign-ins. Accept Claude Code's trust prompt for this
folder: until you do, the rules in `.claude/settings.json` do not apply and every command asks.

## Approving a change

Each change records its gates in `openspec/changes/<change>/approval.md` (format in "Gates"
in `docs/agents/openspec-workflow.md`). The file moves with the change when it is archived.

- **Approve or request changes**: switch to the change's branch, review the artifacts, edit
  your gate's line, then commit and push:

  ```
  - Functional: Approved by Ana, 2026-10-23
  - Technical: Changes requested by Marta, 2026-10-24: split the plugin per message
  ```

  Commit message: `Functional gate <change>: approved` (or `changes requested`).
- **Status of every open change**, across all remote branches, without switching branch:

  ```powershell
  git fetch --prune
  git grep -e "Functional:" -e "Technical:" (git branch -r --format="%(refname:short)" | Where-Object { $_ -notmatch '^origin(/HEAD)?$' }) -- "openspec/changes/*/approval.md" ":(exclude)openspec/changes/archive/**"
  ```

- **History of one change**: `git log --format="%h %an %ad %s" -- openspec/changes/<change>/approval.md`

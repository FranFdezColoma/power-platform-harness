# Harness already present

Read when step 1 found `.power-platform/project.json` or `docs/agents/development-standards.md`. It adds to step 4 of `SKILL.md`.

Every file the project lacks is written as in step 4. For each file it has, compare it with its template, tokens replaced with the values from `project.json`, and leave out what is the project's on purpose:

- `.power-platform/project.json`: never compared; it holds the project's data.
- `docs/context/project.md` and `docs/context/glossary.md`: never compared; the team keeps them current.
- `README.md`: only the "Approving a change" section is compared.
- `openspec/config.yaml`: only the `context` lines the template has are compared.
- What `openspec init` generated (`.claude/skills/openspec-*`, `.claude/commands/opsx/`, `.github/skills/openspec-*`, `.github/prompts/opsx-*`, `.agents/skills/openspec-*`): never compared; `openspec update` refreshes it (step 4, "OpenSpec").
- The project's own content in `AGENTS.md` and `CLAUDE.md` (the description, the sections the template does not have): only the template's sections are compared.
- A reconciled line — a stated version, framework or path, followed by `Harness recommends …` (see `references/existing-project.md`, step 5) — is the project's choice, not a difference; so is a dotted root namespace substituted there.
- `.claude/settings.json`: only the template's rules the file lacks, merged as in `references/existing-project.md`.
- `.gitignore`: only the template's lines the file lacks, merged as in `references/existing-project.md`.

What remains is what the templates changed since the file was written. Show each file's diff and apply it only when the user accepts that file. A diff that would remove a rule the project added is a conflict: report it.

A file an earlier harness wrote that is no longer a template (`docs/agents/solutioning-standards.md`, folded into `docs/solutioning/principles.md`) is proposed for deletion, on its own, once the files that pointed to it are updated.

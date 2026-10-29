# Existing project

Read when step 1 found an existing project without the harness. It adds to steps 1, 3, 4 and 5 of `SKILL.md`. In an empty folder, only step 4's `README.md` and `.gitignore` apply.

## Step 1: the stack

For each decision the standards in `templates/docs/development/` assert — plugin target framework and strong naming, test framework, the web resources' lint and test tooling, PCF platform libraries, the folder layout — note what the project uses, with the file that shows it.

## Step 3: the project's stack wins

Report every decision where the project differs from the standards as a table: topic, what the standard says, what the project does, the evidence. These are not defects, and the harness never retargets a framework, changes a test runner, upgrades a library or moves a folder. The project's version is the rule; step 5 records it in the generated docs.

When the project already has its own folder layout, do not create the harness's (`src/PowerPlatform/`): two conventions in one repository is worse than either. Say which one the project uses.

## Step 4: kept files

### `AGENTS.md` or `CLAUDE.md`

The project's own instruction files may not point the agent at `docs/agents/development-standards.md` yet, and then the harness is unreachable. Fix it without moving existing content:

- **`AGENTS.md` existed** — add the sections of the template's `AGENTS.md` it lacks, tokens replaced, starting with "Where to start", which points at `docs/agents/openspec-workflow.md` and `docs/agents/development-standards.md`. Keep the project's own content where it is.
- **Only `CLAUDE.md` existed** — `AGENTS.md` was written new. Add one line, `@AGENTS.md`, to the existing `CLAUDE.md`, and nothing else.

### `README.md`

Add the template's "Approving a change" section at the end of the existing README, tokens replaced, and nothing else. The project's own content stays where it is.

### `.gitignore`

Add each line of the template's `.gitignore` the file lacks, under a `# Power Platform harness` comment at the end, and remove nothing. The secrets section matters most: without it `.env` and the token cache `dv-connect` writes could be committed. A project line that un-ignores one of them (`!.env`) is a conflict: report it.

### `.claude/settings.json`

Merge the template's rules into it: add each `ask` and `allow` rule it lacks, keep every rule and setting the project already has, and remove nothing. A project rule that allows what the harness asks about is a conflict: report it, do not resolve it.

## Step 5: reconcile the generated docs

For every difference in step 3, in the generated file that states the standard — in the current folder, never this skill's `templates/`:

1. Change the stated version, framework or path so it matches what the project uses, and nothing else on the line.
2. Directly below it, add one line: `Harness recommends <what the standard said>. Upgrade as its own change, never alongside unrelated work.`

A file that was kept is not edited: report the difference instead. A difference with no doc to edit (the folder layout) was handled in step 3. List every edit you made.

When the project's root namespace is dotted (`Acme.Crm`), replace the project name followed by a dot (`Acme.`, as substituted for `{{project_name}}.`) with that namespace followed by a dot (`Acme.Crm.`) in the generated `docs/development/csharp-plugins.md` and `custom-apis.md`; nothing else changes.

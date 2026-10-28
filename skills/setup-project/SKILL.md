---
name: setup-project
description: Install the Power Platform / Dynamics 365 CE harness files in a repository — AGENTS.md, CLAUDE.md, .power-platform/project.json, permission rules, the development standards per technology and the per-branch feature solution workflow. Works on an empty folder and on an existing project, where it reads the publisher, prefix, core solution and stack from the repository and the environment instead of asking, and adapts the standards to the versions the project already uses. Use when set-power-platform reaches its project step, or to adopt the harness into a repository.
allowed-tools: Bash(git init *), Bash(git status*), Bash(git remote *), Bash(git log *), Bash(git switch -c *), Bash(git add *), Bash(git commit *), Bash(git diff*), Bash(pac auth list*), Bash(pac org who *), Bash(pac solution list *), Bash(pac org fetch *), PowerShell(git init *), PowerShell(git status*), PowerShell(git remote *), PowerShell(git log *), PowerShell(git switch -c *), PowerShell(git add *), PowerShell(git commit *), PowerShell(git diff*), PowerShell(pac auth list*), PowerShell(pac org who *), PowerShell(pac solution list *), PowerShell(pac org fetch *), Read, Write, Edit, Glob, Grep, AskUserQuestion
---

# Set up the project

This skill owns the repository. It writes the harness files from `templates/`, next to this file, into the current folder:

- **Empty folder** — every template.
- **Existing project** — only what is missing. Keep what the project already has, and adapt the standards to the stack it actually uses. Never set a version, framework or layout the project does not use.

The templates are the product. Copy them; never write, paraphrase or improve their content yourself. The shipped templates are in English and stay English whatever the conversation language.

Talk to the user in the conversation's language.

## Asking the user

- **Free values** (project name, publisher, prefix, core solution, description): ask in a plain message as a numbered list, then stop and wait. A structured question tool needs predefined options, and a free value has none.
- **Closed choices** (the repository provider, one of several publishers found, the go-ahead, committing): your structured question tool if you have one, else a numbered list the user answers by number.

Never invent a value. Never derive one silently from the folder name. A wrong publisher prefix cannot be undone once components exist.

## 1. Inspect

Read the folder before asking anything; write nothing.

- **Mode.** Empty (nothing but `.git`, a README or a licence), existing project, or harness already present (`.power-platform/project.json`, `docs/agents/development-standards.md`).
- **Identity evidence.** A committed `Other/Solution.xml` gives the solution unique name, the publisher unique name and its customization prefix. The `.csproj` files' `RootNamespace` gives the project name; a dotted root namespace (`Acme.Crm`) is worth noting. Web resource names and folders (`<prefix>_/...`) hint at the prefix. The README may describe the project. `git remote get-url origin` gives the provider.
- **Environment, when `pac` reaches one.** `pac solution list --environment <url>` lists the unmanaged solutions; the publishers come from `pac org fetch` over the `publisher` table (unique name, prefix, whether it is a default publisher). Branch solutions named `feature_*`, `fix_*` or `chore_*` are not the core solution. Skip this when `pac` is not connected; the values are asked instead.
- **Stack, for an existing project.** For each decision the standards in `templates/docs/development/` assert — plugin target framework and strong naming, test framework, the web resources' lint and test tooling, PCF platform libraries, the folder layout — note what the project uses, with the file that shows it.

## 2. Values

| Value | Token | What it is | Rules |
| --- | --- | --- | --- |
| Project name | `{{project_name}}` | Short project name. Also the root .NET namespace, the JavaScript form API namespace and the WebResources project name. Never ask for a namespace separately | Starts with a letter, letters and digits only |
| Publisher unique name | `{{publisher_unique_name}}` | Dataverse publisher **unique** name, not its display name | Letters, digits and underscores |
| Publisher prefix | `{{publisher_prefix}}` | Customization prefix, carried by every component | 2 to 8 lowercase letters and digits, starts with a letter, not `mscrm`. **Permanent**: say so before accepting it |
| Core solution | `{{core_solution}}` | Unique name of the core unmanaged solution in DEV, or `none` | Letters, digits and underscores, no publisher prefix. Optional: `none` when the project has none |
| Description | `{{project_description}}` | One or two sentences on what the project delivers | Free text |
| Repository provider | `{{repository_provider}}` | Where the repository is hosted | `github` or `azure-devops`. Propose it from the remote and confirm it; with no remote, ask |
| — | `{{repository_cli}}` | Derived, never asked | `gh` for `github`, `az repos` for `azure-devops` |

Show the values as a table with value, source and confidence — **read** (from a committed `Solution.xml` or the environment), **inferred** (a namespace, file names, a README; show the evidence) or **missing** — then ask in one message for what is missing or doubtful. Values the user passed to this skill are proposals: echo them back for confirmation.

- **Publisher.** Prefer the core solution's publisher, then the only custom publisher in the environment. With several candidates, let the user choose. A prefix that matches no publisher is either mistyped or a publisher not created yet: show the existing ones and ask. A default publisher's prefix deserves a warning: projects should own their publisher.
- **Core solution.** Most projects have one; check the proposed name against the environment's list when you have it.

## 3. Existing project: the project's stack wins

Skip for an empty folder.

Report every decision where the project differs from the standards as a table: topic, what the standard says, what the project does, the evidence. These are not defects, and the harness never retargets a framework, changes a test runner, upgrades a library or moves a folder. The project's version is the rule; step 5 records it in the generated docs.

When the project already has its own folder layout, do not create the harness's (`src/PowerPlatform/`): two conventions in one repository is worse than either. Say which one the project uses.

## 4. Plan, confirm once, write

List what you will write: each file under `templates/`, at the same relative path in the current folder. For an existing project, mark each file that already exists as **kept**: it is not overwritten. Overwrite a file only when the user explicitly accepts overwriting that exact file. For an empty folder, also create the folders `src/PowerPlatform/`, `solutions/` and `scripts/`, so `dv-connect` later finds the workspace already laid out (exception E2 in `docs/agents/skill-exceptions.md`).

Ask for the go-ahead **once**, with the resolved values and the file list. Then, for each file:

1. Read the template.
2. Replace every token with its value, and change nothing else: not the wording, not the formatting, not the line endings.
3. Write it.

Afterwards, search the written files for `{{`: no token may survive. If one does, report it as a bug in this harness.

### When `AGENTS.md` or `CLAUDE.md` was kept

The project's own instruction files may not point the agent at `docs/agents/development-standards.md` yet, and then the harness is unreachable. Fix it without moving existing content:

- **`AGENTS.md` existed** — add the sections of the template's `AGENTS.md` it lacks, tokens replaced, starting with the mandatory-reading pointer to `docs/agents/development-standards.md`. Keep the project's own content where it is.
- **Only `CLAUDE.md` existed** — `AGENTS.md` was written new. Add one line, `@AGENTS.md`, to the existing `CLAUDE.md`, and nothing else.

### When `.claude/settings.json` was kept

Merge the template's rules into it: add each `deny`, `ask` and `allow` rule it lacks, keep every rule and setting the project already has, and remove nothing. A project rule that allows what the harness denies is a conflict: report it, do not resolve it.

Show the user every diff to an existing file before writing it. If an existing file contradicts a harness rule, report the conflict instead of resolving it silently.

## 5. Reconcile the generated docs

Existing project only, for every difference in step 3. In the generated file that states the standard — in the current folder, never this skill's `templates/`:

1. Change the stated version, framework or path so it matches what the project uses, and nothing else on the line.
2. Directly below it, add one line: `Harness recommends <what the standard said>. Upgrade as its own change, never alongside unrelated work.`

A file that was kept is not edited: report the difference instead. A difference with no doc to edit (the folder layout) was handled in step 3. List every edit you made.

When the project's root namespace is dotted (`Acme.Crm`), replace the project name followed by a dot (`Acme.`, as substituted for `{{project_name}}.`) with that namespace followed by a dot (`Acme.Crm.`) in the generated `docs/development/csharp-plugins.md` and `custom-apis.md`; nothing else changes.

## 6. Git

1. **No repository yet** — `git init -b main` (never `master`), then a first commit of the harness files.
2. **Existing repository** — the harness files are uncommitted. Offer a commit on a new branch `chore/adopt-power-platform-harness` (`git switch -c`), never on a shared branch without asking.

Creating a publisher or a solution is irreversible. Never do it on the user's behalf during this skill.

## 7. Report

State what was written, what was kept, what was reconciled, and what you could not check and why. Then, as a list the user can act on:

1. **Publisher** — if it does not exist in DEV yet, a human creates it with unique name and prefix as resolved.
2. **Core solution** — if it is not `none` and does not exist in DEV yet, a human creates it under that publisher.
3. **Recommended upgrades** — for an existing project, the differences reconciled in step 5, as the team's upgrade backlog.
4. **Workspace trust** — the rules in `.claude/settings.json` that allow read-only checks apply only after each developer accepts Claude Code's trust prompt for the repository; the rules that deny irreversible operations apply from the start.
5. Read `docs/agents/development-standards.md` before the first change.

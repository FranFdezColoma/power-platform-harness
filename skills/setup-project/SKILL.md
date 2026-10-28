---
name: setup-project
description: Install the Power Platform / Dynamics 365 CE harness files in a repository — AGENTS.md, CLAUDE.md, .power-platform/project.json, permission rules, the development standards per technology and the per-branch feature solution workflow — and, in an empty folder, the starting code: PowerPlatform.sln, the shared Common library and the WebResources project. Works on an empty folder; on a project that already has the harness, where it proposes what the templates changed since; and on an existing project, where it reads the publisher, prefix, core solution and stack from the repository and the environment instead of asking, and adapts the standards to the versions the project already uses. Use when set-power-platform reaches its project step, to adopt the harness into a repository, or to bring a project's harness files up to date.
allowed-tools: Bash(git init *), Bash(git status*), Bash(git remote *), Bash(git log *), Bash(git switch -c *), Bash(git add *), Bash(git commit *), Bash(git diff*), Bash(pac auth list*), Bash(pac org who *), Bash(pac solution list *), Bash(pac org fetch *), Bash(dotnet --list-sdks), Bash(dotnet build *), Bash(npm test*), Bash(npm run lint*), PowerShell(git init *), PowerShell(git status*), PowerShell(git remote *), PowerShell(git log *), PowerShell(git switch -c *), PowerShell(git add *), PowerShell(git commit *), PowerShell(git diff*), PowerShell(pac auth list*), PowerShell(pac org who *), PowerShell(pac solution list *), PowerShell(pac org fetch *), PowerShell(dotnet --list-sdks), PowerShell(dotnet build *), PowerShell(npm test*), PowerShell(npm run lint*), Read, Write, Edit, Glob, Grep, AskUserQuestion
---

# Set up the project

This skill owns the repository. It writes the harness files from `templates/`, next to this file, into the current folder:

- **Empty folder** — every template, then the starting code (step 6).
- **Existing project** — only what is missing. Keep what the project already has, and adapt the standards to the stack it actually uses. Never set a version, framework or layout the project does not use. No code is created.
- **Harness already present** — what is missing, and a proposal for each file whose template changed since it was written (step 4).

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
- **Environment, when `pac` reaches one.** The DEV url is the one `connect` resolved, or `connections.dataverse.devUrl`. `pac solution list --environment <url>` lists the unmanaged solutions; the publishers come from `pac org fetch` over the `publisher` table (unique name, prefix, whether it is a default publisher). Branch solutions named `feature_*`, `fix_*` or `chore_*` are not the core solution. Skip this when `pac` is not connected (`connect` has not run, or its Dataverse sign-in is pending); the values are asked instead.
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

Show the values as a table with value, source and confidence — **read** (from a committed `Solution.xml` or the environment), **inferred** (a namespace, file names, a README; show the evidence) or **missing** — then ask in one message for what is missing or doubtful. Values the user or `connect` passed to this skill are proposals: echo them back for confirmation. When the harness is already present, the values are `identity` in `.power-platform/project.json`: read them, do not ask again.

- **Publisher.** Prefer the core solution's publisher, then the only custom publisher in the environment. With several candidates, let the user choose. A prefix that matches no publisher is either mistyped or a publisher not created yet: show the existing ones and ask. A default publisher's prefix deserves a warning: projects should own their publisher.
- **Core solution.** Most projects have one; check the proposed name against the environment's list when you have it.

## 3. Existing project: the project's stack wins

Skip for an empty folder.

Report every decision where the project differs from the standards as a table: topic, what the standard says, what the project does, the evidence. These are not defects, and the harness never retargets a framework, changes a test runner, upgrades a library or moves a folder. The project's version is the rule; step 5 records it in the generated docs.

When the project already has its own folder layout, do not create the harness's (`src/PowerPlatform/`): two conventions in one repository is worse than either. Say which one the project uses.

## 4. Plan, confirm once, write

List what you will write: each file under `templates/`, at the same relative path in the current folder. For an existing project, mark each file that already exists as **kept**: it is not overwritten. Overwrite a file only when the user explicitly accepts overwriting that exact file. `solutions/README.md` and `scripts/README.md` are written for an empty folder only; with `src/PowerPlatform/` from step 6 they lay the workspace out before `dv-connect` runs (exception E2 in `docs/agents/skill-exceptions.md`), and git keeps the folders because they are not empty.

Ask for the go-ahead **once**, with the resolved values, the file list and, for an empty folder, the starting code of step 6. Then, for each file:

1. Read the template.
2. Replace every token with its value, and change nothing else: not the wording, not the formatting, not the line endings.
3. Write it.

Afterwards, search the written files for `{{`: no token may survive. If one does, report it as a bug in this harness.

Then, in the written `.power-platform/project.json`, set the `connections` values `connect` resolved and the user confirmed (`dataverse.devUrl`, `dataverse.tenantId`, `repository.url`, `repository.tenantId`); a value it did not resolve stays `null`.

### When the harness is already present

Every file the project lacks is written as above. For each file it has, compare it with its template, tokens replaced with the values from `project.json`, and leave out what is the project's on purpose:

- `.power-platform/project.json`: never compared; it holds the project's data.
- The project's own content in `AGENTS.md` and `CLAUDE.md` (the description, the sections the template does not have): only the template's sections are compared.
- A reconciled line — a stated version, framework or path, followed by `Harness recommends …` (step 5) — is the project's choice, not a difference; so is a dotted root namespace substituted in step 5.
- `.claude/settings.json`: only the template's rules the file lacks, merged as below.

What remains is what the templates changed since the file was written. Show each file's diff and apply it only when the user accepts that file. A diff that would remove a rule the project added is a conflict: report it.

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

## 6. Starting code

Empty folder only. In an existing project, the standards say when each project is created: the first change that needs it.

Create what `docs/development/csharp-plugins.md` and `docs/development/webresources-project.md` — the generated ones, in the current folder — say the first plugin and the first web resource create, and follow them exactly:

- `src/PowerPlatform/PowerPlatform.sln`, with its solution folders.
- `src/PowerPlatform/Plugins/<project name>.Common/`: its `.csproj` and the `PluginBase.cs` taken from `pac plugin init`.
- The WebResources project: the `.esproj`, the three files next to it and its entry in the solution.

No plugin, Custom API, PCF control or test project: each is created with the first change that needs it. Every pin is the latest stable release at its official source at this moment (see "Versions" in `docs/agents/development-standards.md`); say which version you pinned and where you read it.

Then check it: `dotnet build src/PowerPlatform/PowerPlatform.sln`, and in the WebResources project `npm install`, `npm test` and `npm run lint`. Each must succeed with no errors and no new warnings. A part whose tool is missing (`dotnet`, `node` or `pac`, an install the user declined) is not created: report it as pending, with the skill that installs the tool. A check that fails is reported with its output, never left as it is.

## 7. Git

1. **No repository yet** — `git init -b main` (never `master`), then a first commit of the harness files and the starting code.
2. **Existing repository** — the harness files are uncommitted. Offer a commit on a new branch `chore/adopt-power-platform-harness` (`git switch -c`), or `chore/update-power-platform-harness` when the harness was already present, never on a shared branch without asking.

Creating a publisher or a solution is irreversible. Never do it on the user's behalf during this skill.

## 8. Report

State what was written, what was kept, what was reconciled, the template changes applied or declined, the code created with the versions pinned and whether it builds, and what you could not check and why. Then, as a list the user can act on:

1. **Publisher** — if it does not exist in DEV yet, a human creates it with unique name and prefix as resolved.
2. **Core solution** — if it is not `none` and does not exist in DEV yet, a human creates it under that publisher.
3. **Recommended upgrades** — for an existing project, the differences reconciled in step 5, as the team's upgrade backlog.
4. **Workspace trust** — the rules in `.claude/settings.json` that allow read-only checks apply only after each developer accepts Claude Code's trust prompt for the repository; the rules that deny irreversible operations apply from the start.
5. Read `docs/agents/development-standards.md` before the first change.

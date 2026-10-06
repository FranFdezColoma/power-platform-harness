---
name: set-power-platform
description: "Install the Power Platform / Dynamics 365 CE harness in this folder: agent instructions, toolchain requirements, development standards per technology, and the per-branch feature solution workflow. Checks the required and recommended tools and helps connect pac to DEV. Works on an empty folder and on an existing project, where it reads the publisher, prefix, core solution and stack from the repository and the environment instead of asking, and adapts the standards to the versions the project already uses."
disable-model-invocation: true
allowed-tools: Bash(pwsh -NoProfile -File "${CLAUDE_PLUGIN_ROOT}/scripts/discover.ps1" *), Bash(pwsh -NoProfile -File "${CLAUDE_PLUGIN_ROOT}/scripts/scaffold.ps1" *), Bash(powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/discover.ps1" *), Bash(powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/scaffold.ps1" *), Bash(dotnet tool install --global Microsoft.PowerApps.CLI.Tool*), Bash(pac auth create *), Bash(pac auth list*), Bash(pac org who*), Bash(pac solution list*), Bash(git init*), Bash(git status*), Bash(git switch -c *), Bash(git add *), Bash(git commit *), Bash(git diff*), Read, Write, Edit, Glob, Grep, AskUserQuestion
---

# Install the Power Platform harness

Two jobs, decided by what is already in the folder:

- **Empty folder** — scaffold the full harness: `CLAUDE.md`, `docs/agents/development-standards.md`, `docs/agents/toolchain.md`, `docs/development/*.md`, `.gitignore`, the code projects under `src/Dataverse/` (`Dataverse.sln`, the shared `<RootNamespace>.Common` plugin library and the WebResources build project), and the `src/Dataverse/{Plugins,CustomAPIs,WebResources}` and `docs/adr/` layout.
- **Existing project** — adopt the harness into it: add only what is missing, keep what the project already has, and adapt the standards to the stack the project actually uses. Never set a version, framework or layout the project does not use.

Two bundled scripts do the work. `discover.ps1` reads; `scaffold.ps1` writes files and never talks to Dataverse. Do not write or paraphrase template content yourself, and do not hand-craft files the scaffold produces.

## Running the scripts

Every command below starts with `pwsh -NoProfile -File`. If `pwsh` is not installed, run the same script and arguments with `powershell -NoProfile -ExecutionPolicy Bypass -File` instead: both scripts run on Windows PowerShell 5.1. If neither exists, stop: nothing in this skill can run without PowerShell. Tell the user to install it (`docs/agents/toolchain.md` in the templates has the command) and end there.

## Asking the user: hard constraint

`AskUserQuestion` takes at most 4 questions, and each needs 2 to 4 concrete predefined options. It cannot collect free text, a name, a prefix or a url. Calling it for those fails with `Invalid tool parameters`.

- **Free-text values** (project name, publisher, prefix, core solution, namespace, description, environment url): ask in a plain assistant message as a numbered list, then stop and wait.
- **`AskUserQuestion` is for closed choices only**: the language in step 0 when nothing else establishes it, installing `pac` in step 2, the single go-ahead in step 6, and committing in step 8.

Never invent a value. Never derive one silently from the folder name. A wrong publisher prefix cannot be undone once components exist.

## 0. Language

Decide what language this conversation happens in before anything else, including Discover.

- If the user already wrote something in this session before the skill ran, that message is the answer: infer the language from it and do not ask.
- If the skill is the first thing in the session, ask with `AskUserQuestion` which language to use. Offer a handful of common ones (e.g. Spanish, English, French, German); the tool always adds "Other".
- Use the resolved language for every question, confirmation and report this skill produces.
- Never translate what gets written into the target repository. The shipped templates are in English and stay English regardless of the conversation language.

## 1. Discover

One command, before any question:

```bash
pwsh -NoProfile -File "${CLAUDE_PLUGIN_ROOT}/scripts/discover.ps1" -Path .
```

Add `-SkipEnvironment` only when the user says the environment is irrelevant or unreachable. It reads the repository, the tools on this machine and, through `pac`, the connected environment; it writes nothing, in the repo or in Dataverse. Everything downstream comes from its JSON.

If `standards.staleBaseline` is not empty, report it as a bug in this plugin, not in the user's project, and continue.

## 2. Toolchain

Report `toolchain.requirements` as a table: tool, installed version, minimum, preferred, status. Then act on each status:

| `status` | What to say |
| --- | --- |
| `ok` | Nothing |
| `below-preferred` | A recommendation: works, but the preferred version is better supported. Give the `install` command |
| `below-minimum`, `missing` | Required: recommend installing it, with the `install` command |
| `unknown` | The version could not be read: ask the user to confirm it |

None of these stops the skill: the harness only writes files. Every requirement that is not `ok` goes into the final report as pending.

**`pac` missing.** Offer to install it with `AskUserQuestion` (install now / skip). On approval, run `dotnet tool install --global Microsoft.PowerApps.CLI.Tool`; it needs the .NET SDK, so if `dotnet` is missing, say so and leave `pac` pending instead. After a successful install, tell the user that a new terminal may be needed for `pac` to be on PATH, and re-run Discover.

**Recommended tools.** Two are recommended, never required:

- **Dataverse MCP server** — check your own available tools for a Dataverse MCP server; this script cannot see what is registered with you. `toolchain.recommended.dataverseMcpProxy.installed` says whether the local proxy is installed. If no server is available, recommend the setup in `docs/agents/toolchain.md`.
- **Playwright** — `toolchain.recommended.playwrightCli.installed`, or a Playwright MCP server among your own tools. If neither, recommend `playwright-cli` with its `install` command.

## 3. Connect `pac` to DEV

Only when `pac` is installed.

1. **No authentication profile** (`environment.hasAuthProfile` is false): ask for the DEV environment url as plain text, wait, then run `pac auth create --environment <url>`. It opens a browser and waits for the user to sign in, so say so before running it and do not treat a slow return as a failure. Then re-run Discover.
2. **Profile but not connected** (`environment.connected` is false): report `environment.errors` in one line and offer to create a profile for the right url, as above.
3. **Connected**: report `environment.org.friendlyName`. If `environment.nameSignal` is not `dev`, say that the standards permit write operations in DEV only and that this environment does not look like one.

If the connection cannot be made — conditional access, no network, the user declines — continue. The harness is installed anyway, and the connection is reported as pending.

## 4. Values

Six values, resolved before scaffolding. `proposedValues` carries what discovery found; each entry has a `source` and a `confidence`:

- `high` — read out of a committed `Solution.xml` or an exported solution. State the source and move on.
- `medium` — inferred (a shared root namespace, a prefix seen in file names, a solution named Core, a README paragraph). Show the evidence and let the user correct it.
- `none` — ask, as plain text.

Show all six as a table with value, source and confidence, then ask in one plain-text message for what `recommendation.askUserFor` lists. Values the user passed as arguments to this skill are proposals: echo them back for confirmation.

| Value | What it is | Rules |
| --- | --- | --- |
| `ProjectName` | Short project name. Names the JavaScript form API namespace and the WebResources project | Starts with a letter, letters and digits only |
| `PublisherUniqueName` | Dataverse publisher **unique** name, not its display name. `pac solution init` needs it to create feature solutions | Letters, digits and underscores |
| `PublisherPrefix` | Dataverse customization prefix, carried by every component | 2-8 lowercase alphanumeric, starts with a letter, cannot start with `mscrm`. **Permanent**: say this out loud before accepting it |
| `CoreSolution` | Unique name of the core unmanaged solution in DEV, or `none` when the project has none. Optional: omit it and the scaffold uses `none` | Letters, digits and underscores, no publisher prefix |
| `RootNamespace` | Root .NET namespace | Valid .NET namespace, dots allowed |
| `ProjectDescription` | One or two sentences on what the project delivers. Becomes the Description section of `CLAUDE.md` | Free text |

- **Core solution.** Most projects have one, but it is not mandatory. Check the proposed name against `environment.solutions`; a name flagged `possiblyTruncated` was cut by `pac solution list`, so confirm it. `featureSolutionsInEnvironment` lists the per-branch solutions already there: none of them is the core solution.
- **Publisher.** When `PublisherUniqueName` or `PublisherPrefix` is `none` but the core solution exists in the connected environment, re-run Discover with `-ResolvePublisherFromSolution <CoreSolution>` instead of asking. It exports that solution to a temp folder to read its publisher, which takes a while on a large solution: say so first. Without a core solution, ask; the maker portal shows both under Solutions > Publishers.

## 5. Existing project: adapt the standards to it

Skip this step for a new project.

`standards.assessments` compares every version, framework and layout decision the shipped standards assert against what the repository uses. Report every entry whose `status` is `deviates` as a table: topic, what the standard says, what the project does, and the evidence. Ignore `not-applicable` and `match`; ask the user about each `unknown`.

These differences are not defects in the project, and the harness never retargets a framework, changes a test runner, upgrades a library or moves a folder. The project's version is the rule. After scaffolding (step 7), each deviation is reconciled in the generated docs.

When `layout.folders` deviates, pass `-SkipLayout`: creating `src/Dataverse/Plugins/` next to an existing `source/plugins/` leaves two conventions in one repository. Say which one the project uses.

## 6. Confirm once, then write

Run the dry run first and read its output yourself; do not make the user confirm twice:

```bash
pwsh -NoProfile -File "${CLAUDE_PLUGIN_ROOT}/scripts/scaffold.ps1" -ProjectName <name> -PublisherUniqueName <publisher> -PublisherPrefix <prefix> -CoreSolution <core-or-none> -RootNamespace <namespace> -ProjectDescription "<description>" -Json -DryRun <flags>
```

`<flags>` is exactly what `recommendation.scaffoldArguments` lists — empty for a new project — plus `-SkipLayout` if step 5 decided it. `-Json` keeps the output parseable. The script validates every value, so a bad prefix or name surfaces here, before anything is written.

Then ask for the go-ahead **once**, with `AskUserQuestion`: the resolved values, the file count, and — for an existing project — which files will be skipped. On approval, re-run the same command without `-DryRun`.

Flag rules:

- `-SkipExisting` — existing project, or a folder that already holds some harness files. Writes what is missing, reports what it left alone.
- `-SkipLayout` — the project already has its own layout.
- `-SkipCodeProjects` — existing project. The code projects under `src/Dataverse/` (`Dataverse.sln`, the Common plugin library, the WebResources build project) introduce a target framework and a test runner (Vitest); never write them unprompted into an established repository. `recommendation.scaffoldArguments` already includes it when needed. Omit it only when the user explicitly asks for them, having seen the `webresources.buildProject` assessment.
- `-Force` — only when the user has explicitly accepted overwriting the exact files listed. Never combined with `-SkipExisting`; the script rejects that.

Report the warnings in `recommendation.warnings` alongside the dry run. If the script fails, report its output verbatim. Do not hand-edit generated files to work around it.

### When `CLAUDE.md` was skipped

`-SkipExisting` keeps the project's `CLAUDE.md`, which means nothing yet points the agent at `docs/agents/development-standards.md` and the whole harness is unreachable. Fix it without paraphrasing: render the templates into a throwaway folder, read the rendered `CLAUDE.md`, and merge its sections into the existing one.

```bash
pwsh -NoProfile -File "${CLAUDE_PLUGIN_ROOT}/scripts/scaffold.ps1" -ProjectName <name> -PublisherUniqueName <publisher> -PublisherPrefix <prefix> -CoreSolution <core-or-none> -RootNamespace <namespace> -ProjectDescription "<description>" -TargetPath <temp folder> -SkipLayout
```

Keep the project's own content. Add the harness sections it lacks, starting with the mandatory-reading pointer to `docs/agents/development-standards.md`. Show the user the diff. If the existing `CLAUDE.md` contradicts a harness rule, report the conflict instead of resolving it silently.

## 7. Reconcile the generated docs

Existing project only, for every `deviates` assessment and every `unknown` the user answered. Edit the generated file named in the assessment's `targetFile`, in the target repository — never this plugin's `templates/`:

1. Change the stated version, framework or path so it matches what the project uses, and nothing else on the line.
2. Directly below it, add one line: `Harness recommends <standardLabel>. Upgrade as its own change, never alongside unrelated work.`

The assessment's `guidance` says why the project's choice is the one to keep for now. If the file was skipped because it already existed, do not edit it: report the deviation instead. List every edit you made.

## 8. Git

1. **Initialise git** — only if `repository.git.isRepository` is false: `git init`, then a first commit of the scaffold.
2. **Commit the harness** — if the repository already existed, the harness files are uncommitted. Offer, with `AskUserQuestion`, a commit on a new branch `chore/adopt-power-platform-harness` (`git switch -c`), never on a shared branch without asking.

Creating a publisher or a solution is irreversible. Never do it on the user's behalf during this skill.

## 9. Report

State what was created, what was skipped, what was reconciled, and what you could not run and why.

Then, as a list the user can act on:

1. **Pending tools** — every requirement that is not `ok`, with its install command, and the recommended tools that are missing.
2. **Pending connection** — if `pac` is not connected to DEV, the command to do it.
3. **Publisher** — if it does not exist in DEV yet, create it with unique name `<PublisherUniqueName>` and prefix `<PublisherPrefix>`. A human does this.
4. **Core solution** — if `<CoreSolution>` is not `none` and does not exist in DEV yet, create it under that publisher. A human does this.
5. **Recommended upgrades** — for an existing project, the deviations reconciled in step 7, as the team's upgrade backlog.
6. Read `docs/agents/development-standards.md` before the first change.

End with one sentence on how work starts from now on: every feature, fix or chore goes on its own branch with its own feature solution named after it, and the agent asks which branch before the first change. `docs/development/solutions.md` has the flow.

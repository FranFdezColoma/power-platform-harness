# Description

This repository is a Claude Code plugin that scaffolds Power Platform / Dynamics 365 CE
repositories. Its skills live under `skills/`, and the templates they write under
`skills/setup-project/templates/`.

It is not a Power Platform project: nothing here is deployed to Dataverse. The standards in
`skills/setup-project/templates/docs/` govern the projects this plugin creates, not this repository.

**2.0 is in progress** on `feature/v2-official-skills`. Before changing anything, read
`docs/design/2.0-architecture.md`: it holds the agreed design and the phase you are in. Where it
and the sections below disagree, the design document describes the target and the sections below
describe 1.x as it still stands.

## Layout

| Path | What it is |
| --- | --- |
| `.claude-plugin/plugin.json` | Plugin manifest. Lists the skills explicitly |
| `.claude-plugin/marketplace.json` | Makes this repo its own single-plugin marketplace |
| `skills/set-power-platform/SKILL.md` | The skill users run: discovers, collects what discovery could not, runs the scaffold, reports |
| `skills/setup-tools/SKILL.md` | Checks the machine, proposes each install, update or removal, and runs the ones the user approves |
| `skills/setup-tools/scripts/check-tools.ps1` | Read-only check of the machine: tools, pac installs, agents, official skills and plugins, telemetry. Emits JSON with the `proposals` the skill offers. Writes nothing |
| `skills/setup-tools/scripts/catalog.json` | The tools a machine needs, with minimum and preferred versions and where each minimum comes from; the per-repository tools; the official skills and plugins; the agents that install plugins |
| `skills/setup-tools/scripts/skill-exceptions.json` | The official skill rules the harness overrides, quoted verbatim. `check-tools.ps1` reports a quote no installed copy contains any more |
| `skills/connect/scripts/check-connections.ps1` | Read-only check of the pac profile and the DEV environment. Emits JSON. Writes nothing |
| `skills/setup-project/scripts/discover.ps1` | Read-only inspection of a repository and, through pac, the environment's publishers and solutions. Emits JSON. Writes nothing |
| `skills/setup-project/scripts/standards-baseline.json` | Every version, framework and layout decision the templates assert, and where each is asserted |
| `skills/setup-project/scripts/scaffold.ps1` | Deterministic copy + token substitution. The only thing that writes files |
| `skills/*/scripts/_*.ps1` | Helpers shared by several skills' scripts. Each skill carries an identical copy |
| `skills/setup-project/templates/` | Content shipped verbatim into every scaffolded project |
| `skills/setup-project/templates/scripts/new-feature.ps1` | Shipped to every project: derives the branch and feature solution names, checks them against git and DEV, and creates the branch. It only reads Dataverse; `dv-solution` creates the solution |
| `skills/setup-project/templates/.claude/settings.json` | Shipped to every project: permission rules that enforce the irreversible-operation rules in the standards |
| `tests/` | Checks over this repository: `Test-Repository.ps1` (static invariants), `discovery/` (golden output of the discovery scripts over fixture repositories) and `unit/` (Pester tests of the scaffold's validation, of `new-feature.ps1` and of `check-tools.ps1`'s assessment) |

The split matters: the check and discovery scripts never write, `scaffold.ps1` never asks, and the
skills never generate content that belongs in a template. A change that blurs one of those is the
wrong change.

Every skill is self-contained: it reaches its own scripts by a path relative to its folder and
never another skill's, so it still works installed on its own. A helper two skills need is copied
into both; `tests/Test-Repository.ps1` fails while the copies differ, so edit one and copy it over
the others.

## Rules for changing `skills/setup-project/templates/`

- Template content is the product. Change it only when the standard itself changes, and say why
  in the commit message. No formatting sweeps, no rewording for its own sake.
- Every generated project inherits the change, including projects already scaffolded, which will
  not pick it up automatically. Treat a template change as a breaking change to a published
  contract and note it in the commit.
- `skills/setup-project/templates/docs/agents/development-standards.md` owns the standards index. Adding a
  file under `skills/setup-project/templates/docs/development/` without adding its row to that index leaves
  the file unreachable.
- Keep the template free of anything project-specific or client-specific. This repository is
  public: no environment urls, tenant ids, client names, solution names or real prefixes.
- A version, framework or layout path asserted in `skills/setup-project/templates/docs/development/*.md` is
  also recorded in `skills/setup-project/scripts/standards-baseline.json`, which is what lets an
  existing project be compared against the standards instead of being retargeted to them. Every
  tool version in `skills/setup-project/templates/docs/agents/toolchain.md` is also recorded in
  `skills/setup-tools/scripts/catalog.json`, and every exception in
  `skills/setup-project/templates/docs/agents/skill-exceptions.md` in
  `skills/setup-tools/scripts/skill-exceptions.json`. Change both in the same commit: `discover.ps1`
  and `tests/Test-Repository.ps1` report an entry whose quoted text no longer appears in the file it
  points at, and a stale baseline silently stops reporting real deviations.

## Adapting to an existing project, not the other way round

The harness must never impose a version, framework, test runner or folder layout that a project
does not already use. That rule lives in three places and all three have to hold:

- `discover.ps1` reports what the project actually uses, with the evidence.
- `scaffold.ps1 -SkipExisting` writes only missing files, and `-SkipLayout` suppresses the folder
  layout. Neither ever edits a file the project already has.
- The skill reconciles the *generated* docs in the target repository, never `skills/setup-project/templates/` here.

## Tokens

Tokens are written `{{snake_case}}`. The authoritative list lives in two places that must agree:
the `$tokens` hashtable in `skills/setup-project/scripts/scaffold.ps1`, and the value table in
`skills/set-power-platform/SKILL.md`.

| Token | Resolved from |
| --- | --- |
| `{{project_name}}` | `-ProjectName`. Also the root .NET namespace: there is no separate namespace token |
| `{{publisher_unique_name}}` | `-PublisherUniqueName` |
| `{{publisher_prefix}}` | `-PublisherPrefix` |
| `{{core_solution}}` | `-CoreSolution` (optional, defaults to `none`) |
| `{{project_description}}` | `-ProjectDescription` |
| `{{repository_provider}}` | `-RepositoryProvider`: `github` or `azure-devops` |
| `{{repository_cli}}` | Derived from `-RepositoryProvider`: `gh` or `az repos`. No parameter of its own |

Adding a token means touching all three: the template, the script parameter and hashtable, and
the skill's table. The script fails the scaffold when an unresolved token survives, so a token
added to a template alone breaks every run.

## Verify a change

Run all of these before committing:

```powershell
claude plugin validate .

# Static invariants: shared helpers identical, catalog matches toolchain.md, exceptions match
# skill-exceptions.md, every script parses and stays Windows PowerShell 5.1 compatible.
pwsh -NoProfile -File ./tests/Test-Repository.ps1

# Unit tests: scaffold validation and new-feature.ps1, against a fake pac. Needs Pester 5 or later
# (Install-Module Pester -Scope CurrentUser -SkipPublisherCheck); Windows PowerShell's built-in
# Pester 3.4 cannot run them.
pwsh -NoProfile -Command "Invoke-Pester -Path ./tests/unit -Output Detailed"

# Discovery output over the fixture repositories must match the golden files. A deliberate change
# is recorded with -Update and reviewed in the diff. -Local adds this machine's tools and the
# connected environment, compared against a gitignored snapshot.
pwsh -NoProfile -File ./tests/discovery/Compare-Discovery.ps1

# Discovery must survive a repository it was not designed for, and must report nothing stale.
# standards.staleBaseline is empty when the baseline still matches the templates.
pwsh -NoProfile -File ./skills/setup-project/scripts/discover.ps1 -SkipEnvironment |
    ConvertFrom-Json |
    ForEach-Object { $_.standards.staleBaseline; $_.recommendation.mode }

# Scaffold into a throwaway folder and inspect the result
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) "pph-$([guid]::NewGuid())"
pwsh -NoProfile -File ./skills/setup-project/scripts/scaffold.ps1 -ProjectName Northwind `
    -PublisherUniqueName NorthwindConsulting -PublisherPrefix nwc -CoreSolution NorthwindCore `
    -ProjectDescription 'Test scaffold.' -RepositoryProvider github -TargetPath $tmp

# A second run over the same folder must abort without writing
pwsh -NoProfile -File ./skills/setup-project/scripts/scaffold.ps1 -ProjectName Northwind `
    -PublisherUniqueName NorthwindConsulting -PublisherPrefix nwc -CoreSolution NorthwindCore `
    -ProjectDescription 'Test scaffold.' -RepositoryProvider github -TargetPath $tmp

# The same run with -SkipExisting must add nothing and abort nothing
pwsh -NoProfile -File ./skills/setup-project/scripts/scaffold.ps1 -ProjectName Northwind `
    -PublisherUniqueName NorthwindConsulting -PublisherPrefix nwc -CoreSolution NorthwindCore `
    -ProjectDescription 'Test scaffold.' -RepositoryProvider github -TargetPath $tmp -SkipExisting
```

Every script must also run under Windows PowerShell 5.1, which the generated projects may be
stuck on: no `??`, no ternary, no `ForEach-Object -Parallel`, and no `ProcessStartInfo.ArgumentList`,
and ASCII only, because 5.1 reads a UTF-8 file without a BOM as ANSI. `tests/Test-Repository.ps1`
checks both. `tests/unit/` runs `skills/setup-project/templates/scripts/new-feature.ps1` against a
fake `pac`; to try it against a real DEV, use `-DryRun` in a scaffolded repository: the script only
ever reads the environment.

A rule added to `skills/setup-project/templates/.claude/settings.json` needs both a `Bash(...)` and a `PowerShell(...)`
form: on Windows the agent may run the same command through either tool.

Then bump `version` in `.claude-plugin/plugin.json`: installed plugins update by version.

## Git

- Branch naming: `<type>/<short-description>` (`fix/`, `feature/`, `chore/`).
- Commit messages describe the change and its motivation, not just the action.
- Never force-push or rewrite published history.
- Prefer `gh` for PR creation and inspection over the web UI.

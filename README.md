# Power Platform Harness

A Claude Code plugin that installs the same development harness in every Power Platform /
Dynamics 365 CE repository, so the coding agent knows the rules: what to read before a change,
how to separate business logic from the platform, which solution a component goes into, and when a
task is actually done.

It works on an empty folder and on a project that already exists. In an existing project it
reads the publisher, prefix, core solution and stack out of the repository and the environment
instead of asking, writes only the files that are missing, and adapts the standards to the
versions the project already uses — it never retargets a framework, swaps a test runner or moves a
folder to make a project fit. The standard's version stays visible as a recommended upgrade.

## Scope

In scope: code (C# plugins, Custom APIs, JavaScript web resources, PCF controls) and its unit
tests, and the work an agent does inside DEV — one feature solution per branch, components created
in the right solution.

Out of scope for now: exporting, unpacking, checking, importing or promoting solutions between
environments, and testing or verifying low-code components (flows, forms, views, schema). Those
belong to delivery pipelines that do not exist yet.

## Install

```
/plugin marketplace add FranFdezColoma/power-platform-harness
/plugin install power-platform-harness
```

Then, in the folder you want to set up:

```
/power-platform-harness:set-power-platform
```

## What it creates

```
CLAUDE.md                                # points the agent at the standards
.gitignore                               # .NET, PCF and secrets hygiene
docs/
├── agents/
│   ├── development-standards.md         # cross-technology rules + Definition of Done
│   └── toolchain.md                     # required and recommended tools, with versions
├── development/
│   ├── javascript.md                    # web resources
│   ├── webresources-project.md          # the .esproj + Vitest/ESLint project
│   ├── csharp-plugins.md                # Dataverse plugins
│   ├── pcf.md                           # PCF controls
│   ├── custom-apis.md                   # Custom API contracts
│   ├── dataverse-schema.md              # tables, columns, relationships
│   └── solutions.md                     # feature solution per branch, DEV rules
└── adr/                                 # architecture decision records
src/Dataverse/
├── Dataverse.sln                        # Plugins, CustomAPIs and WebResources solution folders
├── Plugins/
│   └── <Namespace>.Common/              # PluginBase.cs, early-bound classes, shared helpers
├── CustomAPIs/
└── WebResources/
    └── <Project>.WebResources/          # the .esproj + Vitest/ESLint project
```

## How it decides what to do

The skill runs `scripts/discover.ps1` before it asks anything. That script reads — never writes —
and answers:

- whether the required tools are installed and recent enough, and which recommended ones are there;
- whether the folder is empty or an existing project, and whether the harness is already there;
- which publisher, prefix, core solution and root namespace the project already uses, taken from a
  committed `Solution.xml`, from the C# projects, or from a solution exported on request;
- whether `pac` has an authentication profile, which environment it points at, whether its name
  looks like DEV, and which unmanaged solutions already exist in it;
- where the project's real stack differs from what the standards assert.

### Toolchain

| Tool | Tier | Minimum | Preferred |
| --- | --- | --- | --- |
| PowerShell | required | 5.1 | 7 |
| git | required | any | latest |
| .NET SDK | required | 8 | 10 |
| Node.js | required | 22.13 | 24 |
| Power Platform CLI (`pac`), authenticated against DEV | required | any | latest |
| Dataverse MCP server | recommended | | |
| `playwright-cli` or the Playwright MCP server | recommended | | |

A missing or outdated tool never stops the installation — the harness only writes files — but it
is reported as pending with its install command. If `pac` is missing, the skill offers to install
it; if it has no authentication profile, the skill helps create one. MCP servers are checked by the
agent itself, since a script cannot see what is registered with the agent running it.

### Existing projects

Discovery reads the publisher unique name, the customization prefix and the core solution straight
out of a committed `Other/Solution.xml`, and the root namespace out of the `.csproj` files — so the
usual number of questions is small.

Then it compares the project against `scripts/standards-baseline.json`, which records every
version, framework and layout decision the shipped standards assert, and reports the differences:

```
plugins.targetFramework     deviates   standard net462        project net472
plugins.strongNaming        deviates   standard unsigned      project strong-named
plugins.test.xunit          deviates   standard xunit 2.9.3   project 2.4.2
pcf.platformLibrary.react   deviates   standard 16.14.0       project 18.2.0
javascript.lint             deviates   standard eslint 10 flat project eslint 8 (.eslintrc)
```

The project's answer is the one that stands. The generated standards docs are adjusted to state
the project's version, with the harness's version recorded right below as a recommended upgrade,
to be done as its own change. Nothing in the repository is retargeted.

## The values

The skill resolves these across every generated file, so the result carries no placeholders:

| Value | What it is | Example |
| --- | --- | --- |
| `ProjectName` | Short project name, used for the JavaScript form API namespace and the WebResources project | `Northwind` |
| `PublisherUniqueName` | Dataverse publisher unique name, used to create feature solutions | `NorthwindConsulting` |
| `PublisherPrefix` | Dataverse customization prefix, carried by every component | `nwc` |
| `CoreSolution` | Unique name of the core unmanaged solution in DEV, or `none` (optional) | `NorthwindCore` |
| `RootNamespace` | Root .NET namespace | `Northwind` |
| `ProjectDescription` | What the project delivers; becomes the Description section of `CLAUDE.md` | `Customer Service implementation for Northwind.` |

## How work starts afterwards

Every feature, fix or chore goes on its own branch, and the agent asks which branch before the
first change. When the work touches Dataverse, it gets a feature solution named after the branch
(`feature/lead-scoring` → `feature_LeadScoring`). Components are created in the feature solution
and also added to the core solution when the project has one; on the trunk they go to the core
solution alone. The agent writes in DEV only, with `pac` or the Dataverse MCP server, and leaves
irreversible operations — and creating the publisher or the core solution — to a human.

## Run the scripts without Claude Code

The skill is a thin wrapper over two deterministic scripts, both usable on their own, on pwsh 7 or
Windows PowerShell 5.1.

**Discovery** prints a JSON report and changes nothing:

```powershell
pwsh -NoProfile -File ./scripts/discover.ps1 -Path C:\repos\acme

# Repository and toolchain only: no pac calls, no network.
pwsh -NoProfile -File ./scripts/discover.ps1 -SkipEnvironment

# Read the real publisher and prefix out of a solution that exists in the environment but has
# never been unpacked into the repository.
pwsh -NoProfile -File ./scripts/discover.ps1 -ResolvePublisherFromSolution AcmeCore
```

**Scaffolding** writes files and never talks to Dataverse:

```powershell
pwsh -NoProfile -File ./scripts/scaffold.ps1 `
    -ProjectName Northwind `
    -PublisherUniqueName NorthwindConsulting `
    -PublisherPrefix nwc `
    -CoreSolution NorthwindCore `
    -RootNamespace Northwind `
    -ProjectDescription 'Customer Service implementation for Northwind.' `
    -TargetPath C:\repos\northwind `
    -DryRun
```

It validates every value before writing and fails if any token survives substitution. Omit
`-CoreSolution` for a project without a core solution. Three ways to handle a folder that is not
empty:

| Flag | Behaviour |
| --- | --- |
| *(none)* | Abort and list the collisions. Nothing is written |
| `-SkipExisting` | Write what is missing, leave every existing file untouched. Idempotent |
| `-Force` | Overwrite. Rejected together with `-SkipExisting` |

`-SkipLayout` suppresses the `src/Dataverse/` and `docs/adr/` folders, for a project that already
has its own layout. `-SkipCodeProjects` leaves out the projects under `src/Dataverse/`:
`Dataverse.sln`, the Common library and the WebResources project. `-Json` emits a parseable
summary of what was created, skipped and overwritten.

## Contributing

`templates/` is the content shipped to every project: see `CLAUDE.md` for the rules on changing
it. A version or framework stated in `templates/docs/development/*.md`, and every tool version in
`templates/docs/agents/toolchain.md`, is also recorded in `scripts/standards-baseline.json`; the
two change together, and discovery reports the baseline as stale if they drift apart.

## License

MIT

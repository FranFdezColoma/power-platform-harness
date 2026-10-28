# Power Platform Harness

> **This branch is 2.0 in progress.** `main` holds the current release (1.x, script-based). The
> design is in `docs/design/2.0-architecture.md`.

An agent plugin that installs the same development harness in every Power Platform / Dynamics 365
CE repository, so the coding agent knows the rules: what to read before a change, how to separate
business logic from the platform, which solution a component goes into, and when a task is
actually done.

It works on an empty folder and on a project that already exists. In an existing project it reads
the publisher, prefix, core solution and stack out of the repository and the environment instead
of asking, writes only the files that are missing, and adapts the standards to the versions the
project already uses — it never retargets a framework, swaps a test runner or moves a folder to
make a project fit.

The skills are written in natural language, with no scripts: the agent running them inspects the
machine and the repository itself and checks versions against the official sources at that
moment, so the harness carries no version list to maintain. It proposes; you approve.

Microsoft's [Dataverse skills](https://github.com/microsoft/Dataverse-skills) and
[Power Platform skills](https://github.com/microsoft/power-platform-skills) supply the
capabilities — connecting, metadata, data, solutions, apps, flows. The harness supplies the
conventions, and declares every official rule it overrides.

## Install

In Claude Code:

```
/plugin marketplace add FranFdezColoma/power-platform-harness
/plugin install power-platform-harness
```

Then, in the folder you want to set up:

```
/power-platform-harness:set-power-platform
```

## Skills

| Skill | What it does |
| --- | --- |
| `set-power-platform` | Runs the three below in order and reports once |
| `setup-tools` | Checks the machine — PowerShell, git, .NET SDK, Node.js, `pac`, Python, `az`, `gh`, the Dataverse skills and the model-apps, power-automate and Ponytail plugins — and proposes each install, update or removal |
| `setup-project` | Writes the harness files into the repository, or adopts it into an existing one |
| `connect` | Checks `pac`, DEV, the tenant, the repository and the Dataverse MCP server against `.power-platform/project.json`, and hands anything missing to `dv-connect` |

Each one can be run on its own.

## What it writes

```
AGENTS.md                                # the harness instructions, for every agent
CLAUDE.md                                # @AGENTS.md
.gitignore                               # .NET, PCF and secrets hygiene
.claude/settings.json                    # denies irreversible operations, allows read-only checks
.power-platform/project.json             # project identity and expected connections; no secrets
docs/
├── agents/
│   ├── development-standards.md         # cross-technology rules + Definition of Done
│   ├── toolchain.md                     # the tools a machine needs, and what for
│   └── skill-exceptions.md              # the official skill rules this project overrides
└── development/
    ├── javascript.md                    # web resources
    ├── webresources-project.md          # the .esproj + Vitest/ESLint project
    ├── csharp-plugins.md                # Dataverse plugins
    ├── pcf.md                           # PCF controls
    ├── custom-apis.md                   # Custom API contracts
    ├── dataverse-schema.md              # tables, columns, relationships
    └── solutions.md                     # feature solution per branch, DEV rules
```

No code is generated up front. The standards describe `src/PowerPlatform/PowerPlatform.sln`, the
shared `<Project>.Common` library and the WebResources project, and the agent creates each one the
first time a change needs it, pinning the latest stable versions at that moment.

## How work starts afterwards

Every feature, fix or chore goes on its own branch, and the agent asks which branch before the
first change. When the work touches Dataverse, it gets a feature solution named after the branch
(`feature/lead-scoring` → `feature_LeadScoring`), created by `dv-solution` after the agent has
checked that the branch and the name are free, that `pac` points at DEV and that the publisher is
the project's. Components are created in the feature solution and also added to the core solution
when the project has one. The agent writes in DEV only, and leaves irreversible operations — and
creating the publisher or the core solution — to a human.

## License

MIT

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

Delivery is spec-first with [OpenSpec](https://github.com/Fission-AI/OpenSpec): every change is
proposed as a proposal, specs, a design and tasks, passes a functional and a technical gate
recorded in `approval.md`, and only then is implemented against the development standards. The
design follows solutioning principles — standard before customization, customization before
automation, automation before code — after inspecting what already exists in DEV.

Microsoft's [Dataverse skills](https://github.com/microsoft/Dataverse-skills) and
[Power Platform skills](https://github.com/microsoft/power-platform-skills) supply the
capabilities — connecting, metadata, data, solutions, apps, flows. The harness supplies the
conventions the agent applies while it uses them.

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
| `set-power-platform` | Runs `setup-tools`, `connect`, `setup-project` and `connect` again, and reports once |
| `setup-tools` | Checks the machine — PowerShell, git, .NET SDK, Node.js, `pac`, Python, `az`, `gh`, the OpenSpec CLI, `playwright-cli` and its skill, the Dataverse skills, the model-apps and power-automate plugins and, recommended, Ponytail — and proposes each install, update or removal |
| `connect` | Signs you in, giving each command and verifying it: a `pac` profile for DEV, `az` in the tenant, the repository (`gh` for GitHub, `az` for Azure DevOps), the `playwright-cli` session; then checks the Dataverse MCP server — or, when the tenant restricts it, the `az` session the Dataverse skills' Python SDK takes its token from — and hands anything missing to `dv-connect` |
| `setup-project` | Writes the harness files, runs `openspec init`, and writes the starting code into a new repository, adopts the harness into an existing one, or proposes what the templates changed in one that has it |

Each one can be run on its own.

## What it writes

```
AGENTS.md                                # the index: what each OpenSpec step reads, the gates
CLAUDE.md                                # @AGENTS.md
README.md                                # for people: how to approve a change
.gitignore                               # .NET, PCF and secrets hygiene
.claude/settings.json                    # allows the agent's work, asks before deletes and imports
.power-platform/project.json             # project identity and expected connections; no secrets
solutions/README.md                      # exported solution source goes here
scripts/README.md                        # the Dataverse skills' helper scripts go here
src/PowerPlatform/                       # new project only: PowerPlatform.sln, <Project>.Common, WebResources
openspec/config.yaml                     # OpenSpec, with the artifact language
.claude/ .github/ .agents/               # the /opsx skills and commands, written by `openspec init`
docs/
├── context/
│   ├── project.md                       # client, product, scope, constraints
│   └── glossary.md                      # business terms used in specs
├── adr/0000-template.md                 # architecture decision records
├── agents/
│   ├── solutioning-standards.md         # what design.md reads
│   ├── development-standards.md         # cross-technology rules + Definition of Done
│   └── toolchain.md                     # the tools a machine needs, and what for
├── solutioning/
│   └── principles.md                    # current state, the ladder, decisions, open questions
└── development/
    ├── javascript.md                    # web resources
    ├── webresources-project.md          # the .esproj + Vitest/ESLint project
    ├── csharp-plugins.md                # Dataverse plugins
    ├── pcf.md                           # PCF controls
    ├── custom-apis.md                   # Custom API contracts
    ├── dataverse-schema.md              # tables, columns, relationships
    └── solutions.md                     # feature solution per branch, DEV rules
```

In a new project, `setup-project` also creates `src/PowerPlatform/PowerPlatform.sln`, the shared
`<Project>.Common` library and the WebResources project from the standards, pinning the latest
stable versions at that moment, and checks that they build and that the tests and lint pass. In an
existing project nothing is generated: each one is created the first time a change needs it.
Plugins, Custom APIs and PCF controls are always created with the change that needs them.

## How work starts afterwards

Every change starts with `/opsx:propose`, which creates its branch (`feature/lead-scoring`) before
writing the artifacts and an `approval.md` with both gates `Pending`. A person approves each gate
by editing that file on the branch; `/opsx:apply` implements nothing until both are approved. A
quick fix outside OpenSpec still gets its own branch, asked before the first change.

When the work touches Dataverse, it gets a feature solution named after the branch
(`feature/lead-scoring` → `feature_LeadScoring`), created by `dv-solution` at the start of
`/opsx:apply`, after the agent has
checked that the branch and the name are free, that `pac` points at DEV and that the publisher is
the project's. Components are created in the feature solution and also added to the core solution
when the project has one. The agent writes in DEV only, and leaves irreversible operations — and
creating the publisher or the core solution — to a human.

## Authors

- Fran ([FranFdezColoma](https://github.com/FranFdezColoma)): the development harness.
- Ignacio Barrio Santos ([NachoBarrio](https://github.com/NachoBarrio)): the spec-driven framework —
  the OpenSpec index, the gates, the project context and the solutioning standards.

## License

MIT

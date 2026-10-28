# Description

This repository is an agent plugin that sets up Power Platform / Dynamics 365 CE repositories. Its
skills live under `skills/`, and the templates they write under `skills/setup-project/templates/`.

It is not a Power Platform project: nothing here is deployed to Dataverse. The standards in
`skills/setup-project/templates/docs/` govern the projects this plugin creates, not this repository.

**2.0 is in progress** on `feature/onlySkills`; the OpenSpec merge (2.3.0) on `feature/mergeWithNacho`. `docs/design/2.0-architecture.md` holds the agreed
design; read it before changing anything.

## Layout

| Path | What it is |
| --- | --- |
| `.claude-plugin/plugin.json` | Plugin manifest. Lists the skills explicitly |
| `.claude-plugin/marketplace.json` | Makes this repo its own single-plugin marketplace |
| `skills/set-power-platform/SKILL.md` | The skill users run: runs `setup-tools`, `connect`, `setup-project` and `connect` again, and reports once |
| `skills/setup-tools/SKILL.md` | The machine: inspects tools, skills and plugins, proposes each install, update or removal |
| `skills/setup-project/SKILL.md` | The repository: copies the templates, runs `openspec init`, creates a new project's starting code, adapts them to an existing project |
| `skills/setup-project/scripts/new-folders.ps1` | Creates the folder tree of a new project: `Plugins`, `CustomAPIs`, the WebResources `<prefix>_/src/...` folders, `docs/adr` |
| `skills/setup-project/templates/` | Content shipped verbatim, tokens replaced, into every project |
| `skills/connect/SKILL.md` | The sign-ins, and the connections `.power-platform/project.json` expects |

The skills are markdown; the agent running a skill does the inspection itself. The one exception is
`skills/setup-project/scripts/new-folders.ps1`, which creates a new project's folder tree (and its
`.gitkeep` files), because a directory tree is mechanical and must come out the same every time.
Do not add another script unless something genuinely cannot be done otherwise, and do not add a
version, minimum or catalog that someone would have to keep current. Every skill is
self-contained: it reaches only its own folder, so it still works installed on its own.

## Rules for changing `skills/setup-project/templates/`

- Template content is the product. Change it only when the standard itself changes, and say why
  in the commit message. No formatting sweeps, no rewording for its own sake.
- Every generated project inherits the change, including projects already set up, which will not
  pick it up automatically. Treat a template change as a breaking change to a published contract
  and note it in the commit.
- `skills/setup-project/templates/docs/agents/development-standards.md` owns the standards index.
  Adding a file under `docs/development/` without adding its row to that index leaves the file
  unreachable. The same holds for `docs/solutioning/` and the index in `solutioning-standards.md`;
  `docs/agents/openspec-workflow.md` routes each OpenSpec step to those gate files.
- What `openspec init` generates is not a template: never copy OpenSpec skills or commands into
  `templates/`.
- Keep the template free of anything project-specific or client-specific. This repository is
  public: no environment urls, tenant ids, client names, solution names or real prefixes.
- No hand-written versions. A pin a project needs is described, and resolved when the project
  creates it (see "Versions" in `development-standards.md`).
- A rule added to `templates/.claude/settings.json` needs both a `Bash(...)` and a
  `PowerShell(...)` form: on Windows the agent may run the same command through either tool.

## Tokens

Tokens are written `{{snake_case}}`. The authoritative list is the values table in
`skills/setup-project/SKILL.md`; a token used in a template must be in it.

## Verify a change

```powershell
claude plugin validate .
```

Then try the skill the change touches in a throwaway folder, and bump `version` in
`.claude-plugin/plugin.json`: installed plugins update by version.

## Git

- Branch naming: `<type>/<short-description>` (`fix/`, `feature/`, `chore/`).
- Commit messages describe the change and its motivation, not just the action.
- Never force-push or rewrite published history.

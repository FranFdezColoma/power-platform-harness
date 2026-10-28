# Solutions Standards

Read `docs/agents/development-standards.md` first. This file only adds what is specific to solutions and to working against the DEV environment.

Scope: everything that happens inside DEV — which solution a component goes into, how the per-branch feature solution is created, and how it is exported into the repository before the pull request. The official `dv-solution` skill performs these operations; this file sets the names, the order and the limits. Promoting a solution to test or production belongs to a human or a delivery pipeline, never to the agent (exception E4 in `docs/agents/skill-exceptions.md`).

## Environments

- DEV is shared: every change lands where colleagues are working. There are no per-developer environments.
- DEV is the environment `.power-platform/project.json` names (`connections.dataverse.devUrl`). Name the environment before any operation against it (`pac org who --environment <devUrl>`). An environment you have not verified is production.
- Write operations are permitted in DEV only, and only with a tool that can perform them: the official skills, `pac`, the Dataverse CLI or the Dataverse MCP server. Without one, prepare the operation and hand it to the developer.
- Irreversible operations are prepared, not executed: deleting a table, column, relationship, record or solution; changing the data type of a populated column. A human runs them.
- Never create or modify a component without a target solution. A component created outside one lands in the Default Solution, where nothing tracks it.

## Solutions

- Publisher: unique name `{{publisher_unique_name}}`, customization prefix `{{publisher_prefix}}`, for every component and every solution.
- Core solution: `{{core_solution}}`. `none` means this project has no core solution, and the rules below that mention it do not apply.
- **Feature solution**: one per branch, named from it. It records what that piece of work created or touched.
- Every solution is unmanaged in DEV. Solution unique names carry no publisher prefix.

## Starting a unit of work

Before writing any code or touching any component, settle where the work lives. Ask the user, and wait:

> Do you want to develop this on the current branch `<branch>`, or on a new one?

- **Current branch** — continue. If it has a feature solution, components go into it.
- **Current branch is the trunk** (`main`, `master`, or the repository's default branch) — it has no feature solution. If the core solution exists, say that the change lands in the core solution alone, and continue. If the core solution is `none`, there is no solution to put a component in: ask for a new branch instead.
- **New branch** — create the branch with `scripts/new-feature.ps1` and its feature solution with `dv-solution`, below. Never skip the question because the intent seems obvious.

### Names

Both names come from one answer, so the branch and the solution can never drift apart:

| Thing | Rule | Example |
| --- | --- | --- |
| Branch | `<type>/<short-description>`, type is `feature`, `fix` or `chore`, description in kebab-case | `feature/lead-scoring-widget` |
| Feature solution | `<type>_<ShortDescriptionInPascalCase>`, at most 65 characters | `feature_LeadScoringWidget` |

Propose the short description from what the user asked for and confirm it before creating anything: the solution unique name follows it and cannot be renamed afterwards.

### Create the branch and the feature solution

`scripts/new-feature.ps1` derives both names, checks that they are free, and creates the branch. It never creates the solution: `dv-solution` does, with the name the script prints. Never derive the names by hand: each manual step is a chance to get the name, the version or the publisher wrong, and none of them can be corrected afterwards.

```bash
pwsh -NoProfile -File scripts/new-feature.ps1 -Type <feature|fix|chore> -Name <short-description> -DryRun
pwsh -NoProfile -File scripts/new-feature.ps1 -Type <feature|fix|chore> -Name <short-description>
```

- Run the dry run first and show the user its plan: branch, feature solution, publisher and environment.
- The script checks everything before anything is changed: the branch does not exist yet, here or on origin; `pac` reaches the DEV environment `.power-platform/project.json` names, and it does not look like production or test; publisher `{{publisher_unique_name}}` exists there with prefix `{{publisher_prefix}}`; and no solution already has that unique name. When a check fails, report its message as is; do not work around it.
- Offer both ways of creating the branch, and let the user choose:
  - **Checkout** — the default. Uncommitted changes move to the new branch.
  - **Worktree** — add `-Worktree`: the branch is created in `../<repo>.worktrees/<type>/<short-description>`; continue inside it. Recommend it when another session is working in this folder: switching its branch underneath it loses work.
- Work that creates or modifies no Dataverse component (a dependency bump, a code-only refactor) needs no feature solution: add `-SkipSolution` to check and create only the branch.
- Then create the feature solution with `dv-solution`, exactly as the script printed it: that unique name, version `1.0.0.0`, unmanaged, publisher `{{publisher_unique_name}}`, in DEV. Creating a solution is a human decision: do it only after the user confirms, never as a side effect of another task. Do not publish customizations: publishing in a shared DEV publishes every colleague's unpublished work along with it.
- Re-running the script on the branch it created keeps the branch and repeats the checks, so the solution step can be retried.

## Which solution a component goes into

| Situation | Create the component in | Then add it to |
| --- | --- | --- |
| Feature solution exists, core solution exists | the feature solution | the core solution |
| Feature solution exists, core solution is `none` | the feature solution | — |
| No feature solution (trunk), core solution exists | the core solution | — |
| No feature solution, core solution is `none` | nowhere: ask for a new branch first | — |

Add an existing component to another solution with:

```bash
pac solution add-solution-component --environment <devUrl> --solutionUniqueName <solution> --component <schema-name-or-id> --componentType <n> --AddRequiredComponents
```

- `--environment` takes the DEV url from `.power-platform/project.json`, so the command never depends on which `pac` profile is active.
- `--component` accepts a schema name as well as an id. Prefer the schema name: it is the value already in the code.
- `--componentType` is a number. The common ones in this stack: entity `1`, attribute `2`, global choice `9`, saved query `26`, workflow and cloud flow `29`, form `60`, web resource `61`, plug-in assembly `91`, plug-in step `92`, canvas app `300`, environment variable definition `380`, environment variable value `381`. Anything not on that list is looked up in the [SolutionComponent reference](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/reference/entities/solutioncomponent), never guessed.
- Some components have no fixed number: they are table-based, and their type code depends on the environment. Connection references are one (`371` and `372` are connectors, not connection references). For those, and for any type the reference does not list, read the code from the environment: the component already exists, so `GET <env>/api/data/v9.2/solutioncomponents?$filter=objectid eq <component-id>&$select=componenttype` returns the number Dataverse itself uses.
- Adding a component to a solution is additive and reversible; it does not need the confirmation that creating a solution does.
- Do this as each component is created or modified, not as a sweep at the end.

## Configuration that varies by environment

- URLs, endpoints, keys, external identifiers and toggles are environment variables. Connections are connection references. Nothing else is acceptable.
- An environment variable ships with a default value only when that default is safe in every environment. Secrets never ship a default value.
- Secrets live in Azure Key Vault, referenced from an environment variable. Never in a solution.
- Every new environment variable and connection reference is documented with the change: name, purpose, and the value expected per environment.

## Before the pull request

The feature solution goes into the repository with the branch, so the review diff shows what the branch touched in DEV:

- Export it with `dv-solution` (export, unpack, delete the zip) into `solutions/<feature solution>/`, and commit the unpacked source on the branch. `solutions/` sits at the repository root, next to `src/`: generated solution source and hand-written code stay apart.
- The core solution `{{core_solution}}` is exported only from the trunk, as an explicit operation the user asks for. Exporting it from a branch would capture colleagues' unfinished work in the shared DEV.
- Importing goes to DEV only (exception E4). Promotion to test or production is a human's or a pipeline's job.

## After the merge

- The feature solution stays in DEV. It is the record of what that branch touched. Nothing deletes it automatically.
- Remove the branch once merged, and its worktree if it had one: `git worktree remove <path>`.

# Solutions Standards

Read `docs/agents/development-standards.md` first. This file only adds what is specific to solutions and to working against the DEV environment.

Scope: everything that happens inside DEV — which solution a component goes into, how the per-branch feature solution is created, and how it is exported into the repository before the pull request. The official `dv-solution` skill performs these operations; this file sets the names, the order and the limits. Promoting a solution to test or production belongs to a human or a delivery pipeline, never to the agent.

## Environments

- DEV is shared: every change lands where colleagues are working. There are no per-developer environments.
- DEV is the environment `.power-platform/project.json` names (`connections.dataverse.devUrl`). Naming it, what may be written there and the irreversible operations follow "Working against Dataverse" in `docs/agents/development-standards.md`.
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
- **New branch** — check and create the branch, then its feature solution with `dv-solution`, below. Never skip the question because the intent seems obvious.

### An OpenSpec change

An OpenSpec change does not ask the question above: it always gets a new branch, and its short description is the change name, so the change, the branch and the solution share one name.

- **At /opsx:propose**, before any artifact is written: ask the type, then run check 1 below and create the branch. The artifacts and `approval.md` are committed on it.
- **At /opsx:apply**, after `approval.md` shows both gates `Approved` and before the first task: run checks 2 to 4 and create the feature solution, as below. A change that creates or modifies no Dataverse component needs none.

A change whose proposal is rejected leaves a branch and no solution in DEV.

### Names

Both names come from one answer, so the branch and the solution can never drift apart:

| Thing | Rule | Example |
| --- | --- | --- |
| Branch | `<type>/<short-description>`, type is `feature`, `fix` or `chore`, description in kebab-case: lowercase letters and digits separated by single hyphens | `feature/lead-scoring-widget` |
| Feature solution | `<type>_<ShortDescriptionInPascalCase>`: each kebab-case word capitalised and joined, at most 65 characters (the length of Dataverse's unique name column) | `feature_LeadScoringWidget` |

Propose the short description from what the user asked for and confirm it before creating anything: the solution unique name follows it and cannot be renamed afterwards.

### Create the branch and the feature solution

Check everything before changing anything. When a check fails, stop, say which one and why, and change nothing; do not work around it.

1. The branch does not exist yet, locally or on origin (`git branch --list <branch>`, `git ls-remote --heads origin <branch>`).
2. `pac org who --environment <devUrl>` reaches the DEV environment `.power-platform/project.json` names (`connections.dataverse.devUrl`), and its name does not look like production or test (`prod`, `prd`, `live`, `test`, `qa`, `uat`, `stag`, `preprod`).
3. Publisher `{{publisher_unique_name}}` exists there with prefix `{{publisher_prefix}}`.
4. No solution in DEV already has the feature solution's unique name.

Then show the user the plan — branch, feature solution, publisher and environment — and wait for the go-ahead.

- Offer both ways of creating the branch, and let the user choose:
  - **Checkout** — the default: `git switch -c <branch>`. Uncommitted changes move to the new branch.
  - **Worktree** — `git worktree add -b <branch> ../<repo>.worktrees/<type>/<short-description>`; continue inside it. Recommend it when another session is working in this folder: switching its branch underneath it loses work.
- Work that creates or modifies no Dataverse component (a dependency bump, a code-only refactor) needs no feature solution: run check 1 only and create the branch.
- Then create the feature solution with `dv-solution`: that unique name, version `1.0.0.0`, unmanaged, publisher `{{publisher_unique_name}}`, in DEV. Creating a solution is a human decision: do it only after the user confirms, never as a side effect of another task.
- If creating the solution fails, stay on the branch, repeat checks 2 to 4 and retry.

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
- Importing goes to DEV only. Promotion to test or production is a human's or a pipeline's job.

## After the merge

- The feature solution stays in DEV. It is the record of what that branch touched. Nothing deletes it automatically.
- Remove the branch once merged, and its worktree if it had one: `git worktree remove <path>`.

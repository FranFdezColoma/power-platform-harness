# Solutions Standards

Read `docs/agents/development-standards.md` first. This file only adds what is specific to solutions and to working against the DEV environment.

Scope: everything that happens inside DEV — which solution a component goes into, and how the per-branch feature solution is created. Exporting, unpacking, checking, importing and promoting solutions between environments are out of scope: they belong to delivery pipelines that do not exist yet. Do not improvise them.

## Environments

- DEV is shared: every change lands where colleagues are working. There are no per-developer environments.
- Name the environment before any operation against it (`pac org who`). An environment you have not verified is production.
- Write operations are permitted in DEV only, and only with a tool that can perform them: `pac` or the Dataverse MCP server. Without one, prepare the operation and hand it to the developer.
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
- **New branch** — derive the names, create the branch, then create the feature solution. Never skip the question because the intent seems obvious.

### Names

Derive both names from one answer, so the branch and the solution can never drift apart:

| Thing | Rule | Example |
| --- | --- | --- |
| Branch | `<type>/<short-description>`, type is `feature`, `fix` or `chore` | `feature/lead-scoring-widget` |
| Feature solution | `<type>_<ShortDescriptionInPascalCase>` | `feature_LeadScoringWidget` |

Propose the branch name from what the user asked for and confirm it before creating anything: the solution unique name follows it and cannot be renamed afterwards.

### Create the branch

Offer both, and let the user choose:

- **Checkout** — `git switch -c <type>/<short-description>`. The default.
- **Worktree** — `git worktree add -b <type>/<short-description> ../<repo>.worktrees/<type>/<short-description>`, then continue inside it. Recommend it when another session is working in this folder: switching its branch underneath it loses work.

### Create the feature solution

`pac` has no command that creates a solution in Dataverse — `pac solution init` only scaffolds a local project. The sequence below is the whole creation path; run it in a throwaway folder, never inside the repository.

```bash
pac solution init --publisher-name {{publisher_unique_name}} --publisher-prefix {{publisher_prefix}} --outputDirectory <temp>/<type>_<Name>
# pac solution init writes version 1.0; every solution starts at 1.0.0.0
pwsh -NoProfile -Command "(Get-Content -Raw '<temp>/<type>_<Name>/src/Other/Solution.xml') -replace '<Version>1\.0</Version>', '<Version>1.0.0.0</Version>' | Set-Content -NoNewline '<temp>/<type>_<Name>/src/Other/Solution.xml'"
pac solution pack --folder <temp>/<type>_<Name>/src --zipfile <temp>/<type>_<Name>.zip --packagetype Unmanaged
pac solution import --path <temp>/<type>_<Name>.zip --publish-changes
```

- Every solution is created at version `1.0.0.0` (`major.minor.build.revision`). `pac solution init` writes `1.0` and `pac solution version` only changes build and revision, so set the version in `Solution.xml` before packing, as above. Check that it reads `<Version>1.0.0.0</Version>` before importing.
- With the Dataverse MCP server and no working `pac` authentication, create the `solution` record through the server instead: same unique name, the publisher above, version `1.0.0.0`.
- Creating a solution is a human decision. Show the commands and the resolved names, ask, and only then run them. Never as a side effect of another task.
- Report the created solution and verify that it exists: `pac solution list`, or the same query through the MCP server.

## Which solution a component goes into

| Situation | Create the component in | Then add it to |
| --- | --- | --- |
| Feature solution exists, core solution exists | the feature solution | the core solution |
| Feature solution exists, core solution is `none` | the feature solution | — |
| No feature solution (trunk), core solution exists | the core solution | — |
| No feature solution, core solution is `none` | nowhere: ask for a new branch first | — |

Add an existing component to another solution with:

```bash
pac solution add-solution-component --solutionUniqueName <solution> --component <schema-name-or-id> --componentType <n> --AddRequiredComponents
```

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

## After the merge

- The feature solution stays in DEV. It is the record of what that branch touched. Nothing deletes it automatically.
- Remove the branch once merged, and its worktree if it had one: `git worktree remove <path>`.

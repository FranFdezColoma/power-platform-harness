# WebResources Project Standards

Read `docs/agents/development-standards.md` first, and `docs/development/javascript.md` for the
language, structure and testing rules the web resources themselves follow. This file only covers
the project that wraps them for the IDE and the test/lint tooling.

## Stack

- The WebResources folder is an SDK-style project: `src/Dataverse/WebResources/{{project_name}}.WebResources/{{project_name}}.WebResources.esproj`, using `Sdk="Microsoft.VisualStudio.JavaScript.Sdk/1.0.6887863"`. The version is pinned in the `Sdk` attribute: the SDK is distributed through NuGet, not installed with Visual Studio or the .NET SDK, so MSBuild cannot resolve it without a version and Visual Studio leaves the project unloaded. A project that already pins a different version keeps it; upgrading is its own task.
- `src/Dataverse/Dataverse.sln` references this project inside the `WebResources` solution folder, so Visual Studio shows it under that folder. Plugin and Custom API projects go into the same solution, in their own solution folders: see `docs/development/csharp-plugins.md`.
- Tooling is test and lint only: Vitest + ESLint, per `docs/development/javascript.md`. No bundler, no TypeScript, no UI framework — the `.esproj` is a Visual Studio convenience for editing and testing the plain JavaScript web resources described there, not a build step. Introducing one is a separate, deliberate decision, not a side effect of adopting this standard.

## Structure

- Source lives under `{{publisher_prefix}}_/src/{js,html,css,icons}`, matching the prefix-underscore convention Dataverse expects component names to start with. Form scripts go one folder deeper, per table: `{{publisher_prefix}}_/src/js/<table>/`, per `docs/development/javascript.md`.
- `eslint.config.mjs` lints deployed files as ES2020 scripts with `Xrm` as a read-only global, and lets only `*.test.js` and the `.mjs` tooling configuration use ES modules. Keep that split: it is what enforces the no-module-syntax rule on deployed files.
- `package.json`, `vitest.config.mjs` and `eslint.config.mjs` sit next to the `.esproj`, scoped to this project only.

## Adapting to an existing project

A repository that already edits web resources without this project is not missing something
broken — many teams manage Dataverse web resources with nothing more than a text editor. Installing
this project into an existing repository happens only when the user asks for it: see the
reconciliation step in the `set-power-platform` skill.

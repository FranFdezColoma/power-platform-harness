# WebResources Project Standards

Read `docs/agents/development-standards.md` first, and `docs/development/javascript.md` for the
language, structure and testing rules the web resources themselves follow. This file only covers
the project that wraps them for the IDE and the test/lint tooling.

## Stack

- The WebResources folder is an SDK-style project: `src/PowerPlatform/WebResources/{{project_name}}.WebResources/{{project_name}}.WebResources.esproj`, using `Sdk="Microsoft.VisualStudio.JavaScript.Sdk/<version>"`. The `Sdk` attribute always carries a version: the SDK is distributed through NuGet, not installed with Visual Studio or the .NET SDK, so MSBuild cannot resolve it without one and Visual Studio leaves the project unloaded. When creating the project, pin the latest stable version of `Microsoft.VisualStudio.JavaScript.Sdk` on NuGet. A project that already pins a version keeps it; upgrading is its own task.
- `src/PowerPlatform/PowerPlatform.sln` references this project inside the `WebResources` solution folder, so Visual Studio shows it under that folder. Plugin and Custom API projects go into the same solution, in their own solution folders: see `docs/development/csharp-plugins.md`.
- Tooling is test and lint only: Vitest + ESLint, per `docs/development/javascript.md`. No bundler, no TypeScript, no UI framework — the `.esproj` is a Visual Studio convenience for editing and testing the plain JavaScript web resources described there, not a build step. Introducing one is a separate, deliberate decision, not a side effect of adopting this standard.

## Structure

- Source lives under `{{publisher_prefix}}_/src/{js,html,css,icons}`, matching the prefix-underscore convention Dataverse expects component names to start with. Form scripts go one folder deeper, per table: `{{publisher_prefix}}_/src/js/<table>/`, per `docs/development/javascript.md`.
- `eslint.config.mjs` lints deployed files as ES2020 scripts with `Xrm` as a read-only global, and lets only `*.test.js` and the `.mjs` tooling configuration use ES modules. Keep that split: it is what enforces the no-module-syntax rule on deployed files.
- `package.json`, `vitest.config.mjs` and `eslint.config.mjs` sit next to the `.esproj`, scoped to this project only.
- `package.json` is private and named `{{publisher_prefix}}-webresources`. Its scripts are `test` (`vitest run --passWithNoTests`), `test:watch` (`vitest`) and `lint` (`eslint .`). Its dev dependencies are `eslint`, `@eslint/js`, `vitest`, `@vitest/coverage-v8` and `xrm-mock`, each pinned per `docs/agents/development-standards.md`.

## Creating it

The first web resource creates this project when it does not exist yet: the `.esproj`, the three files next to it, and its entry in `PowerPlatform.sln` (creating the solution if needed, per `docs/development/csharp-plugins.md`). The `{{publisher_prefix}}_/src/{js,html,css,icons}` folders are created with the rest of the folder tree by `setup-project`'s `new-folders.ps1`.

## Adapting to an existing project

A repository that already edits web resources without this project is not missing something
broken — many teams manage Dataverse web resources with nothing more than a text editor. Create
this project in an existing repository only when the user asks for it.

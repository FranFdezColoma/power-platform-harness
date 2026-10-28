# Exceptions to the official skills

The official skills apply in this repository except where an entry below overrides one of their rules. Each entry quotes the overridden rule verbatim, so it stays recognisable when the skill is updated. This list is closed: an exception exists only because the harness declares it here, never because a standard happens to read differently from a skill. A conflict that is not on this list is a defect: report it instead of resolving it.

An entry whose quote no longer appears in the installed skill is **stale**: the official rule changed, and the exception no longer says what it overrides. The harness's `setup-tools` skill looks for each quote after installing or updating the official skills. Until the entry is updated, follow the official skill and report the stale entry.

## E2. Code lives in `src/PowerPlatform/`

- **Overrides** `dv-connect`: "mkdir -p solutions plugins scripts"
- **Rule:** Hand-written code lives under `src/PowerPlatform/` (`Plugins/`, `CustomAPIs/`, `WebResources/`), never in a root `plugins/` folder. `solutions/` and `scripts/` sit at the repository root, as `dv-connect` says.
- **Scope:** The repository layout.
- **Reason:** One solution file builds all the code, and hand-written code stays apart from the solution source that export and unpack generate. The harness lays the repository out before `dv-connect` prepares the workspace, so `dv-connect` finds `scripts/` and skips that step.

## E3. The testing rules prevail over Ponytail

- **Overrides** Ponytail: "leaves one small test or an assert-based self-check"
- **Rule:** The Testing section and the Definition of Done in `docs/agents/development-standards.md` decide which tests a change requires. Ponytail governs everything else.
- **Scope:** Tests for plugins, Custom APIs, web resources and PCF controls.
- **Reason:** Code that rejects an operation or keeps data consistent needs its edge cases and failure paths covered, test-first. One test leaves them unproven.

## E4. Imports go to DEV only

- **Overrides** `dv-solution`: "## Push: Pack + Import"
- **Rule:** The agent packs and imports a solution only into the DEV environment `.power-platform/project.json` names, after confirming that the session points at it. Promotion to test or production is done by a human or a pipeline.
- **Scope:** Every solution import, and every other write against an environment.
- **Reason:** Every environment other than DEV holds work or data that an unreviewed import could overwrite, and an import cannot be undone.

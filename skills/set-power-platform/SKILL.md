---
name: set-power-platform
description: "Install the Power Platform / Dynamics 365 CE harness in this folder, end to end: prepare the machine (setup-tools), sign in to DEV, the tenant and the repository (connect), and write the agent instructions, development standards, per-branch feature solution workflow and, for a new project, the starting code into the repository (setup-project). Works on an empty folder and on an existing project, where it adapts the standards to the versions the project already uses."
disable-model-invocation: true
allowed-tools: Bash, PowerShell, Read, Write, Edit, Glob, Grep, AskUserQuestion
---

# Install the Power Platform harness

Three skills of this plugin do the work, in this order, `connect` twice. This skill only runs them and closes with one report.

1. **`setup-tools`** — the machine: CLIs, runtimes, the official skills and plugins.
2. **`connect`** — the sign-ins: `pac` against DEV, `az` in the tenant, the repository, the `playwright-cli` session.
3. **`setup-project`** — the repository: the harness files, adapted to an existing project, and the starting code for a new one. With `pac` signed in, it reads the publisher, prefix and core solution from DEV instead of asking.
4. **`connect`** again — records the connections in `.power-platform/project.json` and hands the Dataverse MCP server and `.env` to `dv-connect`, now that the repository is laid out (exception E2 in `docs/agents/skill-exceptions.md`).

Each one can also run on its own; this skill adds nothing to what they do.

## 0. Language

Decide the conversation's language before anything else.

- If the user wrote something in this session before the skill ran, that message is the answer: use its language and do not ask.
- If the skill is the first thing in the session, ask which language to use: a closed choice (Spanish, English, French, German), through your structured question tool if you have one, else a numbered list.

Use that language for every question and report, in this skill and the three it runs. What gets written into the repository stays in English.

## 1. Run the skills

Run `setup-tools`, `connect`, `setup-project` and `connect` again, each to its end, before starting the next. Pass on what the user already gave and what each skill resolved (the DEV url, the tenant, the repository provider and url, a publisher prefix) so it is not asked twice. The second `connect` finds the sign-ins done and only records and delegates.

- What is already in place is reported and skipped by the skill that owns it, not by you: a ready machine makes `setup-tools` short; a repository with the harness makes `setup-project` add only what is missing and propose what the templates changed since.
- A pending item in one skill — a tool the user declined, a connection that could not be made — never stops the next one. The harness only writes files. Carry it into the final report.
- If the user stops one of them, ask whether to continue with the next.

## 2. Report

One report, in this order: the machine (what changed, what is pending), the connections (confirmed, pending), the repository (written, kept, reconciled, the code created and whether it builds), and the actions left for a human — creating the publisher or the core solution, the upgrades an existing project chose to keep for later.

End with one sentence on how work starts from now on: every feature, fix or chore goes on its own branch, with its feature solution created by `dv-solution`, and the agent asks which branch before the first change. `docs/development/solutions.md` has the flow.

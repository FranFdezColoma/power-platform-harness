---
name: set-power-platform
description: "Install the Power Platform / Dynamics 365 CE harness in this folder, end to end: prepare the machine (setup-tools), write the agent instructions, development standards and per-branch feature solution workflow into the repository (setup-project), and check the connections to DEV and the repository (connect). Works on an empty folder and on an existing project, where it adapts the standards to the versions the project already uses."
disable-model-invocation: true
allowed-tools: Skill, Read, Glob, AskUserQuestion
---

# Install the Power Platform harness

Three skills of this plugin do the work, in this order. This skill only runs them and closes with one report.

1. **`setup-tools`** — the machine: CLIs, runtimes, the official skills and plugins.
2. **`setup-project`** — the repository: the harness files, adapted to an existing project.
3. **`connect`** — the connections `.power-platform/project.json` expects: DEV, the tenant, the repository, the Dataverse MCP server.

Each one can also run on its own; this skill adds nothing to what they do.

## 0. Language

Decide the conversation's language before anything else.

- If the user wrote something in this session before the skill ran, that message is the answer: use its language and do not ask.
- If the skill is the first thing in the session, ask which language to use: a closed choice (Spanish, English, French, German), through your structured question tool if you have one, else a numbered list.

Use that language for every question and report, in this skill and the three it runs. What gets written into the repository stays in English.

## 1. Run the three skills

Run `setup-tools`, then `setup-project`, then `connect`, each to its end, before starting the next. Pass on what the user already gave (a publisher prefix, an environment url, the repository provider) so it is not asked twice.

- What is already in place is reported and skipped by the skill that owns it, not by you: a ready machine makes `setup-tools` short; a repository with the harness makes `setup-project` add only what is missing.
- A pending item in one skill — a tool the user declined, a connection that could not be made — never stops the next one. The harness only writes files. Carry it into the final report.
- If the user stops one of them, ask whether to continue with the next.

## 2. Report

One report, in this order: the machine (what changed, what is pending), the repository (written, kept, reconciled), the connections (confirmed, pending), and the actions left for a human — creating the publisher or the core solution, the upgrades an existing project chose to keep for later.

End with one sentence on how work starts from now on: every feature, fix or chore goes on its own branch, with its feature solution created by `dv-solution`, and the agent asks which branch before the first change. `docs/development/solutions.md` has the flow.

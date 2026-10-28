# OpenSpec Workflow

How OpenSpec (/opsx commands) runs in this repository: what knowledge each step reads, when the
branch and the feature solution are created, and the gates. OpenSpec runs the workflow; this file
decides what knowledge each step uses.

## How to use this file
- Read it before any /opsx command.
- Each step reads at most one gate, plus the project context. The gate routes to the detail.
- A detail file may make a gate rule more specific. It MUST NOT contradict it. On a conflict,
  the gate wins and the conflict is reported.
- If a topic has no file, apply the gate alone and state the gap in the artifact.

## Knowledge library
| Part | Gate | Detail |
| --- | --- | --- |
| Project context | docs/context/project.md | docs/context/glossary.md, docs/adr/ |
| Solutioning | docs/agents/solutioning-standards.md | docs/solutioning/<topic>.md |
| Implementation | docs/agents/development-standards.md | docs/development/<tech>.md |

## What each step reads
| Step | Read |
| --- | --- |
| /opsx:explore | docs/context/project.md; docs/agents/solutioning-standards.md only when the exploration weighs how to solve something or needs the current system state |
| proposal | docs/context/project.md |
| specs | proposal.md; docs/context/glossary.md |
| design | docs/agents/solutioning-standards.md; docs/adr/ |
| tasks | docs/agents/development-standards.md |
| /opsx:apply | docs/agents/development-standards.md, then docs/development/<tag>.md for each task's tag |

- Artifact rows (proposal, specs, design, tasks) apply whichever command writes the
  artifact.
- These rules shape the content of the artifacts. The OpenSpec instructions and templates
  still decide which artifacts exist and how they are structured.
- tasks.md breaks design.md into steps and takes no design decision. In each task, after the
  checkbox and number, the text starts with a tag in brackets: the docs/development/ file it
  follows, without .md. Example: `- [ ] 1.1 [csharp-plugins] ...`. Work no file covers
  (flows, forms, views, security roles, app configuration) is tagged [low-code].
- docs/ is the knowledge library: fixed knowledge that no OpenSpec step changes. During
  /opsx:propose, /opsx:update, /opsx:explore and /opsx:apply the agent never edits AGENTS.md
  or anything under docs/, except a new ADR in docs/adr/ when a decision requires one.
  If a rule blocks the work, stop and propose the change to the user.
- Everything specific to a change (schemas, runbooks, verification notes) lives in the
  change's folder. When a standard asks for something to be documented, write it as a
  Markdown file in openspec/changes/<change>/docs/; design.md may link to it when needed.
  Progress is tracked only in the tasks.md checkboxes.
- After /opsx:archive completes, offer to update the project context as described in
  "Keeping this context current" in docs/context/project.md. Do it only if the user agrees.

## Branch and feature solution
- Before /opsx:propose writes anything, ask whether the change is a `feature`, `fix` or
  `chore`, and create the branch `<type>/<change-name>`, after checking it does not exist
  locally or on origin. The change's artifacts and approval.md live on that branch.
- Before /opsx:apply implements the first task, and after both gates are `Approved`, create
  the feature solution `<type>_<ChangeNameInPascalCase>` with `dv-solution`, unless the change
  creates or modifies no Dataverse component.
- docs/development/solutions.md holds the names, the checks and the procedure for both.

## Gates
- Functional gate after the change is planned; technical gate before /opsx:apply.
- Each change has `approval.md` in its folder: a `# Approval` heading and two lines,
  `- Functional: <status>` and `- Technical: <status>`, each on a single line.
- Status is `Pending`, `Approved by <name>, <YYYY-MM-DD>` or
  `Changes requested by <name>, <YYYY-MM-DD>: <reason>`.
- The agent creates the file with both gates `Pending` when the change's artifacts are first
  written. Only a person sets `Approved` or `Changes requested`; the agent never does.
- Functional covers proposal and specs; technical covers design and tasks. When the agent
  changes an artifact after its gate, it sets that gate back to `Pending`, and the technical
  gate too if proposal or specs changed.
- Before /opsx:apply implements the first task, pull and read approval.md. If either gate is
  not `Approved`, implement nothing and say which gate is missing.
- A change to an artifact after its gate goes through that gate again.
- How a person approves a change is in "Approving a change" in README.md.

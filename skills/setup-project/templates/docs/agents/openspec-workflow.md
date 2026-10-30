# OpenSpec Workflow

How OpenSpec (/opsx commands) runs in this repository: what knowledge each step reads, when the
branch and the feature solution are created, and the gates. OpenSpec runs the workflow; this file
decides what knowledge each step uses.

## How to use this file
- Read it before any /opsx command.
- Every step reads docs/context/project.md, plus at most one other gate. The gate routes to the
  detail.
- A detail file may make a gate rule more specific. It MUST NOT contradict it. On a conflict,
  the gate wins and the conflict is reported.
- If a topic has no file, apply the gate alone and state the gap in the artifact.

## Knowledge library
| Part | Gate | Detail |
| --- | --- | --- |
| Project context | docs/context/project.md | docs/context/glossary.md, docs/adr/ |
| Solutioning | docs/solutioning/principles.md | docs/solutioning/<topic>.md |
| Implementation | docs/agents/development-standards.md | docs/development/<tech>.md |

## What each step reads
| Step | Read |
| --- | --- |
| /opsx:explore | docs/solutioning/principles.md only when the exploration weighs how to solve something or needs the current system state |
| proposal | — |
| specs | docs/context/glossary.md |
| design | docs/solutioning/principles.md; docs/adr/ |
| tasks | docs/agents/development-standards.md |
| /opsx:apply | docs/agents/development-standards.md |
| /opsx:archive | "After /opsx:archive" below; docs/context/project.md, docs/context/glossary.md |

- Artifact rows (proposal, specs, design, tasks) apply whichever command writes the
  artifact.
- These rules shape the content of the artifacts. The OpenSpec instructions and templates
  still decide which artifacts exist and how they are structured.
- Every change has a design.md, whatever its size and whether it is configuration or code,
  even where the OpenSpec instruction calls it optional: it is where the solution is decided
  and what the technical gate reviews.
- tasks.md breaks design.md into steps and takes no design decision. In each task, after the
  checkbox and number, the text starts with a tag in brackets. When a docs/development/ file
  covers the work, the tag is that file without .md: `- [ ] 1.1 [csharp-plugins] ...`.
  Otherwise the tag is a short kebab-case name for the kind of component the task builds,
  chosen by the agent (for example [cloud-flow], [model-driven-form], [security-role]); there
  is no closed list. Use the same tag for the same kind of component across the change.
- docs/ is the knowledge library: fixed knowledge that no OpenSpec step changes. During
  /opsx:propose, /opsx:update, /opsx:explore and /opsx:apply the agent never edits AGENTS.md
  or anything under docs/. Only "After /opsx:archive" below writes there.
  If a rule blocks the work, stop and propose the change to the user.
- Everything specific to a change (schemas, runbooks, verification notes) lives in the
  change's folder. When a standard asks for something to be documented, write it as a
  Markdown file in openspec/changes/<change>/docs/; design.md may link to it when needed.
  Progress is tracked only in the tasks.md checkboxes.
- The change's ADRs are written in openspec/changes/<change>/docs/adr/, format and naming in
  docs/adr/0000-template.md. They are part of the technical gate and reach docs/adr/ only at
  archive.

## Branch and feature solution
/opsx:propose creates the branch before writing anything; /opsx:apply creates the feature
solution after both gates are `Approved`, before the first task. Follow "An OpenSpec change" in
docs/development/solutions.md: it holds the names, the checks and the procedure for both.

## Gates
- Functional gate after the change is planned; technical gate before /opsx:apply.
- Each change has `approval.md` in its folder: a `# Approval` heading and two lines,
  `- Functional: <status>` and `- Technical: <status>`, each on a single line.
- Status is `Pending`, `Approved by <name>, <YYYY-MM-DD>, at <commit>` or
  `Changes requested by <name>, <YYYY-MM-DD>: <reason>`. `<commit>` is the short hash of the
  commit the person reviewed: what they approved is the artifacts as they are in that commit.
- The agent creates the file with both gates `Pending` when the change's artifacts are first
  written. Only a person sets `Approved` or `Changes requested`; the agent never does.
- Functional covers proposal.md and specs/; technical covers design.md, tasks.md and docs/,
  and depends on the functional artifacts too. When the agent changes an artifact after its
  gate, it sets that gate back to `Pending`, and the technical gate too if proposal or specs
  changed.
- Before /opsx:apply implements the first task, pull and read approval.md, then check each
  gate in the change's folder:
  - Functional: `git diff --quiet <commit> HEAD -- proposal.md specs`
  - Technical: `git diff --quiet <commit> HEAD -- proposal.md specs design.md tasks.md docs`

  A gate is approved only when its line is `Approved … at <commit>`, the commit exists
  (`git cat-file -e <commit>`) and the diff is empty. Otherwise implement nothing and say
  which gate is missing; for a stale approval, list the files changed since that commit. If
  both are approved, set the change's ADRs from Proposed to Accepted, with today's date, and
  commit that before the first task.
- How a person approves a change is in "Approving a change" in README.md.

## After /opsx:archive
OpenSpec syncs product behaviour into openspec/specs/. Once it has, bring the knowledge
library up to date with what the change decided, then commit with
`Archive <change>: update project context`.

1. **ADRs.** Move each ADR from the archived change's docs/adr/ to docs/adr/, unchanged. When
   one supersedes an Accepted ADR, set that ADR's status to `Superseded by ADR-<change>-NN`.
   They were approved with the change: list what moved, without asking.
2. **Glossary.** Read the change's delta specs. Add one row to docs/context/glossary.md for
   each business term they use that a new team member would need defined and the glossary
   lacks; Source is `openspec/specs/<capability>/spec.md`. Edit the row of a term whose
   meaning the change altered; remove the row of a term no spec uses any more. Write in the
   artifact language. Never add Dataverse names, technical terms or everyday words.
3. **Project facts.** In docs/context/project.md, edit only the Identity, Scope boundaries or
   Constraints the change altered (a new integration, a licensing constraint, a scope that
   moved) or a TBD the change resolved. Edit the current state in place.
4. **Never** write behaviour (it lives in openspec/specs/), tasks, implementation notes, bug
   fixes, or a log or summary of the change.

Show steps 2 and 3 as one diff and apply what the user accepts. If nothing qualifies, write
nothing and say so.

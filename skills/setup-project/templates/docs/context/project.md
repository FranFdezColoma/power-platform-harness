# Project

Project facts for the OpenSpec steps. One line per fact. Unknown values are TBD, never guessed. No URLs, ids or credentials.

The project name, publisher, prefix, core solution and DEV environment are in `.power-platform/project.json`; the artifact language is in `openspec/config.yaml`. They are not repeated here.

## Identity
- Client: TBD
- Product: {{project_description}}

## Scope boundaries
- In scope: TBD
- Out of scope: TBD

## Constraints
- TBD

## Keeping this context current
After a change is archived, and only if the user agrees, update the project context when the
change alters one of these:
- A project-wide decision: a new ADR in docs/adr/.
- A new business term: one line in docs/context/glossary.md.
- A fact in this file.
- Product behaviour goes nowhere here: OpenSpec syncs it into openspec/specs/.

Edit the current state in place; never append a log or change summary. No task lists,
implementation notes, bug fixes or anything without lasting impact. If nothing qualifies,
write nothing and say so.

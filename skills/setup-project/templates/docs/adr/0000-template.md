# ADR-<change>-NN. Title of the decision

Name the file `ADR-<change>-NN-short-title.md`: `<change>` is the OpenSpec change name, or the
branch's short description for work outside OpenSpec, and NN counts from 01 within it. The name
never changes. One decision per file.

Where it lives: in an OpenSpec change, in `openspec/changes/<change>/docs/adr/` until the change
is archived, then in `docs/adr/` ("After /opsx:archive" in docs/agents/openspec-workflow.md).
Outside OpenSpec, in `docs/adr/` from the start.

The agent writes an ADR as Proposed. In an OpenSpec change it becomes Accepted when both gates
are approved ("Gates" in docs/agents/openspec-workflow.md); outside one, when the user confirms
the decision. While Proposed it may be edited; once Accepted, only its status changes, and a
decision that replaces it is a new ADR that names it under Supersedes.

- Status: Proposed | Accepted | Superseded by ADR-<change>-NN
- Date: YYYY-MM-DD, the day it became Accepted
- Change: the OpenSpec change, or the branch outside OpenSpec
- Supersedes: ADR-<change>-NN | —
- Requirements: the spec requirements it serves, as `<capability>: <requirement>` | —

## Context
What forces the decision: the current state in DEV, platform limits, licensing, volume,
integrations. Facts with their source, not opinions.

## Decision
What was decided, in one or two sentences.

## Alternatives considered
- Alternative: why it was rejected, in one line. Include the lower rung of the ladder, or the
  standard table, that was considered.

## Consequences
- Positive: what becomes easier.
- Negative: what becomes harder, and the risks accepted.
- Follow-up: what must now be done.

## Revisit when
The condition that would reopen the decision (a volume threshold, a capability becoming
generally available, a licensing change), or `—`.

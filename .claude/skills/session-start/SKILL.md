---
name: session-start
description: Open a Whiteout build session — load project state, verify the build is green, and report which tasks are ready to work. Run this before any other work in a new session.
---

# Session Start

You are opening a session on Whiteout, a multi-session iOS game build. Do not begin any
work until this completes.

## 1. Load state

Read in this order. Do not skip — each answers a question the next depends on:

1. `docs/STATE.md` — the only file that knows what happened last session.
2. `docs/ROADMAP.md` — the task queue, milestones, and dependencies.
3. `docs/DECISIONS.md` — skim for ADRs touching today's area.

`CLAUDE.md` is already in context. Re-read the Invariants section if today's work touches
`Core/`, purchases, or the simulation.

## 2. Verify green before touching anything

```bash
./scripts/verify.sh
```

Confirm green **before** changing code. Inheriting a red suite and discovering it an hour
in wastes the session and makes it impossible to tell whose breakage it was.

If it comes back red, that is the session's first task. Say so plainly and fix it before
starting anything planned.

## 3. Check for drift

Compare `docs/STATE.md` against reality:

```bash
git log --oneline -5
git status --short
```

If the working tree is dirty or the last commit does not match what STATE.md claims, the
previous session did not close cleanly. Reconcile before proceeding, and note it.

## 4. Pick the work

From `ROADMAP.md`, find tasks whose `deps` are all `done`. Prefer the lowest unblocked ID
in the earliest incomplete milestone unless the user directs otherwise.

Scope to **one coherent deliverable**. If describing the goal needs the word "and", it is
two sessions.

## 5. Report and begin

Tell the user, briefly:

- Where the project stands (one line from STATE.md)
- Whether verification is green
- The task you are taking and why it is next
- What "done" looks like for it

Then start. Do not ask for permission to begin work that is already sequenced in the
roadmap — autonomy is high, per `CLAUDE.md`.

## Notes

- Mark the task `doing` in `ROADMAP.md` as you start it.
- Record decisions in `docs/DECISIONS.md` as you make them, not at the end. The reasoning
  is perishable.
- Aim to close at roughly 50–60% context. Handoff is cheap; a half-finished task is not.

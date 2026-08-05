---
name: session-end
description: Close a Whiteout build session — run the verification gate, update project state files, commit and push, then produce the recap and the handoff prompt for the next session. Run this before ending any build session.
---

# Session End

Closing a session. The goal is that the next session, with zero memory of this one, can
pick up from the repository alone.

## 1. The gate — this blocks everything else

```bash
./scripts/verify.sh
```

**A red result blocks the close.** Fix it, or revert to the last green commit. Never hand
off a broken suite: the next session cannot tell inherited breakage from its own, and will
burn its budget finding out.

If a task is genuinely half-finished, that is fine — but it must be *green* and
half-finished, not broken. Stub or revert the incomplete part.

## 2. Update `docs/STATE.md`

**Rewrite it, do not append.** It describes *now*, not history. Keep it under a page. It
must answer, for someone with no context:

- What was just completed, concretely
- What is in progress and how far along
- What is verified working versus written but untested (be honest — claiming untested work
  is verified poisons every session that trusts the log)
- Anything surprising: a bug found by running rather than reasoning, a wrong assumption, a
  constraint discovered
- The immediate next task and why

## 3. Update `docs/ROADMAP.md`

Mark completed tasks `done`. Mark in-progress ones `doing`. **Add tasks discovered during
the work** — a session that finds three new problems and records none of them has lost
most of its value.

## 4. Append `docs/DECISIONS.md`

Any notable decision not yet recorded. Include what was **rejected** and why — that is the
part that stops the question being reopened. Never edit an existing ADR; supersede it.

## 5. Write the session log

Create `docs/sessions/NNNN-slug.md`, zero-padded, next in sequence. **Append-only — never
edited later.** This is the archaeology layer, deliberately outside the hot path so it
never bloats context. Include what was built, what broke, what was learned.

## 6. Commit and push

```bash
git add -A
git commit -m "<type>: <summary>"
git push
```

Conventional commit types: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`, `perf`, `ci`.

If pushing to a public remote and the UI changed materially, refresh the README screenshots
from a real running build first — real data, real captures, numbered captions.

## 7. Recap for the user

Short. Bullet points. Two sections:

**Done this session** — concrete outcomes, not activity.
**Left to do** — the next few unblocked tasks.

Flag anything unverifiable (haptics cannot be tested in the simulator) and anything you are
uncertain about. This is for the user, not the next session — the next session reads files.

## 8. The handoff prompt

Print it in a copyable code block. Keep it **thin** — it points into the repo rather than
restating it, because the files are the memory (ADR-015):

```
Continue building Whiteout at /Users/rayankarimcheca/Desktop/Dev/ski

Run /session-start first — it loads state and verifies the build.

Last session: <one line of what shipped>.
Next task: <T-ID> — <title>.
<Any single caveat the files cannot convey, or omit this line.>
```

If that prompt needs to grow past a short paragraph to be usable, the state files are not
doing their job. Fix the files, not the prompt.

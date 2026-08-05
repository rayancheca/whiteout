# Session Protocol

How a Whiteout session opens, runs, and closes. `/session-start` and `/session-end`
execute this; the prose here is the reference and the rationale.

## Why sessions work this way

A long build hits a hard limit: context degrades before it runs out. Auto-compaction
summarizes, and summaries drop exactly what matters later — precise file paths, tuning
constants, and the reasoning behind a *rejected* approach. A fresh session reading
structured files starts sharper than a compacted session at 800k tokens.

So the repository is the memory. Not the handoff prompt.

That inversion is the whole design. A pasted prompt is fragile, unversioned, and grows
without bound; if session 40's handoff was wrong you cannot diff it. Files are versioned,
diffable, and read automatically. The handoff prompt is therefore deliberately thin — a
pointer into the repo, not a transfer of state.

## Opening a session

1. Read `docs/STATE.md`. It is the only file that knows what happened last session.
2. Read `docs/ROADMAP.md` for the task queue, and check which tasks are unblocked.
3. Skim `docs/DECISIONS.md` for anything touching today's area. This is what prevents
   session 47 from quietly undoing session 12.
4. Run `./scripts/verify.sh`. Confirm green *before* changing anything — inheriting a
   red suite and discovering it an hour later wastes the session.
5. State the session goal in one sentence. One coherent deliverable, not three.

## During a session

- Work the task queue in dependency order. Prefer finishing one task to starting three.
- Record notable decisions as ADRs in `docs/DECISIONS.md` **as you make them**, not at the
  end. The reasoning is perishable.
- Write tests alongside the code. The suite is the durable handoff, more than any prose.
- When a bug is found by running the app rather than by reasoning, note that in the ADR.
  Which bugs were only findable by execution is genuinely useful signal for later sessions.

## Stopping

**Stop at roughly 50–60% context, not at the limit.** The final 40% is where quality drops
and where a half-finished mess is most likely to be left behind. Handoff is cheap by
design, so stopping early costs almost nothing. Stopping late can cost a whole session.

Also stop early if the remaining work does not fit cleanly — better to hand off a clean
boundary than to leave a task 70% done with the reasoning trapped in a dead context.

## Closing a session

`/session-end` performs, in order:

1. `./scripts/verify.sh` — tests and iOS build. **A red suite blocks the close.** Fix it or
   revert to green; never hand off broken.
2. Update `docs/STATE.md` — rewritten, not appended. It describes *now*.
3. Update `docs/ROADMAP.md` — mark completed tasks, add discovered ones.
4. Append `docs/DECISIONS.md` if any ADRs are outstanding.
5. Write `docs/sessions/NNNN-slug.md` — append-only, never edited later. This is the
   archaeology layer, kept out of the hot path so it never bloats context.
6. Commit and push.
7. Print the recap and the handoff prompt.

## The recap

Short. Bullet points. What got done, what is left. This is for the user, not for the next
session — the next session reads the files.

## The handoff prompt

Deliberately about ten lines. It points into the repo rather than restating it:

```
Continue building Whiteout at /Users/rayankarimcheca/Desktop/Dev/ski

Read docs/STATE.md, then docs/ROADMAP.md, then CLAUDE.md.
Last session: <one line>.
Next task: <T-ID> — <title>.
Verify green with ./scripts/verify.sh before starting.
```

If that prompt ever needs to grow beyond a short paragraph to be usable, the state files
are not doing their job — fix the files, not the prompt.

## Session sizing

One milestone-sized deliverable per session. Signs a session is scoped wrong:

- **Too big:** the goal needs "and" to describe. Split it.
- **Too small:** it finishes in under an hour with most of the context unused. Pull the
  next unblocked task forward.

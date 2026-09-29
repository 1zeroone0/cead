---
name: scope
description: Clarify a PR, a Horizon comment, or a loose idea into decisions and a PR description before any code. Use for "/scope 8", "/scope rlm", "let's scope", "think through", "grill me", "what are we building".
---

# scope

Work is scoped before it is built. The output is decisions, written into the
record that carries them: a PR description, or a Horizon comment. No issues,
no prose spec; the skeleton commit that follows is the spec of custody.

## Target

Resolve the argument before the first question:

- **A number** (`/scope 8`): that PR. If it is the Horizon PR, the words
  after the number name a comment (`/scope 7 rlm`).
- **Words** (`/scope rlm`): the Horizon comment whose title matches them,
  loosely. Two matches: ask which.
- **Nothing, or a loose idea**: no target yet. Check Horizon for a comment
  that already covers it before making a new one.

The Horizon PR is the repo's parking lot: never merged, one comment per
future PR in the description template. The repo's AGENTS.md names its
number; otherwise it is the open draft titled "Horizon".

## Read first

Read the target in full (PR description and comments, or the Horizon
comment), then the repo's AGENTS.md and CODE.md. Questions start from what
is already written; anything the conversation settles differently from the
text gets named.

## Rounds

Scoping is a conversation, not a step toward automation. The questions are
where what cannot be stabilized becomes visible; asking beats assuming, and
each question gives its context from first principles.

1. Name the destination first: what done looks like, in one or two lines.
   It fixes scope; every question serves it.
2. Work in rounds. A round is every question askable now without guessing
   at an unheard answer. Number each, give one recommended answer, wait.
3. Facts are yours to fetch; decisions are the user's. Look it up before
   asking. Never answer your own question.
4. Where's best, not least disruptive. When a proposal conflicts with what's
   on disk or in the record, say so and say which should win. Conversation
   outranks disk.
5. Nouns go into CODE.md's vocabulary as they settle, one line each. Call
   out a noun the moment its meaning drifts.
6. Stop when the frontier is empty.

## Write back

Restate what settled, then write it into the target in the repo's
description template: **What this PR does**, **What this PR does not do**,
**Merge requirements**.

- **A PR**: rewrite its description.
- **A Horizon comment**: edit it in place. If it is ready to build, say so;
  on the user's go, open its PR (branch, worktree, first commit, draft) with
  the comment as its description, then delete the comment.
- **No target**: a new Horizon comment, or a new draft PR if the user says
  it is next.

Scoping ends at a clarified description. Stubs and code are the next step.

Question format:

```
❓ **Q1** - **title**: body, with choices if there are any

➡️ recommended answer
```

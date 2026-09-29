---
name: slice
description: Scope a cead PR or Horizon comment into its slice of the spec and a PR description, before any spec, Lean or Rust. Use for "/slice 13", "/slice agent", "scope this PR", "what's this PR's slice".
---

# slice

A cead PR takes a slice of the spec (CODE.md, Method). This skill settles
that slice: decisions written into the PR description, before the spec
commit, the Lean, the skeleton or any code.

Slicing is a conversation, not a step toward automation. The questions are
where what cannot be stabilized becomes visible; asking beats assuming, and
each question gives its context from first principles.

## Target

- **A number** (`/slice 13`): that PR. `/slice 7 WORDS`: the Horizon comment
  whose title matches.
- **Words** (`/slice agent`): the Horizon comment whose title matches them,
  loosely. Two matches: ask which.
- **Nothing**: ask what the work is; check Horizon (#7) for a comment that
  covers it before making a new one.

## Read first

The target in full (description and comments), AGENTS.md, CODE.md, and the
parts of `spec/cead.tla` and `spec/Cead/` the target touches. Questions
start from what is written; anything the conversation settles differently
gets named.

## Rounds

1. Name the destination in one or two lines, and the slice: the spec's
   actions and properties this PR makes real.
2. Work in rounds. A round is every question askable now without guessing
   at an unheard answer. Number each, give one recommendation, frame it as
   a commitment ("approving this means..."), wait.
3. Facts are yours to fetch; decisions are Roone's. Look it up before asking.
4. Every round covers what applies:
   - **Spec:** does the slice change what `spec/cead.tla` says? Then that
     change is the PR's first commit. The spec is never looser than the
     system.
   - **Lean:** which pure functions must a skeptic trust (what signs,
     verifies, admits or renders)? Each gets a Lean spec and a
     differential test.
   - **Shape:** modules, types and custody, agreed before the skeleton.
   - **Nouns:** each settles into CODE.md's table with its type's home.
     Terms come from OSTEP or object-capability security; flag a noun the
     moment it drifts.
   - **Thesis:** does the design keep context offloaded to state and
     sub-calls programmatic, every model call locally in distribution?
   - **Dependencies:** one crate at a time, standard and mainline only.
   - **Structure:** crates, binaries, files only when a requirement
     demands them.
5. Where's best, not least disruptive. When a proposal conflicts with the
   record, say which should win. Conversation outranks disk; evidence
   outranks both.
6. Stop when the frontier is empty.

## Write back

Restate what settled, then write it into the target: a `Spec:` line naming
the slice, then **What this PR does**, **What this PR does not do**,
**Merge requirements**.

- **A PR**: rewrite its description.
- **A Horizon comment**: edit it in place. On Roone's go, open its PR
  (branch named for the change, worktree, first commit, draft) with the
  comment as its description, then delete the comment.

Slicing ends at a clarified description. The spec commit, Lean, skeleton and
fill follow, each shown before it is built.

```
❓ **Q1** - **title**: body, with choices if there are any

➡️ recommended answer
```

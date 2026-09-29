# ROLES
You build; I direct, review, approve, and answer for everything that ships.
Public artifacts — commits, code, docs, descriptions — carry "Roone" only, never my last name.

# CONTEXT
Read these root-level files: `README.md` (what this is), `CODE.md` (method, vocabulary, languages).
Every time you create or discover a new AGENTS.md, paste its path here:

# COMMUNICATION
The shape of your responses and documentation is the lowest number of tokens with the strongest overall signal.
Prioritize easy human readability over grammar.
Write for an intelligent cold reader: the shortest form of plain words that preserves precision, evidence, constraints, tradeoffs and uncertainty.
State only what can't be reconstructed from the code in under 10 seconds.

# EXPECTATIONS
My requests are APPROXIMATE pointers toward what I actually want: the simplest, cleanest, most elegant design for a real system that can disagree with us.
That goal ALWAYS outranks my literal words, and you own getting us there.

Code is the primary documentation surface; you are its steward.
Every addition carries maintenance and trust cost: default to omission, delete when behavior is preserved, merge duplicates, and let an existing artifact absorb new work before adding one.
Measure complexity by branch count, not lines; reduce it with better abstractions, never by minifying or code golfing.
Label uncertainty as uncertainty; volunteer absences; find problems and opportunities, don't grade.
Prefer end-to-end tests; they prove the system works. Each ends in an artifact another person can check and re-run from the same initial state. Smaller tests only where an end-to-end test cannot reach an edge cheaply.

When you hit a wall — a case that doesn't fit, a spec that breaks, an assumption that fails — the wall is information: the design is wrong somewhere. Stop the invalid path, re-derive the design from first principles until the wall doesn't exist, and return control only when meaning, evidence or authority must change.
NEVER patch around a wall to comply with my words — no flags, special cases, shims, parallel paths, or tests rewritten to dodge a broken rule.
Building around a blocker is failure and will always be rejected, sunk cost irrelevant.
A blocker honestly reported is a desired outcome; a "working" deliverable built on duct tape is sabotage.
Evidence outranks every artifact: when code or a measurement disagrees with a spec, doc or decision, change it in that PR; never defend it.

# GITHUB
Pull Requests (PRs) are the units of work; only ever create PRs. No issues: the PR is the only record.

For new work, create a draft PR from the first commit, on a branch and worktree specific to that PR. One writer per branch; both are deleted upon merge.
Branches: short kebab-case, naming the change, not the thing changed — `initial-spec`, never `spec` or `feature/…`.
Commits: one imperative line; the diff is the what, the message is the why.

Every PR description has these sections, kept current:
1. **What this PR does** — planned scope; think like a Product Manager
2. **What this PR does not do** — out of scope; think like a Product Manager
3. **Merge requirements** — definition of done; think like a Software Engineer

PR descriptions become the squash-commit body, so write them as records of truth with links to related PRs (#PR).
Squash trades bisect granularity for readable history: the unsquashed commits stay at `refs/pull/N/head`, and `gh land` keeps the comment thread as a note in `refs/notes/pr` (fetch `+refs/notes/*:refs/notes/*`).
A leaning lives in the description of the PR that will settle it. Once code settles it, the why is a doc comment. No third document.
Only #7 (Horizon) and PRs in progress are open. Until its PR exists, a leaning is a comment on #7, in the description template; scope it there, and when it is ready, open its PR and delete the comment.

When a PR changes what the spec says, its first commit is that change, TLC green, before any code.
The next commit is typed stubs ONLY: types and signatures, placeholder bodies, the language's type gate green. The diff defines that PR's scope; one signature per action of the spec. `CODE.md` names each language's stub and gate.
Subsequent commits fill those stubs.
**Zero placeholders may remain at merge. This is always a hard requirement.** `CODE.md` names what counts as a placeholder and the lints that count them.

For every subsequent commit, add a comment to the PR briefly describing:
1. **Built** — architecture, flow.
2. **Why** — key decisions, tradeoffs, what you rejected.
3. **How you avoided bloat** — every existing piece of code you removed, consolidated or simplified.
4. **How you avoided drift** — every existing document you removed, consolidated or updated.
5. **Trust surface** — what's tested, what tests actually PROVE, what is NOT covered, sharp edges (concurrency, time, failure, security).
6. **How it breaks** — be adversarial about your own work.
7. **Where you are not confident** — every choice you made that you're not confident in.
8. **Verify yourself** — the 2–3 places most worth my direct attention before merging.
9. **Next steps** — choose one of these three: additional commits (briefly describe), blocked (explain what is needed), or finished (all merge requirements met, PR is ready for review)

Before marking a PR ready, fold what is durable from its comments (decisions, measurements, limitations) into the description: the description is the record, the comments its receipts.

You may freely commit and push to PR branches via their worktrees.
I own ALL reviews and merges, with `gh land` (squash, delete the branch, evict the worktree), never by hand. `main` is protected.
We may stack PRs at times; that is an explicit, communicated decision.

Run git plain-form — cd first, never `git -C` or `cd &&` chains — so permission prefixes match.

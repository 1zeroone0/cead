# prs

## Next session

Read AGENTS.md, README.md and CODE.md first; this file is the queue.

Before any cead work, one piece of housekeeping outside this repo. Rename
the `~/dev` commons to `rr`, on disk and on GitHub (`1zeroone0/dev`,
private). Steps, in order: land any open cead PR so no worktree holds a
path into `~/dev`; `mv ~/dev ~/rr`; `gh repo rename rr`; set the remote
URL; fix the `land` alias in `~/.config/gh/config.yml`, which points at
`~/dev/bin/land`; confirm cead's remote and worktrees still resolve from
`~/rr/cead`. Then reshape what `rr` tracks: in are AGENTS.md (cead's is
the current template), rust.md, keybinds.md, `bin/`, `skills/`; out are
`career/` (leave git entirely), `linux-codebase-map/` (its own repo, the
cead move), stray root notes (to the project they concern, or deleted),
and the allowlist `.gitignore` (replace with a normal one). Do the
rename as one commit on `rr`'s main, the reshape as a PR there. The
operator lands both.

Then cead: draft PRs from the sections below, §1 first, one worktree
each. Each PR's description absorbs its section, and the section is
deleted here in that PR. Delete this file in the PR that empties it.

Transitory. Each section becomes a draft PR's description, then is deleted
here. Delete the file when empty. Sections are in build order. Items are
leanings with their reasoning; "(checked)" means read against source on
2026-09-20, re-verify before relying on it. What the README decides is not
repeated.

## 1. loop: Firecracker boot, one process, `done`

Scope: image-to-rootfs converter; Firecracker boot plus vsock; the harness
cycle with brush, bounded output, the log as a flat file; `done` returning
the diff; a predictions writer feeding the official SWE-bench harness.
Correct but incomplete: the flat file becomes a Merkle log later without
changing meaning; one machine becomes a tree without changing the cycle.

Held here, not in the README: one SWE-bench-class task crosswalked, the
official harness grading on the host. Not a leaderboard; landing near the
published number validates the pipeline, a delta is the finding. Five
numbers from the first run: cold boot to first command; rootfs and snapshot
size; memory per idle process; harness time per step; cost per resolved
task, inference against everything else. Out until the run demands it:
`rlm`, a tamper-evident log, policy beyond permit-all, containers inside
the guest, a TLA+ or Lean model, Kubernetes.

Crosswalk of one SWE-bench Verified instance:

| Benchmark piece | cead piece |
|---|---|
| per-instance Docker image (300-500 MB, deps preinstalled) | task image; no network needed |
| repo at base commit (`/testbed`) | checkout descriptor, already in the image |
| issue text (long) | context on stdin; the argv query stays commit-sized |
| model patch | `done` emits `git diff`; `cead run` stdout is the prediction |
| hidden tests plus official harness | grader on the host; the test patch never enters the guest |

Shape: `cead run "Fix the issue on stdin; repo is in /testbed" < issue.md > patch.diff`

- Baseline: a bash-only scaffold (mini-SWE-agent, SWE-bench's bash-only
  leaderboard; verify current numbers), not DeepSWE's four-tool scaffold.
  DeepSWE (R2E-Gym) runs 64k context, 100 max steps, Pass@1 over 16 runs.
- Pick 10-20 instances a bash-only baseline already solves with the same
  model, so a failure points at cead. The benchmark is noisy: one 2026 audit
  found 28.5% of a 49-task sample accepted an incorrect patch.
- The part of the thesis under most stress here is truncation: pytest output
  is long. This tests whether spill plus head/grep is enough.
- For comparability consider mirroring the baseline's step and context
  budget. That is one eval setting, not a mechanism.
- Images are x86_64: Linux x86 host first.

CLI contract, mirrored by `rlm`: argv is a commit-style query; stdin is
optional context; stdout is the answer only; stderr is diagnostics; exit code
is the outcome, with distinct codes for done, budget exhausted, timeout,
policy denied. The argument is the commit message; stdin or a file in state
is the diff. Long instructions are context and belong where context lives.
No chat interface: each run starts a fresh window over whatever the state
now is. Continuity is carried by state, not conversation.

`cead` with no verb opens the operator shell over a declaration and its
state; `run` inside it is the same verb. Each step renders as its receipt
on the TTY: the model's prompt line and command, then `exit 0 · 212 bytes`
on permit or `forbid · no network in this process · exit 77` (sysexits
EX_NOPERM) on forbid. Plain lines, no ratatui. One-shot `cead run` prints
the same on stderr when stderr is a TTY.

Operator verbs, git-shaped so coding agents driving the CLI stay in
distribution: `boot mount run log diff fork export evict`. Only `run` for v0.
Avoid thin passthrough wrappers (`cead git ...`); wrap only where cead adds
state-awareness (mount, snapshot, fork, export).

Typed sketch, directional, names not settled:

```rust
struct Ctx<S>(OwnedFd, PhantomData<S>);  // Unsealed -> Sealed (memfd seals)
struct Budget { tokens: u64, depth: u8 } // not Clone; moves into children
impl Budget { fn split(self, n: usize) -> Vec<Budget> }
struct Bounded(Vec<u8>);                 // only constructible via truncation
impl Window { fn push(&mut self, b: Bounded) }
#[must_use] struct Evicted(/* must be written to the log */);
```

Budget is a mechanism. What it counts (tokens, steps, depth), the numbers,
and whether there are any differ between agentic use, eval and RL, and are
declaration policy. Not decided; decide when the first run needs a number.

Tool output behaves like `read()`: bounded, short reads, remainder spilled
to a file the model can seek into. Open: byte- vs line-oriented defaults
for contexts without newlines.

System prompt: size cap roughly 300-600 bytes, fails at boot. Per-step values
(budget left, depth) go in the shell prompt string: `[depth 1/3 · 142k left] $`.
Example shape:

```
You have a shell. Context is outside your window; read it with tools.
$CTX      read-only input, 2.1 MB
/work     scratch, persists across steps
/repo     git checkout @ a41f9c2
/db.sqlite sqlite3; schema in /work/SCHEMA
rlm       run a sub-agent on stdin
done < f  finish with f as your answer
Output over 4 KB is truncated; use head/grep.
```

The prompt names sets, not commands. Open: exact cap; what else earns a
place in the shell prompt. Leaning, unvalidated: nothing about cead should
need teaching; unknown commands return a hint toward the sanctioned
equivalent. The measurements for it are invalid-command rate and doc opens
per run.

Child process: a fresh binary inherits the sealed memfd as stdin (not
SCM_RIGHTS); own cgroup; own scratch only, anything from the parent arrives
on stdin; child stdout is its answer so `rlm` composes like any tool.
Recursion and forking are one operation with different parameters: recursion
hands a child a narrower slice and joins; forking hands a sibling the same
state and lets it diverge.

Snapshot and log roles for RL, evals, sandboxing: snapshot (Firecracker) is
the forking mechanism; the log is training data and audit (exact sampled
tokens, logprobs where available, observations); replay-from-log is a
debugging nicety; evals need a reproducible initial state, not a reproducible
run, variance across re-rolls is signal. Reward integrity: grader, log and
observer live outside the guest from the first run.

Three habits from the first run so the inference-control work later is not
precluded: keep window assembly deterministic and prefix-stable; log exact
tokens (and logprobs where available), not just text; record the model and
weights version in the log.

Facts (checked): aarch64 and riscv64 Linux have no `pipe` syscall; rustix's
linux_raw backend uses `pipe2` (rustix v1.1.5,
`src/backend/linux_raw/pipe/syscalls.rs`). `pipe2` entered POSIX.1-2024;
rustix compiles `pipe_with` out on Apple targets. rustix does not cover
seccomp, landlock or bpf: use seccompiler, landlock, aya. In a micro-VM we
are init and choose the kernel, so no systemd cgroup delegation.
POSIX.1-2024: https://pubs.opengroup.org/onlinepubs/9799919799/

## 2. observer: aya, traces before policy

You need to see behaviour to know what policy to write, so traces come
before enforcement.

- Span tracking via read tracing, not page faults: memfd pages are resident,
  fault-around is coarse, and head/sed/grep use read(), not mmap. Trace
  read/pread with fd, offset, length, keyed by cgroup.
- Key on cgroup only. Never on Postgres process structure (pgrust is
  thread-per-connection; stock Postgres is process-per-connection).
- Tracepoints are fairly steady; kprobes on function names are not; BTF and
  CO-RE soften struct-layout drift (verify). Acceptable because the guest
  kernel is pinned. Upgrading the guest kernel: tools fine, observer needs
  re-validation. Open: tracepoints only, trading coverage for stability.
- Prefer syscalls over pseudo-filesystems where a choice exists (pidfd over
  parsing /proc).
- Record the guest kernel version and the seccomp filter hash in the log
  next to the prompt hash, so a run names the exact contract surface it
  ran on.
- Every doc the model opens is seen. Repeated reads of the same page are a
  measured signal that the prompt is missing a line.
- For interpreters the record shifts from execve level to syscall level
  (opens, reads, forks). Nothing is lost; granularity moves. Record whether
  executed code came from the model or from state (the repo).
- Measure: observer CPU and per-syscall overhead, probes on vs off.

## 3. shell and calls: brush, uutils, `rlm`, man pages

brush is the language, uutils is the tools; brush has no `head` of its own.
Leaning: embed brush over hand-rolling a parser. brush (checked at
reubeno/brush @ 6bada55):

- builtins implement `Command: clap::Parser`, so a builtin is a typed struct;
  `register_builtin` exists; an `ErrorFormatter` extension trait controls
  how errors render.
- `brush-coreutils-builtins` (feature `experimental-bundled-coreutils`)
  bundles uutils with per-utility feature flags and dispatches by re-entering
  the binary as an external process, so pipeline stages stay real processes
  and execve tracing works.
- No pre-dispatch command interception hook was found; command restriction
  comes from PATH contents plus landlock.
- brush uses the `nix` crate plus std and some libc, not rustix; rustix is
  only transitive. Two binding crates over one contract.

Gaps: grep, sed, awk, xargs are not coreutils. xargs and find are in
uutils/findutils (check `-P` before relying on it for fan-out; open whether
harness-native fan-out is better). The uutils org reportedly has a separate
grep effort. For any port, GNU test-suite pass rate is the thing to check:
flag and error-message fidelity is the reason to use them. Open: how much
of brush's surface to disable; whether real git belongs in the default
guest or only when the task needs it.

The `rlm` child cost: a child that reads its slice and calls `done` without
running a command pays for a process, a cgroup, a shell and a rendered
prompt. If that is measured to matter, the harness serves such a child
cheaply, invisibly. An optimization is not a verb.

Docs as state, three tiers, all in-distribution: pinned prompt (one line per
call); `rlm --help`; `man rlm` (full contract, read when unsure). `man 7 cead`
for the world itself: what `$CTX` is, what `/work` is for, how truncation
behaves. Generate pages from the call table with `clap_mangen` (verify it
fits brush's builtin shape). Conventional sections: EXAMPLES, EXIT STATUS,
ENVIRONMENT (`RLM_DEPTH`, `RLM_BUDGET`, `RLM_MODEL`). Descriptors document
themselves the same way: mounting drops a page at a known path and the
prompt line points there (the SQLite schema note first). man-db plus groff is
heavy; ship pre-rendered text behind a tiny `man`. Pages pass through the
bound, so keep them short.

Task tools never shadow core on PATH; note any task where that bites.

## 4. policy: exec allowlist, seccomp, Cedar as candidate notation

- Seccomp cannot be the call set: it filters syscall numbers and raw
  register values and cannot read the path behind execve. The call set is an
  exec policy: a rootfs with only sanctioned binaries plus landlock execute
  rights. Seccomp covers the syscall surface those tools need. Both render
  from the call table; two artifacts.
- Seccomp default for unknown syscalls: ENOSYS, not kill and not EPERM. libc
  treats ENOSYS as "fall back to the older call", which keeps task images
  working as they age (the clone3 container breakage is the known case;
  verify before citing). Explicitly dangerous calls still denied hard.
  Syscall numbers differ per architecture, so generate per target.
- The allowlist is derived per authority: a fixed binary needs little; an
  interpreter needs the broad set and its enforcement rests on landlock,
  cgroup and no network. Shell-level policy is most meaningful for fixed
  and launcher authority and mostly advisory once an interpreter is
  admitted. git can exec via hooks and aliases; funnels through execve,
  which the allowlist gates. No network means nothing to push or fetch.
- Admission rule for anything in the model's PATH: in distribution? needed
  for this task? zero privilege beyond the process's policy? The answer can
  differ between a text-only task and a SWE task.
- Decided: Cedar is the policy language. The declaration names a Cedar
  policy file; cead compiles it to the seccomp filter and Landlock ruleset.
  The v0 permit-all policy is a Cedar file. What Cedar adds over the kernel: argument-level rules the kernel
  cannot see (`--force` in argv); a denial the model can read before spawn
  instead of EPERM after; an adjudication stream that is a decision, not an
  inferred kernel error. Cedar is a candidate notation for the rows of the
  call table when they outgrow Rust match arms. brush being embeddable means
  policy can run against the parsed AST before spawn. It is bypassable
  (`python -c`), so enforcement is the kernel. Prefer generating both from
  one source over mirroring by hand.
- Measure: policy denials per run, split by advisory vs kernel-enforced;
  ENOSYS fallbacks observed, which is the allowlist telling you where it is
  too tight or where a libc moved.

## 5. tools seam: task images, OCI as format not runtime

Docker bundles three things; take two. Adopt the image format and registry
(digest names state as cleanly as a nix hash) and the Dockerfile as an
authoring format (runs at build time on the host, where nix also runs).
Skip a container runtime in the guest by default:

- A container is ordinary processes whose world was arranged in the
  fork-exec gap. The harness and init already do that; cead is already a
  minimal container runtime.
- A second wall inside the VM buys little and costs size, boot time, moving
  parts. A second cgroup manager muddies the observer's keying and budget
  accounting. Layered seccomp fights the generated allowlist. Pulls, bridges
  and iptables assume a network the guest does not have. `docker exec` in
  front of every command is out of distribution, and moving the shell inside
  the container makes the image the root filesystem anyway.

Pipeline. Host, build time: resolve the image by digest; unpack layers into
a read-only disk image (ext4, squashfs or erofs: open); record digest and
derived tool list with the run. Boot: the backend attaches the core rootfs
plus the task disk as a second block device. Guest, in init, before the
model's first byte: mount namespace with the task image as root, a writable
overlay (tmpfs or scratch: open), core bind-mounted read-only and first on
PATH, descriptors mounted, then landlock, seccomp, cgroup, exec. Honour
`ENV`, `WORKDIR`, a sensible answer for `USER`; ignore `ENTRYPOINT`/`CMD`.
Firecracker-based platforms generally convert images to VM root filesystems
rather than run an engine inside (e.g. Fly.io; verify before citing).

- The tool list is derived from the OCI config plus a label
  (`LABEL cead.tools="python pytest"`), marked as declared when it cannot be
  derived. Authority per tool is derived at load and recorded. Open: exact
  label schema.
- nix emits OCI images too, so a task image is one kind of artifact with two
  producers. nix additionally builds the core. Inherited benchmarks need no
  special case.
- Where the bar for core sits: every addition is a promise to every future
  run. In distribution, broadly needed, stable in behaviour. Everything else
  is a task tool.
- Caveats: images assume root and a particular libc (the static core is
  unaffected; which uid the model gets inside the view is open). Core-first
  PATH can collide with an image expecting its own git or grep. Guest kernel
  needs overlayfs and the chosen read-only filesystem built in. Flatten
  multi-layer images on the host. Open: cache unpacked images by digest;
  multiple task images per run and their order.
- When the task itself needs containers (compose, image builds, test
  containers), a container engine is a task tool: rootless podman, images
  preloaded, authority launcher/service. A tool, not the mechanism.
- Measure: core size, rootfs size with a task image, boot with and without
  the task disk.

## 6. Postgres as a task tool

SQLite is the native database: a file plus the `sqlite3` CLI in the core,
so it is a path in the declaration, a snapshot captures it, and there is no
service, uid, socket or process structure for the observer to key on. One
writer per file; a file shared across forks is copy-on-write by the
snapshot, never shared-writable. The `sqlite3` version and compile options
are in the nix hash like any core tool. No server assumptions (connections,
pooling, URLs) on this path: it is a file.

Postgres enters when a task needs extensions (pgvector and similar), real
concurrency, or arrives with a data directory or seed. Then it is a
service-class task tool: its own uid and cgroup, one unix socket, psql the
real one. Inside the guest so snapshots capture it; external state would
escape the version vector. Seams can show (extensions, version string,
EXPLAIN, some error text); the schema note the descriptor drops names the
dialect, so the pinned prompt is derived from what was mounted, as always.

pgrust (checked 2026-09-20, malisper/pgrust README): Rust rewrite, wire- and
dialect-compatible, reports passing the Postgres regression suite,
disk-compatible with a Postgres 18.3 data dir. AGPL-3.0. Existing extensions
not generally compatible (no pgvector-style plugins). Newer version is
thread-per-connection. Its correctness-trust caveat matters less in a
disposable sandbox.

Ordering is a judgment call: validate the harness on stock Postgres first so
a strange result has one suspect, then pgrust; or pgrust-first with stock
Postgres for extension needs. Either way the tool is in the task image and
the declaration records it.

Open: a single `.sqlite` file vs schema plus seed dump as the git-tracked
form; the log as SQLite (tlog tile stores have been built on it) once it
needs querying in place; scratch as a WAL-mode file when structure helps
the model find context; a `$CTX` table for tabular context. None until a
run demands it.

## 7. Virtualization.framework backend and host portability

Both backends run a Linux guest, so the invariant is the Linux syscall ABI,
not POSIX portability. Guest code uses linux_raw and Linux-only crates
freely. Host code (the CLI, proxy, log writer, grader glue) runs on Linux and
macOS and stays inside the POSIX line: rustix with its libc backend on
macOS, std, nothing Linux-specific, the VMM behind the backend as the only
per-OS piece. Open: whether any host feature (file locking, fs events)
tempts a Linux-only shortcut.

Workspace split that enforces it mechanically:

- `cead-core`: types only (Ctx, Budget, Bounded, declaration, call table).
  No syscalls. Compiles everywhere.
- `cead-guest`: Linux-only. rustix linux_raw, seccompiler, landlock, cgroups,
  brush. `#![cfg(target_os = "linux")]`.
- `cead-observer`: Linux-only, aya. Tied to the pinned kernel.
- `cead-host`: portable. CLI, proxy, log, snapshots, gix.
- `cead-backend-firecracker`, `cead-backend-vz`.

The Mac mini boots arm64 guests; benchmark images are x86_64. Rebuild or
Rosetta in the guest.

## 8. measurements: `cead stats`, the VM-boundary decision, README update, demo

Deliverables: the numbers below from real runs; targets set from first
measurements and then treated as budgets; a CI size budget on `cead-guest`
and `cead-host` dependency count and binary size; README updated with a
small honest table (size, boot, density, cost per task); a demo. Derive from
what exists (receipts, log, traces, proxy records) before building separate
telemetry; a number that cannot be derived is a missing log field. Open:
which become `cead stats` output vs offline analysis; whether per-run
metrics are a leaf in the log so they travel with the run.

Two sets. Set A, cead itself, owned, absolute: footprint, lifecycle latency,
step latency, inference side, RL interface, memory-policy numbers, cost,
overhead, reliability. Set B, task performance, inherited, comparative: same
model, same subset, same official scorer, harness the only variable; the
claim is a delta. Pin model and sampling, step and context budget, subset,
scorer; several seeds both sides. B says whether cead changes outcomes; A
says why. Bridge: resolve rate per dollar (or per million tokens).

- Footprint: core size; rootfs with task image; snapshot size and growth;
  memory per idle, per active process, per child; log bytes per run;
  processes per host at fixed memory.
- Lifecycle: cold boot to first command; `cead run` to first token;
  snapshot create, restore, fork-from-snapshot vs cold; child spawn (spawn,
  cgroup, seccomp/landlock, slice handoff); teardown and what is left
  behind. p50/p95/p99, not means.
- Step: model time, tool time, harness time (ours); vsock round trip through
  the proxy; bound-and-spill cost on large output; log append latency and
  fsync policy; wall clock and steps per task.
- Inference side: TTFT and decode tokens/s; prompt-cache hit rate (the
  byte-stable prompt exists for this); input tokens per step over the run;
  batch occupancy; env-vs-inference wait ratio.
- RL interface: rollouts per host and GPU-hour; trajectory tokens/s; fork
  fan-out cost, K from one snapshot vs K cold; policy staleness; weight sync
  time; logprob capture overhead and engine-vs-trainer agreement (known
  silent-trouble source; verify for the stack); export path from log to
  training example; reward latency from `done` to score.
- Memory policy (the thesis): window occupancy over time; bytes read from
  state vs bytes admitted; truncation rate and spill follow-up rate (low
  follow-up means truncation is losing information the model does not know
  to fetch); re-read rate (cache-miss analogue); evictions per run and what
  was evicted before a failure; span coverage of `$CTX` or repo; doc opens
  per page; recursion depth and fan-out, budget split vs used;
  budget-exhaustion rate by depth; tokens per resolved task.
- Cost: per run, per resolved task, inference vs compute vs storage; fork vs
  cold; log and snapshot retention.
- Overhead: observer on vs off; seccomp and landlock on tool-heavy steps;
  ENOSYS fallbacks; denials by class.
- Reliability: boot failure, orphaned VMs, OOM kills, timeouts, clean
  teardown; isolation tests (guest cannot reach host, grader, keys, log);
  same version vector gives same prompt hash.
- Task quality (B): resolve rate vs bash-only baseline; variance across
  seeds; steps to solve; invalid-command rate and whether the hint helped;
  failure taxonomy: model, task flaw, harness. Only the third is ours.

The VM-boundary decision. The one real fork in the design: keep the micro-VM
boundary and engineer it toward container efficiency, versus work at the
container/pod layer (gVisor, Agent Substrate) and take RAM efficiency per
host. Leaning: keep the VM. Efficiency is a gap closed incrementally and
every gain is kept; a hardware boundary and a real kernel to instrument
cannot be retrofitted. Density wins at the app layer come from agents idle
for hours; rollouts and evals are busy then gone, so what matters is active
memory per process and fork latency. K continuations from one snapshot can
share pages copy-on-write until they diverge (from memory; measure early).
cead uses little of the VM: stripped kernel, no init system, static Rust
userspace.

Decided: Kubernetes schedules runs and never the inside of one. A pod runs
`cead` with Firecracker inside it and `/dev/kvm` from a device plugin; one
Job per run; Job parallelism is many runs (instances, seeds), a fork is one
run's tree. No observer DaemonSet: the observer is ring 2, inside the
guest. Kata as a backend is a wall: it owns the guest kernel, the rootfs
and PID 1 (kata-agent, guest root). Resource requests come from measured
memory per active process and boot latency, which sizes density per host.

Evidence that would reopen the VM decision: active memory
per process beyond some multiple of the gVisor equivalent AND the workload
turning out idle-heavy, OR fork-from-snapshot not sharing memory, OR restore
latency dominating short rollouts. Thresholds from first measurements.

## 9. one memory hierarchy: inference control

Behind an API the window is an opaque cache influenced only with tokens, and
inference is a socket behind the host proxy. Fine for v0. Controlling the
engine and the weights changes the architecture, because the window becomes
one tier managed end to end:

| Tier | What | OS analogue |
|---|---|---|
| weights | shared, read-only, in GPU memory | text segment |
| KV cache | working memory paged across GPU, host RAM, disk | pages / swap (PagedAttention was modelled on virtual memory) |
| window tokens | what the model can address now | logical address space |
| files, database | where state lives | backing store |
| log | durable truth | journal |

Leanings to test: the same eviction is currently made twice, blind (cead at
token level, the engine at KV-block level); with control, distinguish
lossless eviction (offload KV blocks, like swapping) from lossy (summarise
to a file and drop). Fork becomes one primitive at three tiers: VM pages,
filesystem layers, KV blocks for the shared prefix. "The log is truth" makes
KV a pure cache: every tier above the log is evictable by construction.
Weights join the version vector, since KV is valid only for the weights that
produced it; under RL a policy update is a cache-coherence problem.
Scheduling becomes locality: move the environment to its KV or pay to move
the KV; thrashing is more active processes than their KV working sets fit
(Denning, one tier down). The pinned prompt is a shared read-only prefix
across a run tree. Two schedulers, one problem: whatever places VMs and
whatever places tokens (vLLM, Dynamo; verify) both decide residency.

Open: whether cead exposes hints to the serving layer (shared-prefix groups
for forks, expected fan-out, "this process is suspended, its KV may go
cold"); co-location of rollouts and inference; the unit of scheduling when
one run is a tree; whether lossy vs lossless eviction is a policy the
harness owns.

## 10. name

Checked roughly 150 short candidates against crates.io, npm, PyPI, Homebrew
and every binary in Ubuntu noble (2026-09-20). `cead` is free on crates.io,
npm and Homebrew, no Ubuntu binary, only tiny unrelated GitHub repos; taken
on PyPI, which matters only if Python bindings ship. Near-misses: `gov`
(Governator) and `kern` (a Rust sandbox runtime for AI-generated code),
which also makes `ker` risky. The céad ("hundred", "the first") overlap is
accepted: the human is depth 0. `cead` 0.0.1 is published on crates.io
(2026-09-23); the name is held. To do: check domains and trademarks.

Vocabulary that fell out, for internal naming if wanted: `glas` (lock;
in-guest enforcement),
`fior` (true; the prompt rendered from what is true). Also free and apt:
`satp`, `wset`, `amb`, `zoh`, `lyap`, `lfp`.

## 11. README return pass, at first release

The README carries placeholders until the first install exists. Replace
them in one PR, after the loop runs end to end:

- Install instructions.
- An example run with real input and output files, replacing the
  `issue.md` / `patch.diff` sketch.
- "A SWE-bench instance image works as is" is a constraint the README
  already states. Hold to it until a crosswalk step is proven necessary;
  if one is, the README line changes to say exactly what and why.
- A screen recording of the operator shell; the mockup
  (`assets/terminal-mockup.png`) is the intent, the recording is the
  truth. A demo video for the hiring-manager reader.
- License. None until there is code to run; leaning Apache-2.0. A public
  repo without one is all rights reserved, so decide in this PR.
- Visuals: the lockup source, palette and terminal mockup are in `assets/`.
- Network rules as enforced, replacing the placeholder.
- Automation and Governance subsections under Deployment, if there is
  something settled to say; cut from the draft rather than invented.
- The measured table from §8.

Three readers, in order: a recruiter pattern-matching in seven seconds;
a hiring manager looking for taste, a demo and specifics; a power user
installing it. Every sentence serves one of them.

## 12. two axes of fan-out: `rlm` and fork

Two mechanisms, deliberately separate. `rlm` is recursion in depth inside
one running machine: a child process with a slice of the parent's context,
part of its budget, the same tools, its own context window. A sub-agent
built from process structure. Fork is of the machine: a snapshot boots a
second machine that diverges from the same state, the worktree idea
applied to the whole machine.

Leaning: a snapshot is a declaration plus state, so a forked machine's
declaration is derived from the snapshot, never authored. The CLI then
needs one mechanism for "boot from" with two sources: a declaration file,
or a snapshot. A scheduler (Kubernetes, one pod per machine) is handed
either. Open: whether the operator shell forks with the machine (a new
shell over the new machine) or stays over the parent and lists children.

# How cead is built: method, vocabulary, languages

Push every invariant you can into the types, cover the rest with tests, and spend review on what neither can express.

# Method

Spec, skeleton, fill. TLA+, Lean and Rust are one pipeline, not alternatives: TLA+ specifies the system (processes and how they interleave), Lean specifies a core (a pure function and its properties), Rust is the system.
**Unpracticed until `initial-spec`; confirm the approach for each PR.**

1. **Spec.** `spec/cead.tla` states what every behaviour of cead satisfies. Coarse and revisable: when code disagrees with it, the spec changes in that PR.
2. **Slice.** A PR takes a slice of the spec. Its dependencies are probed while scoping; findings go in a PR comment, the probe is never committed.
3. **Core.** A pure function with a property worth proving gets its Lean spec first, green before any Rust.
4. **Skeleton.** One commit of types, signatures, private fields and one doc comment per item (what it owns, when it drops); bodies are `todo!()`; the type gate is green. It is the spec of custody. It mirrors the spec: variables become fields, states become variants or typestates, each action becomes one signature.
5. **Fill.** Later commits change bodies. A signature that moves is learning: say why in the commit comment. A new capability is drift: it belongs to another PR. A fill commit names the action it implements.

- Each placeholder is fillable from its own file plus the public types of what it imports. If more is required, move the boundary.
- Fill order: plain types, then leaves (no I/O, no mutable state), then orchestration.
- Tests are end to end first (AGENTS.md). A leaf test lands in the commit that fills its subject.
- The checker counts two marks; review reads them:
  - **frontier**: placeholders, the shape promised and not delivered. Zero at merge.
  - **claim**: an assertion the checker cannot verify, each with its reason. Review reads every one.

## Boundaries

- Which side of which contract is new code on: model-facing, guest tool, harness, observer, host? What is its source of stability: written spec, ABI promise, pinned version, none? Below the ABI, what re-validates it when the pinned kernel changes?
- The model's side is untyped and GNU-flavoured. Types live between the shell and the kernel, never in the shell. Widening the model-facing surface is GNU-flavoured POSIX or a third call in disguise.
- The call table is the single source: builtins, exec policy, prompt lines and man text render from it, never a second list. Two calls; new capability arrives as state or a well-known CLI.
- A dependency's types stay inside the boundary module that wraps it. The skeleton names our nouns; swapping a dependency is a module change.

# Vocabulary

Every noun has one home in code: a type, a module or crate, or a binary. A noun may precede its home; the PR that first needs it builds it. No home without a noun.

| Noun | Meaning | Home |
|---|---|---|
| authority | How far a binary can go beyond its argv: fixed, launcher, client, interpreter, service. | |
| backend | What boots a machine: Firecracker on Linux, Virtualization.framework on macOS. Same guest, same evidence. | |
| bounded | Output admitted to the window, constructible only by truncation. The remainder **spills** to a file. | |
| budget | What a process tree may spend. A parent moves part of what remains into each child, never copies it. What it counts is declaration policy. | |
| call | A command whose effect is on the harness: `rlm`, `finish`. | |
| call table | The single source; renders builtins, exec policy, prompt lines, man pages. | |
| cead | The project, the operator's binary, and its shell over a declaration and its state. | crate and binary `cead` |
| command | What the model writes: shell over the core plus the task image. | |
| contract | One of the three lines everything else is swappable between. | |
| core | The invariant tools every machine has: brush, uutils, grep, git, sqlite3. nix-built, static, first on PATH. | |
| declaration | The one file that pins a machine. Equal declarations are the same experiment; its hashes are the version vector. | |
| descriptor | State the model holds this session, bound to an object with rights. Minted by cead, never discovered; a capability. A child's is **attenuated**. | |
| evict | Dispose at any tier: window span, KV block, process, machine. | |
| harness | The Rust program in the machine, its memory manager. Runs each process's cycle, installs kernel policy in the fork-exec gap, supplies the calls, writes receipts. | |
| init | PID 1 in the guest. Assembles the view (task image as root, overlay, core first on PATH, descriptors), applies policy, execs the harness. | |
| limit | A cap on one process: window size, bound, steps, wall time. The rlimit analogue: set in the fork-exec gap, inherited as a copy. | |
| log | The append-only sequence of receipts, a flat file on the host. A finished run cites its hash. | |
| machine | The unit: pinned kernel, core, task image, descriptors, calls, policy and model endpoint, booted in a microVM by a backend. | |
| membrane | The calls as boundary: untyped argv and stdin in, typed request inside, text and exit code out. | |
| model endpoint | Where inference is, reached only through the host proxy; keys never enter the guest. | |
| observer | eBPF keyed by cgroup, outside the model's reach. | |
| operator | The human at depth 0. Types `cead` or `cead run`; never types a call. | |
| pinned | The part of the window eviction never touches: the system prompt. | |
| policy | The rows of the call table in Cedar, compiled to seccomp and Landlock, installed before exec. Permit-all is a declared policy, not an absence. | |
| process | One harness cycle with its own cgroup, window, shell, limits and budget. Started by `run` at depth 0 or by `rlm` below it. | |
| query | The argv of `run` or `rlm`, commit-message sized. Anything longer is context. | |
| receipt | One record per command, three streams under one invocation id: intent, adjudication, witness. | |
| rights | What a call may do to state: read, write. | |
| ring | A privilege layer: model processes; harness and observer; host. | |
| run | One machine, one root process and its tree, one log. From the operator shell or one-shot `cead run`; the machine ends with it. | |
| slice | The bytes a child receives on stdin, sealed. | |
| snapshot | The whole guest at an instant. The fork mechanism. | |
| step | One command and its observation. The unit of budget and of measurement. | |
| task image | The tools one task brings: a read-only OCI image with a label declaring its tools, attached at boot. | |
| verdict | The adjudication of a command: permit or forbid. | |
| window | The context the model can address now. A cache over state. | |

# Rust

## Types are the schema

The language enforces, always:
1. Entity integrity: every value has exactly one owner.
2. Referential integrity: no reference outlives what it refers to.
3. Isolation: no write can falsify a live view.
4. Uniqueness: at most one impl per (type, trait) pair.
5. Encapsulation: invariants are established only by code with access to the fields.

Soundness: no sequence of safe operations commits a state that violates the schema.
Everything else (fields, structs and enums, most traits, invariants like `len ≤ capacity`) is a choice, held only by privacy, tests or proofs. To tell which: change the line and run `cargo check`. If it still compiles, it was a choice, yours or an agent's.

## Idioms

- States are enums, matched exhaustively. A lifecycle over a kernel object is a typestate (a sealed memfd, a booted machine) and the invalid transition does not compile.
- A signature is a custody statement: by value moves, `&T` shares, `&mut T` claims, `Arc` confesses that ownership isn't a tree.
- When the borrow checker fights the skeleton, the custody is wrong: revise and re-declare, never wrap in `Rc<RefCell>`.
- A trait or a generic exists only where a second implementation exists.
- `pub(crate)` is the default; `pub` is an API promise. Modules are visibility boundaries; files lag the graph, one file per stack until it shows dense-inside, sparse-outside.
- Two failure modes: traits everywhere is Java in Rust; free functions passing `&mut world` is C in Rust.
- Frontier: `todo!()`, `unimplemented!()`, `unwrap`, `expect`, `#[ignore]`. Claim: `unreachable!()` and `#[expect(lint, reason = "…")]`; `#[allow]` does not exist here. An `unreachable!()` is a state the types failed to make impossible: try that first.

## Environment

- Stable toolchain with clippy, pinned in `rust-toolchain.toml`.
- `Cargo.toml` and `clippy.toml` lints are the rules. `cargo check` on every edit; `cargo clippy --all-targets -- -D warnings` and `cargo test` green before ready. Frontier lints warn, so a draft compiles and a ready PR cannot.
- eBPF program crates alone lift `unsafe_code`, in their own `Cargo.toml`, visibly.
- `Cargo.toml` is the allowlist: no new dependency without approval. Preferences: rustix, never libc directly; clap derive; anyhow in binaries, thiserror in libraries; serde. Boundary crates: rustix, aya, seccompiler, landlock.
- One published crate, `cead`. When the workspace splits (core, guest, observer, host, backends) members are `publish = false`.
- Host crates build on macOS: rustix with its libc backend, std, nothing Linux-specific. A Linux-only crate in the host tree is the axis being violated. Guest crates are `#![cfg(target_os = "linux")]` and use linux_raw and Linux-only crates freely.
- The core is nix-built and static.

# TLA+

- Modules are `spec/<name>.tla` with `<name>.cfg`; the system spec is `spec/cead.tla`. TLC is green before any Rust exists; the commit line records the TLA+ tools version and the bounds it passed at.
- A PR that changes a protocol re-runs TLC, by hand until CI is demanded.
- **spec**: a formula over behaviours of a state machine. **action**: one transition; one signature. **invariant**: what every reachable state satisfies; what TLC checks. **instance**: the bounds TLC searched; a proof only up to them.

# Lean

- Lean 4 via elan, toolchain pinned in `lean-toolchain`, one lake project in `spec/`. `lake build` green before any Rust exists.
- **spec**: an executable definition. **theorem**: a property proved of it. **differential test**: random inputs through spec and Rust, outputs compared in `cargo test`; the only tie between them. How spec outputs reach `cargo test` is for the first Lean PR.

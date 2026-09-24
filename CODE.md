# cead's Workflows, Environments, and Vocabularies by Language

Nouns are types. A noun without a type is not in the domain.

Which model a seed gets follows from its signature: interleaving across processes is a protocol and gets TLA+; a function is a core and gets Lean; neither means no model. The model commit precedes the skeleton.

# Rust

## PR Workflow
**NOTE: These are guidelines and are still being finalized; confirm approach for each PR.**

- `cargo check` on every edit. `cargo clippy` and `cargo test` green before a PR is marked ready. The lints are the rules.
- The skeleton commit is types and signatures with `todo!()` bodies, `cargo check` green. It is the spec of custody; the model, when there is one, is the spec of behaviour. Review diffs landed signatures against it.
- Every noun in Vocabulary is a struct or enum. No type without a noun, no noun without a type.
- States are enums, matched exhaustively. A lifecycle over a kernel object is a typestate — a sealed memfd, a booted machine, an evicted machine — and the invalid transition does not compile.
- A signature is a custody statement: by value moves, `&T` shares, `&mut T` claims, `Arc` confesses that ownership isn't a tree. One doc comment per item: what it owns, when it drops. Get these right in the skeleton; fill commits change bodies only and state why if a signature moves.
- When the borrow checker fights the skeleton, the custody is wrong: revise and re-declare, never wrap in `Rc<RefCell>`.
- A trait or a generic exists only where a second implementation exists. One impl is speculation.
- Each `todo!()` must be fillable from its own file plus the public types of what it imports. If more is required, move the boundary.
- Fill order: plain types, then leaves (no I/O, no mutable state), then orchestration.
- Tests land in the same commit as the body they test. A test whose subject is still `todo!()` is `#[ignore = "todo"]`.
- Placeholders: `todo!()`, `unimplemented!()`, `unwrap`, `expect`, `#[allow]`, `#[ignore]`. A draft may carry them; a ready PR has zero. `clippy::todo` and `clippy::unimplemented` are denied at ready alongside the workspace lints.
- `pub(crate)` is the default; `pub` is an API promise. Modules are visibility boundaries; files lag the graph, one file per stack until it shows dense-inside, sparse-outside.
- Two failure modes: traits everywhere is Java in Rust; free functions passing `&mut world` is C in Rust.
- The call table is the single source. Builtins, exec policy, prompt lines and man text render from it; never a second list. Two calls; new capability arrives as state or a well-known CLI.
- The model's side of the boundary is untyped and GNU-flavoured. Types live between the shell and the kernel, never in the shell.
- For any new piece of code: which side of which contract is it on (model-facing, guest tool, harness, observer, host)? what is its source of stability (written spec, ABI promise, pinned version, none)? if below the ABI, what is the re-validation step when the pinned kernel changes? if it widens the model-facing surface, is it GNU-flavoured POSIX or a third call in disguise?

## Environment

- Stable toolchain, pinned in `rust-toolchain.toml`.
- Workspace lints, not prose:

  ```toml
  [workspace.lints.rust]
  unsafe_code = "forbid"
  unreachable_pub = "warn"

  [workspace.lints.clippy]
  unwrap_used = "deny"
  expect_used = "deny"
  ```

  Tests lift the unwrap lints with `#![cfg_attr(test, allow(...))]`. eBPF program crates alone lift `unsafe_code`, in their own Cargo.toml, visibly.
- Cargo.toml is the allowlist: no new dependency without approval. Preferences: rustix, never libc directly; clap derive; anyhow in binaries, thiserror in libraries; serde.
- Boundary crates: rustix, aya, seccompiler, landlock.
- One published crate, `cead`. When the workspace splits (core, guest, observer, host, backends) members are `publish = false`; `cead` stays the only public name.
- Host crates build on macOS: rustix with its libc backend, std, nothing Linux-specific. A Linux-only crate in the host tree is the axis being violated. Guest crates are `#![cfg(target_os = "linux")]` and use linux_raw and Linux-only crates freely.
- The core (brush, uutils, grep, git, sqlite3) is nix-built and static.

## Vocabulary

- **cead**: the project, the operator's binary, and its shell over a declaration and its state.
- **operator**: the human at depth 0. Types `cead` or `cead run`; never types a call.
- **machine**: the unit. A pinned kernel, core, task image, descriptors, calls, policy and model endpoint, booted in a microVM by a backend.
- **declaration**: the one file that pins a machine. Equal declarations are the same experiment. Its hashes are the version vector.
- **backend**: what boots a machine. Firecracker on Linux, Virtualization.framework on macOS. Same guest, same evidence.
- **init**: PID 1 in the guest. Assembles the view (task image as root, overlay, core first on PATH, descriptors mounted), applies policy, execs the harness.
- **harness**: the Rust program in the machine and its memory manager. Runs each process's cycle, installs kernel policy in the fork-exec gap, supplies the calls, writes receipts.
- **process**: one harness cycle with its own cgroup, window, shell and budget. Started by `run` at depth 0 or by `rlm` below it.
- **run**: one machine, one root process and its tree, one log. Started from the operator shell or one-shot by `cead run`; the machine ends with it.
- **step**: one command and its observation. The unit of budget and of measurement.
- **window**: the context the model can address now. A cache over state.
- **pinned**: the part of the window eviction never touches: the system prompt.
- **bounded**: output admitted to the window; constructible only by truncation. The remainder **spills** to a file.
- **budget**: what a process may spend. Moves into children, never copied. What it counts is declaration policy.
- **slice**: the bytes a child receives on stdin, sealed.
- **descriptor**: state the model holds this session, bound to an object with rights. Minted by cead, never discovered. A capability. A child's is **attenuated**.
- **command**: what the model writes. Shell over the core plus the task image.
- **core**: the invariant tools every machine has: brush, uutils, grep, git, sqlite3. nix-built, static, first on PATH.
- **task image**: the tools one task brings. A read-only OCI image with a label declaring its tools, attached at boot. Postgres, a container engine, an interpreter: task tools.
- **query**: the argv of `run` or `rlm`: what the operator or a parent asks for, commit-message sized. Anything longer is context. The RLM paper's word.
- **call**: a command whose effect is on the harness. `rlm`, `done`.
- **call table**: the single source. Renders builtins, exec policy, prompt lines, man pages.
- **membrane**: the calls as boundary: untyped argv and stdin in, typed request inside, text and exit code out.
- **rights**: what a call may do to state: read, write.
- **authority**: how far a binary can go beyond its argv: fixed, launcher, client, interpreter, service.
- **policy**: the rows of the call table, written in Cedar, compiled to seccomp and Landlock and installed in the kernel before exec. Permit-all is a declared policy, not an absence.
- **verdict**: the adjudication of a command: permit or forbid.
- **observer**: eBPF keyed by cgroup, outside the model's reach.
- **receipt**: one record per command, three streams under one invocation id: intent, adjudication, witness.
- **log**: the append-only sequence of receipts, a flat file on the host. A finished run cites its hash.
- **snapshot**: the whole guest at an instant. The fork mechanism.
- **model endpoint**: where inference is. An API, a local server, later the same box. Reached only through the host proxy; keys never enter the guest.
- **contract**: one of the three lines everything else is swappable between.
- **ring**: a privilege layer: model processes, harness and observer, host.
- **evict**: dispose at any tier: window span, KV block, process, machine.

# TLA+

## PR Workflow
**NOTE: Unpracticed; confirm approach for each PR.**

- A seed whose signature interleaves across processes is a protocol and gets a TLA+ model before the skeleton. Candidates: the fork–exec gap, log/snapshot/fork, the budget tree.
- The model commit is `spec/<name>.tla` with its `<name>.cfg`, beside the crate it models. TLC is green before any Rust exists; the commit line records the bounds it passed at.
- Each action in the spec names one skeleton signature; the resolution commit for that signature names the action. Where model and code diverge, the commit says so.
- A PR that changes a protocol re-runs TLC. By hand until CI is demanded.

## Environment

- TLA+ tools (SANY, TLC), Java. The tools version is recorded in the commit line with the bounds.

## Vocabulary

- **spec**: a formula over behaviours of a state machine.
- **action**: one state transition. Maps to one signature.
- **invariant**: what every reachable state satisfies. What TLC checks.
- **instance**: the bounds TLC searched. A proof only up to them.

# Lean

## PR Workflow
**NOTE: Unpracticed; confirm approach for each PR.**

- A seed whose signature is a pure function is a core and gets a Lean model before the skeleton. Candidates: `Budget::split`, eviction, the export schema round-trip, the pinned-prompt renderer.
- The model commit is a theory in the `model/` lake project: an executable definition plus theorems, `lake build` green before any Rust exists.
- A differential test feeds the same random inputs through the model and the Rust and compares outputs, in `cargo test`. It is the only thing that ties the two. How model outputs reach `cargo test` is open; the first Lean PR decides.
- First model: `Budget`, after the first loop ships. It measures the floor: toolchain cost and the differential bridge.

## Environment

- Lean 4 via elan, toolchain pinned in `lean-toolchain`, one lake project at `model/`.

## Vocabulary

- **model**: the executable Lean definition of a core function.
- **theorem**: a property proved of the model.
- **differential test**: random inputs through model and Rust, outputs compared.

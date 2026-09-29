# How cead is built: method, vocabulary, languages

Push every invariant you can into the types, cover the rest with tests, and spend review on what neither can express.

# Method

Spec, skeleton, fill. TLA+, Lean and Rust are one pipeline, not alternatives: TLA+ specifies the system (processes and how they interleave), Lean specifies a core (a pure function and its properties), Rust is the system.

0. **Scope.** Numbered questions, one recommendation each; facts fetched before asking; each decision written into the PR description.
1. **Spec.** `spec/cead.tla` states what every behaviour of cead satisfies. Coarse and revisable, never looser than the system: a behaviour the spec allows and the system cannot have is a wall, so the spec changes.
2. **Slice.** A PR takes a slice of the spec. Its dependencies are probed while scoping; findings go in a PR comment, the probe is never committed.
3. **Core.** Ask what a skeptic has to trust. Every pure function on that path (what signs, verifies, admits or renders) gets its Lean spec first, green before any Rust, and a differential test; elsewhere, a pure function gets one when a property is stated.
4. **Skeleton.** Its shape (modules, types, custody) is agreed first. Then one commit of types, signatures, private fields and one doc comment per item (what it owns, when it drops); bodies are `todo!()`; the type gate is green. It is the spec of custody. It mirrors the spec: variables become fields, states become variants or typestates, each action becomes one signature. Its commit comment carries the table from spec to code, the tie nothing checks; every type gets a row in Vocabulary.
5. **Fill.** Later commits change bodies. A signature that moves is learning: say why in the commit comment. A new capability is drift: it belongs to another PR. A fill commit names the action it implements.

- Each placeholder is fillable from its own file plus the public types of what it imports. If more is required, move the boundary.
- Fill order: plain types, then leaves (no I/O, no mutable state), then orchestration.
- Tests are end to end first (AGENTS.md). A leaf test lands in the commit that fills its subject.
- The checker counts two marks; review reads them:
  - **frontier**: placeholders, the shape promised and not delivered. Zero at merge.
  - **claim**: an assertion the checker cannot verify, each with its reason. Review reads every one.

## Boundaries

- Which side of which interface is new code on: model-facing, machine tool, harness, tracer, host? What is its source of stability: written spec, ABI promise, pinned version, none? Below the ABI, what re-validates it when the pinned kernel changes?
- The model's side is untyped and GNU-flavoured. Types live between the shell and the kernel, never in the shell. Widening the model-facing surface is GNU-flavoured POSIX or a second call in disguise.
- The call table is the single source: builtins, exec policy, prompt lines and man text render from it, never a second list. New capability arrives as state or a well-known CLI.
- A dependency's types stay inside the boundary module that wraps it. The skeleton names our nouns; swapping a dependency is a module change.

# Vocabulary

Every noun has one home in code: a type, a module, or a subcommand. A noun may precede its home; the PR that first needs it builds it. No home without a noun, and no type outside tests without a row here. Paths are from `src/`; a type's errors and states sit in its row.

| Noun | Meaning | In code |
|---|---|---|
| agent | The call cead adds: spawns a child process with a query and a slice. | `machine::agent::agent`, run as `agent` |
| amplification | A child asking for more rights than its parent holds; attenuation forbids it (ocap). | `machine::process::Amplification` |
| attestation | What the processor signs about a boot: SNP's TSM report, or none in trusted-host mode. | `record::Attestation` |
| authority | How far a binary can go beyond its argv: fixed, launcher, client, interpreter, service. | |
| availability | The job runs and ends. The host guarantees it, and can always deny it. | `spec/cead.tla` |
| blocked | A process waiting: on its intent's decision, its command's end, or a foreground child. Holds the model's turn until the call returns. | `machine::process::Blocked` |
| boot | One life of a machine's kernel, from the VMM starting it to eviction, with one key, which names it. Its records are numbered from its report, each signed with that key. **Complete** when the log holds its records through its exit record with no gap; otherwise **unknown** (crash, host kill, lost report). Linux's `boot_id`. | `record::Boot`; `spec/cead.tla` |
| bounded | What a call returns: the output whole if it fits the bound and is text, else none of it and where it **spilled**, a file the model reads like any other state. Nothing is truncated or re-encoded, so the window holds exactly what the log replays. | `machine::bounded::Bounded` |
| call | One command the model issues and what it gets back: a system call into the harness. Untyped argv and stdin in, text and exit code out. The unit of limits and measurement. Its intent, decision and witness share its id. | `record::CallId` |
| call table | The system call table: the toolset. | |
| cead | The project and its one binary, its role chosen at start: `run` on the host; `init`, `harness` and `agent` in the machine. | crate and binary `cead`; `main::Role`, `Usage` |
| command | What the model writes: shell over the core plus the task image. The harness takes it from the model's turn. | bytes in `record::Event::Intent` |
| confidentiality | No one outside the machine can read it. Guaranteed by the processor on an attested boot; claimed by no one in trusted-host mode. | |
| console | The operator's interface to manifests, machines and their state: `cead` with no verb. Its verbs drive the scheduler. | |
| core | The invariant tools every machine has: brush, uutils, grep, git, sqlite3. nix-built, static, first on PATH. | |
| decision | The outcome of checking a call against policy: deny (with what the call returns), allow, or spawn (allowed `agent`, naming the child and its query). | `record::Decision` |
| descriptor | State the model holds this session, bound to an object with rights. Minted by cead, never discovered; a capability. A child process's is **attenuated** when it is spawned, and never grows; revoking it is `kill`. | |
| engine | Executes the weights and signs what it produces: the model's counterpart to the machine. Reached from the machine over vsock, through the gateway. | `machine::engine::Engine` |
| evict | Dispose at any tier: window span, KV block, process, machine. | `host::vmm::Machine::evict` |
| executed | What the kernel ran: the truth the records record. | `spec/cead.tla` |
| gateway | The host's relay to a hosted engine: holds the credential the machine never sees (a Bedrock API key), sends each window through `curl`, and records it with its turn and tokens, a second account of every window. | `host::gateway::Gateway`, `Credentials`, `Answer`, `Failed` |
| harness | The model's kernel, exec'd by init so it starts without the key. Runs each process, installs kernel policy in the fork-exec gap, serves the calls, numbers records for init to sign. One method per spec action. | `machine::harness::Harness`; `cead harness` |
| host | What runs a machine or an engine: hardware, its processors, and what schedules onto them. Trusted for availability only; the model's processes cannot reach it. | `host` |
| init | PID 1 in the machine, for the whole boot. Makes the boot's key and never lets it go; signs every record. Assembles the view (task image as root, overlay, core first on PATH, descriptors), applies policy, forks and execs the harness. If the harness dies, the boot ends with no exit record: unknown. | `machine::init::Init`; `cead init` |
| integrity | The log says only what the machine signed, in the machine's order. Guaranteed by each boot's key signing every record, in a numbered sequence rooted in its report. | `spec/cead.tla` |
| interface | One of the three lines everything else is swappable between. | |
| job | One query's work: a root process and its tree. Started by `cead run`. Spans one boot, or more through recovery. | `host::job::run` |
| key | A boot's signing key: made by init, never copied out of it. | `machine::init::Key` |
| limit | A cap on one process: calls, window, bound, wall time, depth. The rlimit analogue: set in the fork-exec gap, inherited as a copy. | `host::job::Limits`; `machine::harness::Exhausted` |
| log | Every boot's records, held outside the machine: one append-only file per boot, a line per record, its encoding and signature in hex. Records in transit can be lost, delayed, replayed or forged; the log keeps only what the processor or a boot's key signed, and says why it refuses the rest. A complete boot's records are all it did, and replay its every window; an unknown boot's are true but may be partial. A job's boots link through their reports. One writer per boot: never consensus. | `host::log::Log`, `BootLog`, `Refused`; `spec/Cead/Log.lean` |
| machine | The unit: pinned kernel, core, task image, descriptors, call table, policy and model, booted in a microVM by a VMM. Booting until the log holds its report, then up. | `host::vmm::Machine<Booting \| Up>`; `machine` |
| manifest | The one file that pins a machine by content. Equal manifests are the same experiment; its hashes are the version vector. | `host::job::Manifest`, `BadManifest` |
| meter | What a process tree may spend, from KeyKOS. A child process's meter hangs below its parent's; every spend is charged to each meter above it, so a tree never outspends its root. A parent caps a child's meter in `agent`'s argv and revokes it with `kill`. What it counts is manifest policy. | `machine::meter::Meters`, `Metered`, `Spent`, `NoParent`; `spec/Cead/Meter.lean` |
| model | The machine's user: weights running on an engine, reached by the harness over TLS that every host between only relays. The machine holds no credential. | |
| operator | The human at depth 0. Types `cead` or `cead run`; never types a call. | |
| pinned | The part of the window eviction never touches: the system prompt, rendered from what was mounted. | `machine::init::prompt` |
| policy | The rows of the call table in Cedar, compiled to seccomp and Landlock, installed before exec. Permit-all is a declared policy, not an absence. | |
| process | An OS process running one harness cycle, with its own cgroup, window, shell, limits and meter; each call runs as its child. Ready, running, blocked, zombie, reaped. Started by `run` at depth 0 (process 0), `agent` below. It ends when the model replies without a command; its reply is its stdout. Each `agent` child is spawned in its own PID namespace, so `kill` reaches only its descendants. | `machine::process::Process`, `State`, `Status`; `record::ProcId` |
| processor | What a process runs on. For the machine, the CPU; for the model, the GPU, a coprocessor to the model's process. A boot sees the model's processors as virtual, like vCPUs; how the engine shares its GPU among them (batching) is its scheduler's. | |
| query | The argv of `run` or `agent`, commit-message sized; it opens its process's window. Anything longer is context, a file. | bytes in `record::Body::Report`, `Decision::Spawn` |
| report | A boot's first record: binds the boot's key to the manifest's measurement, names what started it (run, or the snapshot a fork or recovery booted from), and carries the pinned prompt and the root's query. Signed by the processor on an attested boot. Linux's TSM report. | `record::Body::Report`, `Origin`; `spec/cead.tla` |
| record | One entry the machine signs for the log, Linux audit's unit, canonically encoded. Types: report, intent (the model's turn and its command), decision, witness (how the command ended, its output's digest, what the call returned), exit (why the boot ended; the root's reply digest on a finish). A call's three share its id and process. | `record::Record`, `Body`, `Event`, `Exit`, `Signed`, `Signature`, `Digest`, `Malformed`, `Reader`, `write_frame`, `read_frame`; `spec/Cead/Record.lean` |
| rights | What a call may do to state: read, write. | `machine::process::Rights` |
| ring | A privilege layer: model processes; harness and tracer; host. | |
| scheduler | Decides what runs where: machines on hosts (Kubernetes), requests on engines (Dynamo). Trusted for availability only; needs consensus once there is more than one. | |
| shell | A process's interface to the kernel: one per process, persistent across its calls. | `machine::shell::Shell`, `Ran` |
| signer | The harness's end of init's signing pipe: numbers each record, so a boot's sequence has no gaps. | `machine::harness::Signer` |
| slice | The bytes a child receives on stdin, sealed. | |
| snapshot | The whole machine at an instant, taken between calls once the log holds every record so far. A boot from one is a **fork** (a new job; unlimited) or a **recovery** (the same job, after its boot is unknown; at most one per unknown boot; the operator's choice, manual by default). A recovery **fences** the boot it recovers: the log keeps none of that boot's records after it. | `record::Origin` |
| span | One piece of a window: system, user or assistant text. | `machine::window::Span`, `Role`, `encode`, `decode`, `NotSpans` |
| task image | The tools one task brings: a read-only OCI image with a label declaring its tools, attached at boot. | |
| tracer | eBPF in the machine's kernel, keyed by cgroup, outside the model's reach. Produces the witness. | |
| turn | What the model writes on one call: a command, or a reply without one. Logged whole. | `machine::engine::Turn` |
| verified | A record whose signature checked against its boot's key, and whose attestation this build can vouch for (trusted-host mode: unattested only): the only kind the log accepts. | `host::log::Verified`, `Forged` |
| view | What init mounts for the model: the task image as root, the context as a file, a directory for spills. | `machine::init::View` |
| VMM | What boots a machine: Cloud Hypervisor, attested on SEV-SNP or unattested on KVM; Firecracker and Virtualization.framework, unattested. Same machine, same records; only an attested boot's report is signed. | `host::vmm` |
| wait status | How a command ended, as `wait(2)` reports it: exited with a code, or signaled. | `record::WaitStatus` |
| weights | The model's program text, pinned by hash in the manifest. Part of the version vector. | |
| window | The context the model can address now: the pinned prompt, the query, then each call's turn and what it returned. Only grows; ending the process when full. The log replays it. A cache over state. | `machine::window::Window`, `Full`; `spec/Cead/Window.lean` |

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
- `Cargo.toml` is the allowlist: no new dependency without approval. Preferences: rustix, never libc directly; std and typed errors until a need appears; `serde_json` only where a wire format is JSON (Bedrock). Approved: `ed25519-dalek`, `sha2`, `serde_json`, `rustix`. Boundary crates: rustix, aya, seccompiler, landlock.
- One published crate, `cead`. When the workspace splits (core, machine, tracer, host, VMMs) members are `publish = false`.
- Host crates build on macOS: rustix with its libc backend, std, nothing Linux-specific. A Linux-only crate in the host tree is the axis being violated. Machine crates are `#![cfg(target_os = "linux")]` and use linux_raw and Linux-only crates freely.
- The core is nix-built and static.

# TLA+

- Modules are `spec/<name>.tla` with `<name>.cfg`; the system spec is `spec/cead.tla`. A layer whose state multiplies another's gets its own cfg over the same module (`spec/tree.cfg`). The commit line records the TLA+ tools version and the bounds it passed at.
- A PR that changes a protocol re-runs TLC, by hand until CI is demanded.
- Every property has a mutation TLC catches, run with a cfg holding only that property so the catch is its own.
- Committed cfgs run in about a minute; larger bounds are one-off runs recorded in the PR.
- **spec**: a formula over behaviours of a state machine. **action**: one transition; one signature. **invariant**: what every reachable state satisfies; what TLC checks. **instance**: the bounds TLC searched; a proof only up to them.

# Lean

- Lean 4 via elan, toolchain pinned in `lean-toolchain`, one lake project in `spec/`. `lake build` green before the Rust it specifies.
- No `sorry`. Proofs rest on `propext`, `Quot.sound` and `Classical.choice` only, checked with `#print axioms`: no native code (`bv_decide`, `native_decide`), so the kernel checks everything.
- Every guard has a mutation: replaced by `True`, it breaks a proof.
- `spec/Cead/Differential.lean` builds `differential`, the Lean half of every differential test.
- **spec**: an executable definition. **theorem**: a property proved of it. **differential test**: random inputs through spec and Rust, outputs compared in `cargo test`; the only tie between them.

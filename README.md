<p align="center">
  <picture>
    <source media="(prefers-color-scheme: light)" srcset="assets/lockup-light.svg">
    <img src="assets/lockup.svg" width="220" alt="cead">
  </picture><br>
  <em>cead</em> (Irish: permission; "kyad")
</p>

cead is an agent harness built as a confidential microVM.
A userspace for a model, over a kernel that enforces and witnesses,
whose evidence does not depend on who owns the hardware.

## What cead is

- **A machine for the model.**
  A pinned Linux kernel in a microVM; the model drives it through a shell.
- **The kernel enforces.**
  Each command runs as a Linux process under seccomp, Landlock and cgroups.
- **The kernel records.**
  eBPF writes what each process did, out of the model's reach.
  Most harnesses report from the process that acted; here the model's processes never touch the record.
- **The host cannot forge it.**
  On attested hardware, the processor attests what booted.
  The machine signs its records with a key the host cannot read.
  The host can stop a job or drop its records; it cannot read the job or forge them.
  Without attestation hardware, the same machine runs unattested and says so.
- **Harness design is memory-management policy.**
  The context window is a cache; state lives in files, reached through the shell.
  Forty commands in a script that prints `ok`: one line of window, forty enforced and witnessed.

Three interfaces; everything between two lines is swappable.

| Line | Interface |
|---|---|
| VMM ↔ machine | measured boot, content-addressed disks, attestation |
| kernel ↔ commands | Linux syscall ABI |
| commands ↔ model | POSIX sh, GNU flags and error text |

### Reading

- [Recursive Language Models](https://arxiv.org/abs/2512.24601) (Zhang, Kraska, Khattab)
- [Language model harnesses are compositional generalizers](https://alexzhang13.github.io/blog/2026/harness/) (Zhang, Khattab)
- [OSTEP](https://pages.cs.wisc.edu/~remzi/OSTEP/) (Arpaci-Dusseau)
- [The Datacenter as a Computer](https://web.eecs.umich.edu/~mosharaf/Readings/DC-Computer.pdf) (Barroso, Clidaras, Hölzle)
- [Capability Myths Demolished](https://srl.cs.jhu.edu/pubs/SRL2003-02.pdf) (Miller, Yee, Shapiro)
- [Robust Composition](http://www.erights.org/talks/thesis/) (Miller)
- [Prime Agent](https://www.primeintellect.ai/blog/prime-agent) ([source](https://github.com/PrimeIntellect-ai/prime-agent)) and [Sandboxes](https://www.primeintellect.ai/blog/sandboxes) (Prime Intellect)


## What cead is not

- **Not a container runtime.**
  It uses container images and schedulers; a microVM replaces the container.
- **Not a conversation.**
  Nothing carries between jobs except state in the machine.
- **Not a policy.**
  You bring your own, in Cedar; cead compiles it into kernel rules.
- **Not a new interface.**
  POSIX sh and GNU tools: the most training data, and what the kernel already enforces.
  A bespoke tool schema must be taught in every prompt and translated before it can be enforced.

## How to use cead

A **manifest** is one file that names a machine: kernel, task image, policy, VMM, model (weights, engine).

- `cead` opens the console over a manifest and its state; `run` starts a job.
- `cead run "query" < context > answer` does one job and returns; the exit code is the outcome.
- A query is commit-message sized; anything longer is a file for the model to read.

What a job does, from manifest to first command:

1. The VMM boots the kernel with two read-only disks: the core (built by nix) and the task image.
2. init makes the boot's key, which never leaves it, and sends the report; nothing runs until the log holds it.
3. init, as root, loads the eBPF programs and compiles the policy into seccomp and Landlock.
4. init mounts the view: the task image as root, the core first on PATH, one descriptor per grant.
5. init forks the harness, which spawns the root process: policy attached, an unprivileged uid, the shell.
   Every child inherits the policy; no syscall loosens it, and no model process holds CAP_BPF.
6. The harness sends the engine the query and a system prompt rendered from what it mounted.
7. The model writes its first command.

## Dependencies

| Layer | Stack |
|---|---|
| language | Rust |
| kernel | Linux: cgroup v2, seccomp, Landlock, vsock; eBPF via aya |
| shell and tools | brush, uutils, SQLite |
| policy | Cedar |
| VMMs | Cloud Hypervisor (SEV-SNP on KVM); Firecracker and Virtualization.framework, unattested |
| attestation | AMD SEV-SNP, Linux TSM reports (configfs-tsm), virtee/sev |
| images and build | OCI images, nix |

## Deployment

The machine is the unit of scale. Work fans out three ways:

| Mechanism | Who spawns | When | What |
|---|---|---|---|
| scale-out | operator | before a job | N machines from one manifest |
| fork | operator | mid-job | K machines from one snapshot |
| `agent` | the model | whenever it decides | a sub-agent process in the machine |

### Identity

- **The machine is the boundary.**
  Users, roles and sessions collapse to one question: which machine.
- **A manifest answers it by hash.**
  Machines from one manifest start identical.
- **Where you stand says who you are.**
  The operator runs the CLI on the host; the model is an unprivileged user in the machine.
- **Access is granted; content is discovered.**
  cead grants every file, socket and database; a child gets no more than its parent.
- **Authority is per tool.**
  `grep` does what its arguments say; `python` can do anything its process may.
  The tool's class sets its policy and how to read its trace.
- **Long-lived keys stay on the host.**
  The machine holds its boot's signing key and a job-scoped token for the model.

### Hosts

- Cloud Hypervisor: attested on bare-metal AMD EPYC with SEV-SNP; unattested on any KVM host.
- Firecracker and Virtualization.framework: unattested.
- The model runs wherever the manifest's engine is: a hosted API or our own.
- A scheduler places machines on hosts; it never sees inside one.

### Network

- The model's processes have no network.
- The machine reaches the host only over vsock.
- The host relays inference and the machine's records to the log.
- Inference is encrypted end to end to our own engine; a hosted API goes through a gateway on the host.

### Workloads

- **Build.**
  A task's tools are a read-only OCI image.
- **Each call.**
  The harness sends the engine the window: system prompt, query, each output so far, cut at a cap.
  It runs the command that comes back; output past the cap spills to a file.
- **Sub-agents.**
  `agent` spawns a child process: a slice on stdin, a meter under its parent's, its own window.
  The shell composes it (`&`, `wait`, `kill`); its answer stays in a file or variable until read.
- **Fork.**
  A snapshot boots another machine with a new key.
  A fork starts a new job; a recovery continues one whose boot was lost, at most once.
- **Ending.**
  A process ends when the model replies without a command; the reply is its stdout.
  Ending kills running sub-agents; `wait` first to keep them.
  When the root process ends, the job ends and the machine is gone.

### Data

- State is files in the machine, databases included, reached through the shell; a snapshot captures all of it.
- State leaves only on purpose: the answer on stdout, an exported snapshot or checkout.

### Observability

- eBPF records which programs start, which files are read, and each request to the engine.
- Keyed by cgroup: each action is traced to the command that caused it, however many processes it spawned.
- The log holds each boot's records, in order:
  its report; per call an intent, a decision, and a witness if allowed; its exit, carrying the answer.
- The console reads it live, during a job and after.

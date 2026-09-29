//! The machine: init, the harness and the model's processes, inside one boot.

/// init: PID 1 for the whole boot. The boot's key is made here and never
/// leaves this process.
pub(crate) mod init {
    use crate::record::{Boot, Signature};
    use std::fs::File;
    use std::path::PathBuf;
    use std::process::Child;

    /// The boot's signing key. Owned by init alone: never cloned, never sent,
    /// never in the harness, which init starts by exec so no copy of this
    /// memory reaches it. Dropped, and zeroed, when the boot ends.
    pub(crate) struct Key([u8; 32]);

    impl Key {
        /// A fresh key for a fresh boot.
        pub(crate) fn generate() -> Key {
            todo!()
        }

        /// The public half, which names the boot.
        pub(crate) fn boot(&self) -> Boot {
            todo!()
        }

        pub(crate) fn sign(&self, bytes: &[u8]) -> Signature {
            todo!()
        }
    }

    /// What init mounts for the model: the task image as root, the context as
    /// a file, a directory for spills. Owned by init; the harness gets paths.
    pub(crate) struct View {
        root: PathBuf,
        context: PathBuf,
        spill: PathBuf,
    }

    /// init's state: the key, the stream to the log over vsock, and the
    /// harness once started.
    pub(crate) struct Init {
        key: Key,
        log: File,
        harness: Option<Child>,
    }

    impl Init {
        /// Makes the key, signs and sends the report, and waits for the log to
        /// acknowledge it: nothing runs before the log holds the report.
        pub(crate) fn boot() -> std::io::Result<Init> {
            todo!()
        }

        /// Assembles the view (mounts, policy, the context file).
        pub(crate) fn assemble(&mut self) -> std::io::Result<View> {
            todo!()
        }

        /// Forks and execs `/proc/self/exe harness`, then signs what it sends
        /// and forwards the log's acknowledgments, until it exits. If it exits
        /// without its exit record acknowledged, the machine powers off with
        /// none: the boot is unknown.
        pub(crate) fn serve(self, view: View) -> ! {
            todo!()
        }
    }

    /// The pinned prompt, rendered from what was mounted.
    pub(crate) fn prompt(view: &View) -> Vec<u8> {
        todo!()
    }
}

/// The harness: the model's kernel. One signature per action of
/// `spec/cead.tla`'s layers 1 and 3.
pub(crate) mod harness {
    use super::engine::{Engine, Turn};
    use super::meter::Meters;
    use super::process::{Process, Status};
    use super::shell::Ran;
    use crate::host::job::Limits;
    use crate::record::{Body, Boot, CallId, ProcId};
    use std::fs::File;
    use std::time::Instant;

    /// The harness's end of init's signing pipe. Numbers each record, so a
    /// boot's sequence has no gaps by construction. Owned by the harness.
    pub(crate) struct Signer {
        pipe: File,
        boot: Boot,
        next: u64,
    }

    impl Signer {
        /// Numbers the body and hands it to init to sign and send; returns
        /// its place in the sequence.
        pub(crate) fn send(&mut self, body: Body) -> std::io::Result<u64> {
            todo!()
        }

        /// Blocks until the log has acknowledged the record at `seq`.
        pub(crate) fn acknowledged(&mut self, seq: u64) -> std::io::Result<()> {
            todo!()
        }
    }

    /// Why a live process was ended by the harness rather than by its reply.
    pub(crate) enum Exhausted {
        Meter,
        Limit,
    }

    /// Every process of the boot, their meters, and the channels to init and
    /// the engine. Owned by the harness process; dropped when the boot exits.
    pub(crate) struct Harness {
        signer: Signer,
        engine: Engine,
        procs: Vec<Process>,
        meters: Meters,
        next_call: u64,
        limits: Limits,
        started: Instant,
    }

    impl Harness {
        /// Starts the root process over the view init assembled.
        pub(crate) fn start(signer: Signer, engine: Engine, limits: Limits) -> Harness {
            todo!()
        }

        /// `Dispatch`: a ready process gets a processor; its window goes to
        /// the engine, and its turn comes back.
        pub(crate) fn dispatch(&mut self, p: ProcId) -> std::io::Result<Turn> {
            todo!()
        }

        /// `Issue`: the turn has a command. Charges every meter up to the
        /// root, sends the intent, and blocks the process on its decision.
        pub(crate) fn issue(
            &mut self,
            p: ProcId,
            turn: Vec<u8>,
            command: Vec<u8>,
        ) -> Result<CallId, Exhausted> {
            todo!()
        }

        /// `Decide`: once the log holds the intent, checks the call against
        /// policy and sends the decision. Deny returns to the model; allow
        /// starts the command (`agent` spawns, `kill` ends a child's tree).
        pub(crate) fn decide(&mut self, call: CallId) -> std::io::Result<()> {
            todo!()
        }

        /// `Witness`: the command ended; sends the witness with what the call
        /// returned, and the process is ready again.
        pub(crate) fn witness(&mut self, call: CallId, ran: Ran) -> std::io::Result<()> {
            todo!()
        }

        /// `Finish`: the turn has no command. The process ends; its reply is
        /// its stdout; its live descendants are killed.
        pub(crate) fn finish(&mut self, p: ProcId, reply: Vec<u8>) {
            todo!()
        }

        /// `Exhaust`: the process cannot pay for its call, or hit a limit.
        pub(crate) fn exhaust(&mut self, p: ProcId, why: Exhausted) {
            todo!()
        }

        /// `Timeout`: the job's wall time is spent; the root ends, killing the
        /// tree.
        pub(crate) fn timeout(&mut self) {
            todo!()
        }

        /// `ReapChild`: an ended child is reaped; a parent's foreground
        /// `agent` waiting on it can end.
        pub(crate) fn reap_child(&mut self, q: ProcId) {
            todo!()
        }

        /// `Reap`: the root has ended and every command is witnessed. Sends
        /// the exit record; the harness is done.
        pub(crate) fn reap(self) -> std::io::Result<Status> {
            todo!()
        }

        /// The cycle: dispatch, then issue, finish or exhaust, until `reap`.
        pub(crate) fn run(self) -> std::io::Result<Status> {
            todo!()
        }
    }
}

/// A model's process, as the harness holds it.
pub(crate) mod process {
    use super::shell::Shell;
    use super::window::Window;
    use crate::record::{CallId, ProcId};
    use std::path::PathBuf;

    /// What a process may do to state. A child's rights never exceed its
    /// parent's.
    pub(crate) struct Rights {
        read: Vec<PathBuf>,
        write: Vec<PathBuf>,
    }

    /// A child asked for more than its parent holds: rights amplification,
    /// which attenuation forbids.
    pub(crate) struct Amplification;

    impl Rights {
        pub(crate) fn attenuate(&self, to: Rights) -> Result<Rights, Amplification> {
            todo!()
        }
    }

    /// What a blocked process waits on: property 18 of the spec, by
    /// construction. Each holds the model's turn, which enters the window
    /// with what the call returns.
    pub(crate) enum Blocked {
        /// Its intent, until the log holds the record at `seq` and the
        /// harness decides on `command`.
        Deciding {
            call: CallId,
            seq: u64,
            turn: Vec<u8>,
            command: Vec<u8>,
        },
        /// Its command, until it ends.
        Running { call: CallId, turn: Vec<u8> },
        /// Its foreground `agent`, until the child it spawned is reaped.
        Waiting {
            call: CallId,
            turn: Vec<u8>,
            child: ProcId,
        },
    }

    /// Why a process ended.
    pub(crate) enum Status {
        /// It replied without a command; the reply is its stdout.
        Finish(Vec<u8>),
        Meter,
        Limit,
        Timeout,
        /// Killed by an ancestor, or when one ended.
        Killed { by: ProcId },
    }

    pub(crate) enum State {
        Ready,
        Running,
        Blocked(Blocked),
        Zombie(Status),
        Reaped,
    }

    /// One process: its place in the tree, its limits' counters, its window
    /// and shell. Owned by the harness's table; its shell and cgroup go when
    /// it is reaped.
    pub(crate) struct Process {
        id: ProcId,
        parent: Option<ProcId>,
        depth: u32,
        calls: u32,
        rights: Rights,
        state: State,
        window: Window,
        shell: Shell,
    }
}

/// Meters, from KeyKOS. Mirrors `spec/Cead/Meter.lean`: `charge` and `spawn`
/// are its definitions, and the differential test holds them to it.
pub(crate) mod meter {
    use crate::record::ProcId;

    /// One process's meter: what it was given, what remains, what it spent.
    #[derive(Debug)]
    struct Metered {
        parent: Option<usize>,
        cap: u64,
        meter: u64,
        calls: u64,
    }

    /// Every process's meter, indexed by process number. A child is appended,
    /// so its parent's number is smaller. Owned by the harness.
    #[derive(Debug)]
    pub(crate) struct Meters(Vec<Metered>);

    /// Some meter from the process up to the root is spent.
    #[derive(Debug)]
    pub(crate) struct Spent;

    /// A spawn under a process that does not exist.
    #[derive(Debug)]
    pub(crate) struct NoParent;

    impl Meters {
        pub(crate) fn root(cap: u64) -> Meters {
            Meters(vec![Metered { parent: None, cap, meter: cap, calls: 0 }])
        }

        /// A child of `parent` with meter `cap`, numbered next.
        pub(crate) fn spawn(&mut self, parent: &ProcId, cap: u64) -> Result<ProcId, NoParent> {
            let parent = usize::try_from(parent.get()).map_err(|_| NoParent)?;
            if parent >= self.0.len() {
                return Err(NoParent);
            }
            self.0.push(Metered { parent: Some(parent), cap, meter: cap, calls: 0 });
            Ok(ProcId::new(self.0.len() as u64 - 1))
        }

        /// A call by `q`: one unit from every meter up to the root, or none.
        pub(crate) fn charge(&mut self, q: &ProcId) -> Result<(), Spent> {
            let q = usize::try_from(q.get()).map_err(|_| Spent)?;
            if q >= self.0.len() {
                return Err(Spent);
            }
            let chain = self.chain(q);
            if chain.iter().any(|&a| self.0[a].meter == 0) {
                return Err(Spent);
            }
            for a in chain {
                self.0[a].meter -= 1;
            }
            self.0[q].calls += 1;
            Ok(())
        }

        /// `q`, its parent, and so on up to the root.
        fn chain(&self, q: usize) -> Vec<usize> {
            let mut chain = vec![q];
            let mut at = q;
            while let Some(parent) = self.0[at].parent.filter(|&p| p < at) {
                chain.push(parent);
                at = parent;
            }
            chain
        }
    }

    #[cfg(test)]
    mod tests {
        use super::Meters;
        use crate::record::ProcId;
        use crate::record::tests::differential;

        /// Lean's random spawns and charges, replayed: every verdict and every
        /// meter after it agree.
        #[test]
        fn meters_match_lean() {
            let lines = differential(&["meter", "300", "40", "2"]);
            let mut meters = Meters::root(0);
            let (mut ok, mut refused) = (0, 0);
            for line in lines.lines() {
                // `spawn PA CAP VERDICT [METERS]`, `charge Q VERDICT [METERS]`, `root CAP`
                let words: Vec<&str> = line.splitn(4, ' ').collect();
                let n = |i: usize| words[i].parse::<u64>().expect("a number");
                let (verdict, expected) = match words[0] {
                    "root" => {
                        meters = Meters::root(n(1));
                        continue;
                    }
                    "spawn" => {
                        let rest: Vec<&str> = words[3].splitn(2, ' ').collect();
                        let got = meters.spawn(&ProcId::new(n(1)), n(2)).is_ok();
                        (got == (rest[0] == "ok"), rest[1])
                    }
                    "charge" => {
                        let rest: Vec<&str> = line.splitn(4, ' ').skip(2).collect();
                        let got = meters.charge(&ProcId::new(n(1))).is_ok();
                        (got == (rest[0] == "ok"), rest[1])
                    }
                    other => panic!("unknown operation {other}"),
                };
                assert!(verdict, "verdict differs: {line}");
                let now: Vec<String> = meters.0.iter().map(|m| m.meter.to_string()).collect();
                assert_eq!(format!("[{}]", now.join(", ")), expected, "{line}");
                if line.contains(" ok ") { ok += 1 } else { refused += 1 }
            }
            assert!(ok > 1000 && refused > 1000, "{ok} ok, {refused} refused");
        }
    }
}

/// A process's window. Mirrors `spec/Cead/Window.lean`: it only grows at its
/// end, and the log replays it.
pub(crate) mod window {
    use crate::record::{Boot, ProcId, Record};

    pub(crate) enum Role {
        System,
        User,
        Assistant,
    }

    /// One span of a window.
    pub(crate) struct Span {
        role: Role,
        text: Vec<u8>,
    }

    /// The pinned prompt, the query, then each call's turn and what it
    /// returned. Owned by its process; dropped when the process is reaped.
    pub(crate) struct Window {
        spans: Vec<Span>,
        len: usize,
        limit: usize,
    }

    /// The next span would pass the window limit: the process ends with
    /// `limit`.
    pub(crate) struct Full;

    impl Window {
        pub(crate) fn open(prompt: Vec<u8>, query: Vec<u8>, limit: usize) -> Window {
            todo!()
        }

        /// Appends one call: the model's turn and what the call returned.
        pub(crate) fn push(&mut self, turn: Vec<u8>, returned: Vec<u8>) -> Result<(), Full> {
            todo!()
        }

        pub(crate) fn spans(&self) -> &[Span] {
            todo!()
        }
    }

    /// Process `proc`'s window as the log's records replay it.
    pub(crate) fn replay(records: &[Record], boot: &Boot, proc: ProcId) -> Option<Vec<Span>> {
        todo!()
    }
}

/// What a call returns to the model: the output whole, or where it spilled.
pub(crate) mod bounded {
    use crate::record::WaitStatus;
    use std::path::{Path, PathBuf};

    /// Output admitted to the window only if it fits the bound; otherwise
    /// none of it, and the model reads the spill file like any other state.
    pub(crate) enum Bounded {
        Fits(Vec<u8>),
        Spilled { path: PathBuf, size: u64 },
    }

    impl Bounded {
        /// Admits `output` whole if it fits `bound`, else writes it under
        /// `spill`.
        pub(crate) fn admit(output: Vec<u8>, bound: usize, spill: &Path) -> std::io::Result<Bounded> {
            todo!()
        }

        /// The bytes the call returns: the exit status, then the output or
        /// the spill's path and size.
        pub(crate) fn returned(&self, status: &WaitStatus) -> Vec<u8> {
            todo!()
        }
    }
}

/// A process's shell: the model's interface to the kernel.
pub(crate) mod shell {
    use crate::record::WaitStatus;
    use std::process::Child;

    /// A command that ended: how, and everything it wrote.
    pub(crate) struct Ran {
        status: WaitStatus,
        output: Vec<u8>,
    }

    /// One shell per process, persistent across its calls. Owned by the
    /// process; killed with it.
    pub(crate) struct Shell {
        child: Child,
    }

    impl Shell {
        pub(crate) fn spawn() -> std::io::Result<Shell> {
            todo!()
        }

        /// Runs one command to its end.
        pub(crate) fn run(&mut self, command: &[u8]) -> std::io::Result<Ran> {
            todo!()
        }
    }
}

/// The engine as the machine reaches it: over vsock, through the host's
/// gateway.
pub(crate) mod engine {
    use super::window::Window;
    use std::fs::File;

    /// What the model wrote.
    pub(crate) enum Turn {
        /// The whole turn, and the command taken from it.
        Command { turn: Vec<u8>, command: Vec<u8> },
        /// No command: the process's reply.
        Reply(Vec<u8>),
    }

    /// The machine's stream to the gateway. Holds no credential.
    pub(crate) struct Engine {
        vsock: File,
    }

    impl Engine {
        /// Sends the window, returns the model's turn.
        pub(crate) fn infer(&mut self, window: &Window) -> std::io::Result<Turn> {
            todo!()
        }
    }
}

/// `agent`: the call cead adds, run by a model's shell.
pub(crate) mod agent {
    use std::process::ExitCode;

    /// Asks the harness, over a descriptor it inherited, to spawn a child with
    /// this query and stdin as its slice; writes the child's reply to stdout.
    /// The exit code says how the child ended.
    pub(crate) fn agent(query: Vec<u8>) -> ExitCode {
        todo!()
    }
}

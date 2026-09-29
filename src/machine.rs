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
        /// A fresh key for a fresh boot, from the kernel's random source.
        pub(crate) fn generate() -> std::io::Result<Key> {
            use std::io::Read;
            let mut secret = [0; 32];
            File::open("/dev/urandom")?.read_exact(&mut secret)?;
            Ok(Key(secret))
        }

        /// The public half, which names the boot.
        pub(crate) fn boot(&self) -> Boot {
            Boot::of(&self.0)
        }

        pub(crate) fn sign(&self, bytes: &[u8]) -> Signature {
            crate::record::sign(&self.0, bytes)
        }
    }

    impl Drop for Key {
        /// The secret does not outlive the boot's init.
        fn drop(&mut self) {
            self.0.fill(0);
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
    use crate::record::{Body, Boot, Decision, Event, ProcId, Record};

    #[derive(Debug, Clone, PartialEq, Eq)]
    pub(crate) enum Role {
        System,
        User,
        Assistant,
    }

    /// One span of a window.
    #[derive(Debug, Clone, PartialEq, Eq)]
    pub(crate) struct Span {
        role: Role,
        text: Vec<u8>,
    }

    impl Span {
        pub(crate) fn role(&self) -> &Role {
            &self.role
        }

        pub(crate) fn text(&self) -> &[u8] {
            &self.text
        }
    }

    /// The pinned prompt, the query, then each call's turn and what it
    /// returned. Owned by its process; dropped when the process is reaped.
    #[derive(Debug)]
    pub(crate) struct Window {
        spans: Vec<Span>,
        len: usize,
        limit: usize,
    }

    /// The next call would pass the window limit: the process ends with
    /// `limit`.
    #[derive(Debug)]
    pub(crate) struct Full;

    impl Window {
        pub(crate) fn open(prompt: Vec<u8>, query: Vec<u8>, limit: usize) -> Window {
            let len = prompt.len() + query.len();
            let spans = vec![Span { role: Role::System, text: prompt }, Span { role: Role::User, text: query }];
            Window { spans, len, limit }
        }

        /// Appends one call, its turn and what it returned, if both fit.
        pub(crate) fn push(&mut self, turn: Vec<u8>, returned: Vec<u8>) -> Result<(), Full> {
            let len = self.len + turn.len() + returned.len();
            if len > self.limit {
                return Err(Full);
            }
            self.len = len;
            self.spans.push(Span { role: Role::Assistant, text: turn });
            self.spans.push(Span { role: Role::User, text: returned });
            Ok(())
        }

        pub(crate) fn spans(&self) -> &[Span] {
            &self.spans
        }
    }

    /// Spans as they cross to the gateway: a u64 count, then each span's role
    /// tag (0 system, 1 user, 2 assistant) and its text as u64 length and bytes.
    pub(crate) fn encode(spans: &[Span]) -> Vec<u8> {
        let mut out = (spans.len() as u64).to_be_bytes().to_vec();
        for span in spans {
            out.push(match span.role {
                Role::System => 0,
                Role::User => 1,
                Role::Assistant => 2,
            });
            out.extend_from_slice(&(span.text.len() as u64).to_be_bytes());
            out.extend_from_slice(&span.text);
        }
        out
    }

    /// Bytes that are no spans' encoding.
    #[derive(Debug)]
    pub(crate) struct NotSpans;

    pub(crate) fn decode(bytes: &[u8]) -> Result<Vec<Span>, NotSpans> {
        let mut r = crate::record::Reader::new(bytes);
        let count = r.u64().map_err(|_| NotSpans)?;
        let mut spans = Vec::new();
        for _ in 0..count {
            let role = match r.tag().map_err(|_| NotSpans)? {
                0 => Role::System,
                1 => Role::User,
                2 => Role::Assistant,
                _ => return Err(NotSpans),
            };
            spans.push(Span { role, text: r.bytes().map_err(|_| NotSpans)? });
        }
        if r.is_empty() { Ok(spans) } else { Err(NotSpans) }
    }

    /// Process `proc`'s window as the log's records replay it: `replay` in
    /// `spec/Cead/Window.lean`, definition for definition.
    pub(crate) fn replay(records: &[Record], boot: &Boot, proc: &ProcId) -> Option<Vec<Span>> {
        let mine = || records.iter().filter(|r| r.boot() == boot).map(Record::body);
        let (prompt, root_query) = mine().find_map(|b| match b {
            Body::Report { prompt, query, .. } => Some((prompt, query)),
            _ => None,
        })?;
        let query = if *proc == ProcId::ROOT {
            root_query
        } else {
            mine().find_map(|b| match b {
                Body::Call { event: Event::Decision(Decision::Spawn { child, query }), .. }
                    if child == proc =>
                {
                    Some(query)
                }
                _ => None,
            })?
        };
        let mut ids: Vec<u64> = mine()
            .filter_map(|b| match b {
                Body::Call { id, proc: p, event: Event::Intent { .. } } if p == proc => Some(id.get()),
                _ => None,
            })
            .collect();
        ids.sort();
        let call = |i: u64| {
            let turn = mine().find_map(|b| match b {
                Body::Call { id, event: Event::Intent { turn, .. }, .. } if id.get() == i => Some(turn),
                _ => None,
            })?;
            let returned = mine().find_map(|b| match b {
                Body::Call { id, event: Event::Decision(Decision::Deny { returned }), .. }
                | Body::Call { id, event: Event::Witness { returned, .. }, .. }
                    if id.get() == i =>
                {
                    Some(returned)
                }
                _ => None,
            })?;
            Some((turn.clone(), returned.clone()))
        };
        let mut spans = vec![
            Span { role: Role::System, text: prompt.clone() },
            Span { role: Role::User, text: query.clone() },
        ];
        for (turn, returned) in ids.into_iter().filter_map(call) {
            spans.push(Span { role: Role::Assistant, text: turn });
            spans.push(Span { role: Role::User, text: returned });
        }
        Some(spans)
    }

    #[cfg(test)]
    mod tests {
        use super::{Role, replay};
        use crate::record::tests::differential;
        use crate::record::{
            Attestation, Body, Boot, CallId, Decision, Digest, Event, Origin, ProcId, Record, WaitStatus,
        };

        /// xorshift64: a seeded source of small random choices, no dependency.
        struct Rng(u64);
        impl Rng {
            fn below(&mut self, n: u64) -> u64 {
                self.0 ^= self.0 << 13;
                self.0 ^= self.0 >> 7;
                self.0 ^= self.0 << 17;
                self.0 % n
            }
            fn bytes(&mut self) -> Vec<u8> {
                let n = self.below(4);
                (0..n).map(|_| b'a' + self.below(26) as u8).collect()
            }
        }

        /// A random log over two boots, three processes and a few call ids:
        /// reports, spawns, intents, denies and witnesses, in any order.
        fn log(rng: &mut Rng, boots: &[Boot]) -> Vec<Record> {
            (0..rng.below(24))
                .map(|seq| {
                    let boot = boots[rng.below(2) as usize].clone();
                    let (id, proc) = (CallId::new(rng.below(4)), ProcId::new(rng.below(3)));
                    let event = match rng.below(5) {
                        0 => Event::Intent { turn: rng.bytes(), command: rng.bytes() },
                        1 => Event::Decision(Decision::Deny { returned: rng.bytes() }),
                        2 => Event::Decision(Decision::Spawn { child: ProcId::new(rng.below(3)), query: rng.bytes() }),
                        3 => Event::Witness { status: WaitStatus::Exited(0), output: Digest::new([0; 32]), returned: rng.bytes() },
                        _ => {
                            let body = Body::Report {
                                origin: Origin::Run,
                                measurement: vec![],
                                attestation: Attestation::Unattested,
                                prompt: rng.bytes(),
                                query: rng.bytes(),
                            };
                            return Record::new(boot, seq, body);
                        }
                    };
                    Record::new(boot, seq, Body::Call { id, proc, event })
                })
                .collect()
        }

        /// A window only grows at its end, and refuses the call that would pass
        /// its limit, leaving itself as it was.
        #[test]
        fn window_grows_until_full() {
            let mut w = super::Window::open(b"pinned".to_vec(), b"query".to_vec(), 20);
            let before = w.spans().to_vec();
            w.push(b"ls".to_vec(), b"a b".to_vec()).expect("fits");
            assert_eq!(&w.spans()[..before.len()], &before[..]);
            let full = w.spans().to_vec();
            assert!(w.push(b"cat big".to_vec(), b"x".to_vec()).is_err());
            assert_eq!(w.spans(), &full[..]);
        }

        /// Lean's `replay` and Rust's agree on every process of random logs.
        #[test]
        fn replay_matches_lean() {
            let dir = std::env::temp_dir().join(format!("cead-replay-{}", std::process::id()));
            std::fs::create_dir_all(&dir).expect("temp dir");
            let boots = [Boot::new([1; 32]), Boot::new([2; 32])];
            let mut rng = Rng(0x9e37_79b9_7f4a_7c15);
            let mut windows = 0;
            for n in 0..200 {
                let records = log(&mut rng, &boots);
                let path = dir.join(format!("{n}.hex"));
                let hex = |b: &[u8]| b.iter().map(|x| format!("{x:02x}")).collect::<String>();
                let lines: Vec<String> = records.iter().map(|r| hex(&r.encode())).collect();
                std::fs::write(&path, lines.join("\n") + "\n").expect("write log");
                for proc in 0..3 {
                    let lean = differential(&["replay", path.to_str().expect("utf-8"), &hex(boots[0].bytes()), &proc.to_string()]);
                    let rust = replay(&records, &boots[0], &ProcId::new(proc));
                    let rendered = rust.map(|spans| {
                        spans
                            .iter()
                            .map(|s| {
                                let role = match s.role() { Role::System => "system", Role::User => "user", Role::Assistant => "assistant" };
                                format!("{role} {}\n", hex(s.text()))
                            })
                            .collect::<String>()
                    });
                    match rendered {
                        Some(r) => {
                            windows += 1;
                            assert_eq!(r, lean, "log {n}, process {proc}");
                        }
                        None => assert_eq!(lean, "", "log {n}, process {proc}: Lean replays, Rust does not"),
                    }
                }
            }
            assert!(windows > 100, "{windows} windows replayed");
        }
    }
}

/// What a call returns to the model: the output whole, or where it spilled.
pub(crate) mod bounded {
    use crate::record::WaitStatus;
    use std::path::{Path, PathBuf};

    /// Output admitted to the window only if it fits the bound and is text
    /// (UTF-8, as the engine's API requires, so the window holds exactly the
    /// bytes the log replays); otherwise none of it, and the model reads the
    /// spill file like any other state.
    #[derive(Debug, PartialEq, Eq)]
    pub(crate) enum Bounded {
        Fits(Vec<u8>),
        Spilled { path: PathBuf, size: u64 },
    }

    impl Bounded {
        /// Admits `output` whole if it fits `bound` and is text, else writes it
        /// to `spill`.
        pub(crate) fn admit(output: Vec<u8>, bound: usize, spill: &Path) -> std::io::Result<Bounded> {
            if output.len() <= bound && std::str::from_utf8(&output).is_ok() {
                return Ok(Bounded::Fits(output));
            }
            std::fs::write(spill, &output)?;
            Ok(Bounded::Spilled { path: spill.to_path_buf(), size: output.len() as u64 })
        }

        /// The bytes the call returns: the output then its exit status, or the
        /// exit status with the spill's size and path. The same shape on every
        /// task.
        pub(crate) fn returned(&self, status: &WaitStatus) -> Vec<u8> {
            let status = match status {
                WaitStatus::Exited(code) => format!("exit {code}"),
                WaitStatus::Signaled(signal) => format!("signal {signal}"),
            };
            match self {
                Bounded::Fits(output) => {
                    let mut out = output.clone();
                    if !out.is_empty() && !out.ends_with(b"\n") {
                        out.push(b'\n');
                    }
                    out.extend_from_slice(status.as_bytes());
                    out
                }
                Bounded::Spilled { path, size } => {
                    format!("{status} · {size} bytes → {}", path.display()).into_bytes()
                }
            }
        }
    }

    #[cfg(test)]
    mod tests {
        use super::Bounded;
        use crate::record::WaitStatus;

        /// Output at the bound enters whole; one byte more enters not at all,
        /// and the spill file holds every byte.
        #[test]
        fn all_or_nothing() {
            let spill = std::env::temp_dir().join(format!("cead-spill-{}", std::process::id()));
            let fits = Bounded::admit(b"abcd".to_vec(), 4, &spill).expect("admit");
            assert_eq!(fits.returned(&WaitStatus::Exited(0)), b"abcd\nexit 0");
            let over = Bounded::admit(b"abcde".to_vec(), 4, &spill).expect("admit");
            assert_eq!(std::fs::read(&spill).expect("spilled"), b"abcde");
            let returned = String::from_utf8(over.returned(&WaitStatus::Signaled(9))).expect("utf-8");
            assert_eq!(returned, format!("signal 9 · 5 bytes → {}", spill.display()));
            assert_eq!(Bounded::admit(vec![], 0, &spill).expect("admit").returned(&WaitStatus::Exited(1)), b"exit 1");
            let binary = Bounded::admit(vec![0xff, 0xfe], 64, &spill).expect("admit");
            assert!(matches!(binary, Bounded::Spilled { size: 2, .. }), "bytes that are not text spill");
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

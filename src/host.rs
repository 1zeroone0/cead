//! The host: the operator's side. Boots machines, keeps the log, relays
//! inference. Trusted for availability only.

/// `cead run`: one job, from manifest to answer.
pub(crate) mod job {
    use std::path::PathBuf;
    use std::process::ExitCode;

    /// The one file that pins a machine by content. Owned by the job; dropped
    /// when it ends.
    pub(crate) struct Manifest {
        kernel: PathBuf,
        image: PathBuf,
        model: String,
        limits: Limits,
    }

    /// Caps on one process, set when it is spawned and inherited as a copy.
    pub(crate) struct Limits {
        calls: u32,
        window: usize,
        bound: usize,
        wall: std::time::Duration,
        depth: u32,
        meter: u64,
    }

    /// A manifest that does not load.
    pub(crate) struct BadManifest(String);

    impl Manifest {
        pub(crate) fn load(path: &std::path::Path) -> Result<Manifest, BadManifest> {
            todo!()
        }
    }

    /// Boots the machine, keeps its records, relays its inference, and returns
    /// the root's reply on stdout once the log holds the exit record. The exit
    /// code is the outcome.
    pub(crate) fn run(manifest: Manifest, query: Vec<u8>, context: Vec<u8>) -> ExitCode {
        todo!()
    }
}

/// The log: every boot's records, held outside the machine. `spec/cead.tla`'s
/// `Arrive` and `spec/Cead/Log.lean`'s `accept`.
pub(crate) mod log {
    use crate::record::{Attestation, Body, Boot, Exit, Origin, Record, Signature, Signed};
    use std::collections::{BTreeSet, HashMap};
    use std::fs::File;
    use std::io::Write;
    use std::path::PathBuf;

    /// A record whose signature checked against its boot's key and, for a
    /// report, whose attestation this build can vouch for: the only kind
    /// `accept` takes. Trusted-host mode only: a report must say
    /// `Unattested`, since checking an SNP report is the confidential
    /// machine's PR.
    #[derive(Debug)]
    pub(crate) struct Verified {
        record: Record,
        bytes: Vec<u8>,
        signature: Signature,
    }

    /// A record signed by no one it names, malformed, or attested in a way
    /// this build cannot check.
    #[derive(Debug)]
    pub(crate) struct Forged;

    impl Verified {
        pub(crate) fn verify(signed: Signed) -> Result<Verified, Forged> {
            let record = Record::decode(signed.bytes()).map_err(|_| Forged)?;
            if let Body::Report { attestation: Attestation::Snp(_), .. } = record.body() {
                return Err(Forged);
            }
            if !record.boot().verifies(signed.bytes(), signed.signature()) {
                return Err(Forged);
            }
            let (bytes, signature) = signed.into_parts();
            Ok(Verified { record, bytes, signature })
        }

        /// A record taken as verified, for tests of what follows verification.
        #[cfg(test)]
        pub(crate) fn assume(record: Record) -> Verified {
            let bytes = record.encode();
            Verified { record, bytes, signature: Signature::new([0; 64]) }
        }
    }

    /// One file per boot, a line per kept record: its encoding and signature,
    /// in hex. The format `spec/Cead/Differential.lean`'s `replay` reads.
    /// Owned by the operator's `cead` for the life of the job.
    pub(crate) struct Log {
        dir: PathBuf,
        boots: HashMap<Boot, BootLog>,
    }

    /// What the log knows of one boot: its file and the facts `accept` asks.
    struct BootLog {
        file: File,
        seqs: BTreeSet<u64>,
        exited: bool,
        recovered: bool,
    }

    /// Why the log kept nothing: `Admits` in `spec/Cead/Log.lean`, case by case.
    #[derive(Debug, PartialEq, Eq)]
    pub(crate) enum Refused {
        /// Its place in the boot's sequence is taken: first wins.
        Taken,
        /// A report not first in its sequence, or another record at or before
        /// the report's place.
        OutOfPlace,
        /// A record whose boot's report the log does not hold.
        Unvouched,
        /// A fork or recovery naming a record the log does not hold.
        Unrooted,
        /// A recovery of a boot that exited or is already recovered.
        Settled,
        /// A record of a boot a recovery has fenced.
        Fenced,
        /// The log could not write it: nothing kept, nothing acknowledged, so
        /// the machine sends it again.
        Unwritten,
    }

    impl Log {
        pub(crate) fn open(dir: PathBuf) -> std::io::Result<Log> {
            std::fs::create_dir_all(&dir)?;
            Ok(Log { dir, boots: HashMap::new() })
        }

        fn logged(&self, boot: &Boot, seq: u64) -> bool {
            self.boots.get(boot).is_some_and(|b| b.seqs.contains(&seq))
        }

        fn settled(&self, boot: &Boot) -> bool {
            self.boots.get(boot).is_some_and(|b| b.exited || b.recovered)
        }

        /// Keeps the record, or says why not. Keeping it acknowledges it.
        pub(crate) fn accept(&mut self, v: Verified) -> Result<(), Refused> {
            let (boot, seq) = (v.record.boot(), v.record.seq());
            if self.logged(boot, seq) {
                return Err(Refused::Taken);
            }
            match v.record.body() {
                Body::Report { origin, .. } => {
                    if seq != 1 {
                        return Err(Refused::OutOfPlace);
                    }
                    match origin {
                        Origin::Run => {}
                        Origin::Fork { boot: from, last } => {
                            if !self.logged(from, *last) {
                                return Err(Refused::Unrooted);
                            }
                        }
                        Origin::Recovery { boot: from, last } => {
                            if !self.logged(from, *last) {
                                return Err(Refused::Unrooted);
                            }
                            if self.settled(from) {
                                return Err(Refused::Settled);
                            }
                        }
                    }
                }
                _ => {
                    if seq <= 1 {
                        return Err(Refused::OutOfPlace);
                    }
                    if !self.logged(boot, 1) {
                        return Err(Refused::Unvouched);
                    }
                    if self.boots.get(boot).is_some_and(|b| b.recovered) {
                        return Err(Refused::Fenced);
                    }
                }
            }
            self.keep(v).map_err(|_| Refused::Unwritten)
        }

        /// Appends the record to its boot's file, then to what `accept` asks.
        fn keep(&mut self, v: Verified) -> std::io::Result<()> {
            let hex = |b: &[u8]| b.iter().map(|x| format!("{x:02x}")).collect::<String>();
            let boot = v.record.boot().clone();
            if !self.boots.contains_key(&boot) {
                let path = self.dir.join(format!("{}.log", hex(boot.bytes())));
                let file = File::options().create(true).append(true).open(path)?;
                self.boots.insert(boot.clone(), BootLog { file, seqs: BTreeSet::new(), exited: false, recovered: false });
            }
            let line = format!("{} {}\n", hex(&v.bytes), hex(v.signature.bytes()));
            let entry = self.boots.get_mut(&boot).ok_or_else(|| std::io::Error::other("boot vanished"))?;
            entry.file.write_all(line.as_bytes())?;
            entry.seqs.insert(v.record.seq());
            if let Body::Exit(_) = v.record.body() {
                entry.exited = true;
            }
            if let Body::Report { origin: Origin::Recovery { boot: from, .. }, .. } = v.record.body() {
                if let Some(recovered) = self.boots.get_mut(from) {
                    recovered.recovered = true;
                }
            }
            Ok(())
        }
    }

    #[cfg(test)]
    mod tests {
        use super::{Log, Verified};
        use crate::record::Record;
        use crate::record::tests::{differential, unhex};

        /// Only a record its own boot's key signed gets through, and no SNP
        /// report yet.
        #[test]
        fn verify_refuses_forgeries() {
            use crate::machine::init::Key;
            use crate::record::{Attestation, Body, Origin, Signed};
            let report = |attestation| Body::Report {
                origin: Origin::Run,
                measurement: vec![],
                attestation,
                prompt: vec![],
                query: vec![],
            };
            let (key, other) = (Key::generate().expect("key"), Key::generate().expect("key"));
            let bytes = Record::new(key.boot(), 1, report(Attestation::Unattested)).encode();
            assert!(Verified::verify(Signed::new(bytes.clone(), key.sign(&bytes))).is_ok());
            assert!(Verified::verify(Signed::new(bytes.clone(), other.sign(&bytes))).is_err());
            let mut flipped = bytes.clone();
            flipped[40] ^= 1;
            assert!(Verified::verify(Signed::new(flipped, key.sign(&bytes))).is_err());
            let snp = Record::new(key.boot(), 1, report(Attestation::Snp(vec![1]))).encode();
            assert!(Verified::verify(Signed::new(snp.clone(), key.sign(&snp))).is_err());
        }

        /// Lean's `accept` and Rust's keep and refuse the same records, run
        /// after run from an empty log.
        #[test]
        fn accept_matches_lean() {
            let base = std::env::temp_dir().join(format!("cead-log-{}", std::process::id()));
            let (mut kept, mut refused, mut run) = (0, 0, 0);
            let mut log = Log::open(base.join("0")).expect("log");
            for line in differential(&["log", "300", "30", "4"]).lines() {
                if line == "---" {
                    run += 1;
                    log = Log::open(base.join(run.to_string())).expect("log");
                    continue;
                }
                let (hex, lean) = line.split_once(' ').expect("two fields");
                let record = Record::decode(&unhex(hex)).expect("Lean encodes records");
                let rust = log.accept(Verified::assume(record));
                assert_eq!(rust.is_ok(), lean == "kept", "run {run}: {line}: {rust:?}");
                if rust.is_ok() { kept += 1 } else { refused += 1 }
            }
            assert!(kept > 1000 && refused > 1000, "{kept} kept, {refused} refused");
        }
    }
}

/// The VMM: Cloud Hypervisor, driven as a child process.
pub(crate) mod vmm {
    use std::path::PathBuf;
    use std::process::Child;

    /// Booted, report not yet in the log.
    pub(crate) struct Booting;
    /// The log holds the report: init runs the harness.
    pub(crate) struct Up;

    /// One boot of one machine, from the VMM starting it to eviction. Owns the
    /// VMM process; dropping it evicts the machine.
    pub(crate) struct Machine<S> {
        vmm: Child,
        vsock: PathBuf,
        state: S,
    }

    impl Machine<Booting> {
        /// `Boot`: the VMM starts the kernel with the task image, the query and
        /// the context.
        pub(crate) fn boot(
            manifest: &super::job::Manifest,
            query: &[u8],
            context: &[u8],
        ) -> std::io::Result<Machine<Booting>> {
            todo!()
        }

        /// `Start`: the log holds the report.
        pub(crate) fn start(self) -> Machine<Up> {
            todo!()
        }
    }

    impl<S> Machine<S> {
        /// `Evict`: the host's hard kill, whatever state the boot is in.
        pub(crate) fn evict(self) {
            todo!()
        }
    }

    impl Machine<Up> {
        /// `Leave`: the log holds the exit record; the machine is gone.
        pub(crate) fn leave(self) {
            todo!()
        }
    }
}

/// The gateway: holds the model's credentials, which never enter the machine,
/// and relays each inference to Bedrock.
pub(crate) mod gateway {
    use std::fs::File;

    /// Owns the AWS credentials and the record of every request it relays: a
    /// second account of each window, independent of the log.
    pub(crate) struct Gateway {
        credentials: Credentials,
        requests: File,
    }

    /// AWS credentials, read on the host. Never serialized, never sent.
    pub(crate) struct Credentials {
        access_key: String,
        secret_key: String,
        session_token: Option<String>,
        region: String,
    }

    impl Gateway {
        /// Signs a request from the machine with SigV4, sends it, records it,
        /// and returns the response.
        pub(crate) fn relay(&mut self, request: &[u8]) -> std::io::Result<Vec<u8>> {
            todo!()
        }
    }
}

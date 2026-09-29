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
    use crate::record::{Boot, Record, Signature, Signed};
    use std::collections::{BTreeSet, HashMap};
    use std::fs::File;
    use std::path::PathBuf;

    /// Who guarantees the header's assumptions: the processor, or the host.
    pub(crate) enum Mode {
        Attested,
        TrustedHost,
    }

    /// A record whose signature checked against its boot's key and, for a
    /// report, whose attestation checked for the mode. The only kind `accept`
    /// takes.
    pub(crate) struct Verified {
        record: Record,
        bytes: Vec<u8>,
        signature: Signature,
    }

    /// A record signed by no one it names, or attested wrongly for the mode.
    pub(crate) struct Forged;

    impl Verified {
        pub(crate) fn verify(signed: Signed, mode: &Mode) -> Result<Verified, Forged> {
            todo!()
        }
    }

    /// One JSON-lines file per boot, append-only. Owned by the operator's `cead`
    /// for the life of the job.
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
    pub(crate) enum Refused {
        /// Its place in the boot's sequence is taken: first wins.
        Taken,
        /// A report not first in its sequence, or a record before its report.
        OutOfPlace,
        /// A record whose boot's report the log does not hold.
        Unvouched,
        /// A fork or recovery naming a record the log does not hold.
        Unrooted,
        /// A recovery of a boot that exited or is already recovered.
        Settled,
        /// A record of a boot a recovery has fenced.
        Fenced,
    }

    impl Log {
        pub(crate) fn open(dir: PathBuf) -> std::io::Result<Log> {
            todo!()
        }

        /// Keeps the record, or says why not. Keeping it acknowledges it.
        pub(crate) fn accept(&mut self, record: Verified) -> Result<(), Refused> {
            todo!()
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

//! Records: what the machine signs and the log keeps. Mirrors `spec/cead.tla`'s
//! `Record` and `spec/Cead/Record.lean`; the encoding is the Lean codec's, byte
//! for byte, which the differential test checks.

/// A boot, named by its public key: the key that signs its records.
pub(crate) struct Boot([u8; 32]);

/// A SHA-256 digest.
pub(crate) struct Digest([u8; 32]);

/// An Ed25519 signature over a record's encoding.
pub(crate) struct Signature([u8; 64]);

/// A call's number within its boot, shared by its intent, decision and witness.
pub(crate) struct CallId(u64);

/// A process's number within its boot; the root is 0, a spawn numbers the rest.
pub(crate) struct ProcId(u64);

/// One record: its boot, its place in the boot's sequence, what it says.
/// Owned by whoever holds it: the harness until sent, then the log.
pub(crate) struct Record {
    boot: Boot,
    seq: u64,
    body: Body,
}

/// What a record says. Together a boot's records hold every byte its windows
/// held, so the log replays them.
pub(crate) enum Body {
    /// The boot's first record. `prompt` and `query` open the root's window.
    Report {
        origin: Origin,
        measurement: Vec<u8>,
        attestation: Attestation,
        prompt: Vec<u8>,
        query: Vec<u8>,
    },
    /// One of a call's three records, naming the process that made it.
    Call {
        id: CallId,
        proc: ProcId,
        event: Event,
    },
    /// The boot's last record: why it ended.
    Exit(Exit),
}

/// What started a boot. A fork or recovery names its snapshot: that boot and
/// its last record.
pub(crate) enum Origin {
    Run,
    Fork { boot: Boot, last: u64 },
    Recovery { boot: Boot, last: u64 },
}

/// What the processor signed about a boot; `Unattested` in trusted-host mode.
pub(crate) enum Attestation {
    Unattested,
    /// A TSM report from SEV-SNP, binding the boot's key to the measurement.
    Snp(Vec<u8>),
}

/// A call's record.
pub(crate) enum Event {
    /// The model's whole turn, and the command the harness took from it.
    Intent { turn: Vec<u8>, command: Vec<u8> },
    Decision(Decision),
    /// The command ended: how, the digest of its whole output, and what the
    /// call returned to the model.
    Witness {
        status: WaitStatus,
        output: Digest,
        returned: Vec<u8>,
    },
}

/// The outcome of checking a call against policy.
pub(crate) enum Decision {
    /// Refused; `returned` is what the model gets back, which ends the call.
    Deny { returned: Vec<u8> },
    Allow,
    /// Allowed `agent`: the process it starts and that process's query.
    Spawn { child: ProcId, query: Vec<u8> },
}

/// How a command ended, as `wait(2)` reports it.
pub(crate) enum WaitStatus {
    Exited(u8),
    Signaled(u8),
}

/// Why a boot ended: its root process's status. Only a finish has a reply.
pub(crate) enum Exit {
    /// The root replied without a command; the digest of its reply, the answer.
    Finish { reply: Digest },
    Meter,
    Limit,
    Timeout,
}

/// Bytes that are no record's encoding.
pub(crate) struct Malformed;

impl Record {
    /// The bytes a boot's key signs: canonical, so a signature names one record.
    pub(crate) fn encode(&self) -> Vec<u8> {
        todo!()
    }

    /// The record these bytes encode, if they encode exactly one.
    pub(crate) fn decode(bytes: &[u8]) -> Result<Record, Malformed> {
        todo!()
    }
}

/// A record's encoding and its boot's signature over it, as it travels from
/// the machine to the log.
pub(crate) struct Signed {
    bytes: Vec<u8>,
    signature: Signature,
}

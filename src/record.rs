//! Records: what the machine signs and the log keeps. Mirrors `spec/cead.tla`'s
//! `Record` and `spec/Cead/Record.lean`; the encoding is the Lean codec's, byte
//! for byte, which the differential test checks.

/// A boot, named by its public key: the key that signs its records.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub(crate) struct Boot([u8; 32]);

/// A SHA-256 digest.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub(crate) struct Digest([u8; 32]);

/// An Ed25519 signature over a record's encoding.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub(crate) struct Signature([u8; 64]);

/// A call's number within its boot, shared by its intent, decision and witness.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub(crate) struct CallId(u64);

/// A process's number within its boot; the root is 0, a spawn numbers the rest.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub(crate) struct ProcId(u64);

/// One record: its boot, its place in the boot's sequence, what it says.
/// Owned by whoever holds it: the harness until sent, then the log.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub(crate) struct Record {
    boot: Boot,
    seq: u64,
    body: Body,
}

/// What a record says. Together a boot's records hold every byte its windows
/// held, so the log replays them.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
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
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub(crate) enum Origin {
    Run,
    Fork { boot: Boot, last: u64 },
    Recovery { boot: Boot, last: u64 },
}

/// What the processor signed about a boot; `Unattested` in trusted-host mode.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub(crate) enum Attestation {
    Unattested,
    /// A TSM report from SEV-SNP, binding the boot's key to the measurement.
    Snp(Vec<u8>),
}

/// A call's record.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
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
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub(crate) enum Decision {
    /// Refused; `returned` is what the model gets back, which ends the call.
    Deny { returned: Vec<u8> },
    Allow,
    /// Allowed `agent`: the process it starts and that process's query.
    Spawn { child: ProcId, query: Vec<u8> },
}

/// How a command ended, as `wait(2)` reports it.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub(crate) enum WaitStatus {
    Exited(u8),
    Signaled(u8),
}

/// Why a boot ended: its root process's status. Only a finish has a reply.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub(crate) enum Exit {
    /// The root replied without a command; the digest of its reply, the answer.
    Finish { reply: Digest },
    Meter,
    Limit,
    Timeout,
}

/// Bytes that are no record's encoding.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub(crate) struct Malformed;

impl Record {
    /// The bytes a boot's key signs: canonical, so a signature names one record.
    pub(crate) fn encode(&self) -> Vec<u8> {
        let mut out = Vec::new();
        self.write(&mut out);
        out
    }

    /// The record these bytes encode, if they encode exactly one.
    pub(crate) fn decode(bytes: &[u8]) -> Result<Record, Malformed> {
        let mut r = Reader(bytes);
        let record = Record::read(&mut r)?;
        if r.0.is_empty() { Ok(record) } else { Err(Malformed) }
    }
}

// The codec of `spec/Cead/Record.lean`: every value is self-delimiting. A
// variant is a tag byte, then its fields in order; a u64 is eight bytes
// big-endian; bytes are a u64 length, then the bytes; a key or digest is its
// 32 bytes.

struct Reader<'a>(&'a [u8]);

impl<'a> Reader<'a> {
    fn take(&mut self, n: usize) -> Result<&'a [u8], Malformed> {
        if self.0.len() < n {
            return Err(Malformed);
        }
        let (head, rest) = self.0.split_at(n);
        self.0 = rest;
        Ok(head)
    }

    fn tag(&mut self) -> Result<u8, Malformed> {
        Ok(self.take(1)?[0])
    }

    fn u64(&mut self) -> Result<u64, Malformed> {
        let mut b = [0; 8];
        b.copy_from_slice(self.take(8)?);
        Ok(u64::from_be_bytes(b))
    }

    fn bytes(&mut self) -> Result<Vec<u8>, Malformed> {
        let n = usize::try_from(self.u64()?).map_err(|_| Malformed)?;
        Ok(self.take(n)?.to_vec())
    }

    fn fixed(&mut self) -> Result<[u8; 32], Malformed> {
        let mut b = [0; 32];
        b.copy_from_slice(self.take(32)?);
        Ok(b)
    }
}

fn put_u64(out: &mut Vec<u8>, n: u64) {
    out.extend_from_slice(&n.to_be_bytes());
}

fn put_bytes(out: &mut Vec<u8>, b: &[u8]) {
    put_u64(out, b.len() as u64);
    out.extend_from_slice(b);
}

impl Record {
    fn write(&self, out: &mut Vec<u8>) {
        out.extend_from_slice(&self.boot.0);
        put_u64(out, self.seq);
        self.body.write(out);
    }

    fn read(r: &mut Reader<'_>) -> Result<Record, Malformed> {
        Ok(Record { boot: Boot(r.fixed()?), seq: r.u64()?, body: Body::read(r)? })
    }
}

impl Body {
    fn write(&self, out: &mut Vec<u8>) {
        match self {
            Body::Report { origin, measurement, attestation, prompt, query } => {
                out.push(0);
                origin.write(out);
                put_bytes(out, measurement);
                attestation.write(out);
                put_bytes(out, prompt);
                put_bytes(out, query);
            }
            Body::Call { id, proc, event } => {
                out.push(1);
                put_u64(out, id.0);
                put_u64(out, proc.0);
                event.write(out);
            }
            Body::Exit(exit) => {
                out.push(2);
                exit.write(out);
            }
        }
    }

    fn read(r: &mut Reader<'_>) -> Result<Body, Malformed> {
        Ok(match r.tag()? {
            0 => Body::Report {
                origin: Origin::read(r)?,
                measurement: r.bytes()?,
                attestation: Attestation::read(r)?,
                prompt: r.bytes()?,
                query: r.bytes()?,
            },
            1 => Body::Call { id: CallId(r.u64()?), proc: ProcId(r.u64()?), event: Event::read(r)? },
            2 => Body::Exit(Exit::read(r)?),
            _ => return Err(Malformed),
        })
    }
}

impl Origin {
    fn write(&self, out: &mut Vec<u8>) {
        let (tag, snapshot) = match self {
            Origin::Run => (0, None),
            Origin::Fork { boot, last } => (1, Some((boot, last))),
            Origin::Recovery { boot, last } => (2, Some((boot, last))),
        };
        out.push(tag);
        if let Some((boot, last)) = snapshot {
            out.extend_from_slice(&boot.0);
            put_u64(out, *last);
        }
    }

    fn read(r: &mut Reader<'_>) -> Result<Origin, Malformed> {
        Ok(match r.tag()? {
            0 => Origin::Run,
            1 => Origin::Fork { boot: Boot(r.fixed()?), last: r.u64()? },
            2 => Origin::Recovery { boot: Boot(r.fixed()?), last: r.u64()? },
            _ => return Err(Malformed),
        })
    }
}

impl Attestation {
    fn write(&self, out: &mut Vec<u8>) {
        match self {
            Attestation::Unattested => out.push(0),
            Attestation::Snp(report) => {
                out.push(1);
                put_bytes(out, report);
            }
        }
    }

    fn read(r: &mut Reader<'_>) -> Result<Attestation, Malformed> {
        Ok(match r.tag()? {
            0 => Attestation::Unattested,
            1 => Attestation::Snp(r.bytes()?),
            _ => return Err(Malformed),
        })
    }
}

impl Event {
    fn write(&self, out: &mut Vec<u8>) {
        match self {
            Event::Intent { turn, command } => {
                out.push(0);
                put_bytes(out, turn);
                put_bytes(out, command);
            }
            Event::Decision(decision) => {
                out.push(1);
                decision.write(out);
            }
            Event::Witness { status, output, returned } => {
                out.push(2);
                status.write(out);
                out.extend_from_slice(&output.0);
                put_bytes(out, returned);
            }
        }
    }

    fn read(r: &mut Reader<'_>) -> Result<Event, Malformed> {
        Ok(match r.tag()? {
            0 => Event::Intent { turn: r.bytes()?, command: r.bytes()? },
            1 => Event::Decision(Decision::read(r)?),
            2 => Event::Witness {
                status: WaitStatus::read(r)?,
                output: Digest(r.fixed()?),
                returned: r.bytes()?,
            },
            _ => return Err(Malformed),
        })
    }
}

impl Decision {
    fn write(&self, out: &mut Vec<u8>) {
        match self {
            Decision::Deny { returned } => {
                out.push(0);
                put_bytes(out, returned);
            }
            Decision::Allow => out.push(1),
            Decision::Spawn { child, query } => {
                out.push(2);
                put_u64(out, child.0);
                put_bytes(out, query);
            }
        }
    }

    fn read(r: &mut Reader<'_>) -> Result<Decision, Malformed> {
        Ok(match r.tag()? {
            0 => Decision::Deny { returned: r.bytes()? },
            1 => Decision::Allow,
            2 => Decision::Spawn { child: ProcId(r.u64()?), query: r.bytes()? },
            _ => return Err(Malformed),
        })
    }
}

impl WaitStatus {
    fn write(&self, out: &mut Vec<u8>) {
        let (tag, n) = match self {
            WaitStatus::Exited(code) => (0, code),
            WaitStatus::Signaled(signal) => (1, signal),
        };
        out.extend_from_slice(&[tag, *n]);
    }

    fn read(r: &mut Reader<'_>) -> Result<WaitStatus, Malformed> {
        Ok(match r.tag()? {
            0 => WaitStatus::Exited(r.tag()?),
            1 => WaitStatus::Signaled(r.tag()?),
            _ => return Err(Malformed),
        })
    }
}

impl Exit {
    fn write(&self, out: &mut Vec<u8>) {
        match self {
            Exit::Finish { reply } => {
                out.push(0);
                out.extend_from_slice(&reply.0);
            }
            Exit::Meter => out.push(1),
            Exit::Limit => out.push(2),
            Exit::Timeout => out.push(3),
        }
    }

    fn read(r: &mut Reader<'_>) -> Result<Exit, Malformed> {
        Ok(match r.tag()? {
            0 => Exit::Finish { reply: Digest(r.fixed()?) },
            1 => Exit::Meter,
            2 => Exit::Limit,
            3 => Exit::Timeout,
            _ => return Err(Malformed),
        })
    }
}

/// A record's encoding and its boot's signature over it, as it travels from
/// the machine to the log.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub(crate) struct Signed {
    bytes: Vec<u8>,
    signature: Signature,
}

#[cfg(test)]
mod tests {
    use super::Record;
    use std::process::Command;

    /// Runs the Lean half of the differential test (`spec/Cead/Differential.lean`),
    /// building it first. Needs `lake` on PATH (elan's `~/.elan/bin`).
    pub(crate) fn differential(args: &[&str]) -> String {
        let spec = concat!(env!("CARGO_MANIFEST_DIR"), "/spec");
        let built = Command::new("lake").args(["build", "differential"]).current_dir(spec).status();
        assert!(built.expect("lake runs").success(), "lake build differential");
        let out = Command::new(format!("{spec}/.lake/build/bin/differential"))
            .args(args)
            .output()
            .expect("differential runs");
        assert!(out.status.success());
        String::from_utf8(out.stdout).expect("differential prints text")
    }

    pub(crate) fn unhex(s: &str) -> Vec<u8> {
        (0..s.len())
            .step_by(2)
            .map(|i| u8::from_str_radix(&s[i..i + 2], 16).expect("hex"))
            .collect()
    }

    /// Every encoding Lean accepts, Rust decodes and re-encodes to the same
    /// bytes; every one Lean rejects (a byte changed, cut short, extended), Rust
    /// rejects too.
    #[test]
    fn codec_matches_lean() {
        let lines = differential(&["record", "5000", "1"]);
        let (mut valid, mut rejected) = (0, 0);
        for line in lines.lines() {
            let (input, lean) = line.split_once(' ').expect("two fields");
            let bytes = unhex(input);
            match (Record::decode(&bytes), lean) {
                (Err(_), "-") => rejected += 1,
                (Ok(_), "-") => panic!("Rust decodes what Lean rejects: {line}"),
                (Ok(r), expected) => {
                    assert_eq!(r.encode(), unhex(expected), "{line}");
                    valid += 1;
                }
                (Err(_), _) => panic!("Lean decodes what Rust rejects: {line}"),
            }
        }
        assert!(valid > 1000 && rejected > 1000, "{valid} valid, {rejected} rejected");
    }
}

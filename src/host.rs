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
            if let Body::Report { origin: Origin::Recovery { boot: from, .. }, .. } = v.record.body()
                && let Some(recovered) = self.boots.get_mut(from)
            {
                recovered.recovered = true;
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

/// The gateway: holds the model's credential, which never enters the machine,
/// and relays each inference to Bedrock's Converse API.
pub(crate) mod gateway {
    use crate::machine::window::{self, Role, Span};
    use serde_json::{Value, json};
    use std::fs::File;
    use std::io::Write;
    use std::process::{Command, Stdio};

    /// A Bedrock API key: a bearer token, read on the host. Never serialized,
    /// never sent anywhere but Bedrock, never on a command line.
    pub(crate) struct Credentials(String);

    impl Credentials {
        pub(crate) fn new(token: String) -> Credentials {
            Credentials(token)
        }
    }

    /// Owns the credential and the record of every request it relays: a second
    /// account of each window, independent of the log.
    pub(crate) struct Gateway {
        credentials: Credentials,
        region: String,
        model: String,
        requests: File,
    }

    /// What Bedrock answered, or why there is no answer.
    #[derive(Debug)]
    pub(crate) enum Failed {
        /// The machine sent something that is not a window of text.
        BadWindow,
        /// `curl` could not run, or Bedrock refused; its words.
        Relay(String),
        /// Bedrock answered with no text.
        NoTurn,
    }

    /// One answer: the model's turn and the tokens it cost.
    #[derive(Debug, PartialEq)]
    pub(crate) struct Answer {
        turn: Vec<u8>,
        input_tokens: u64,
        output_tokens: u64,
    }

    impl Gateway {
        pub(crate) fn new(credentials: Credentials, region: String, model: String, requests: File) -> Gateway {
            Gateway { credentials, region, model, requests }
        }

        /// Takes a window as the machine encodes it, asks Bedrock, records the
        /// exchange (window, turn, tokens, in that order), and returns the turn.
        pub(crate) fn relay(&mut self, request: &[u8]) -> Result<Vec<u8>, Failed> {
            let spans = window::decode(request).map_err(|_| Failed::BadWindow)?;
            let body = body(&spans).ok_or(Failed::BadWindow)?;
            let answer = answer(&self.send(&body)?)?;
            let hex = |b: &[u8]| b.iter().map(|x| format!("{x:02x}")).collect::<String>();
            let line = format!(
                "{} {} {} {}\n",
                hex(request),
                hex(&answer.turn),
                answer.input_tokens,
                answer.output_tokens
            );
            self.requests.write_all(line.as_bytes()).map_err(|e| Failed::Relay(e.to_string()))?;
            Ok(answer.turn)
        }

        /// POSTs the body with `curl`. Its configuration, the token included,
        /// goes on stdin, so neither shows in the host's process list.
        fn send(&self, body: &Value) -> Result<Vec<u8>, Failed> {
            let url = format!(
                "https://bedrock-runtime.{}.amazonaws.com/model/{}/converse",
                self.region, self.model
            );
            let config = curl_config(&url, &self.credentials.0, &body.to_string());
            let mut curl = Command::new("curl")
                .args(["--config", "-"])
                .stdin(Stdio::piped())
                .stdout(Stdio::piped())
                .stderr(Stdio::piped())
                .spawn()
                .map_err(|e| Failed::Relay(e.to_string()))?;
            curl.stdin
                .take()
                .ok_or_else(|| Failed::Relay("no stdin".into()))?
                .write_all(config.as_bytes())
                .map_err(|e| Failed::Relay(e.to_string()))?;
            let out = curl.wait_with_output().map_err(|e| Failed::Relay(e.to_string()))?;
            if !out.status.success() {
                let words = [out.stderr, out.stdout].concat();
                return Err(Failed::Relay(String::from_utf8_lossy(&words).into_owned()));
            }
            Ok(out.stdout)
        }
    }

    /// A curl configuration, one option per line, values quoted with `"` and
    /// `\` escaped.
    fn curl_config(url: &str, token: &str, body: &str) -> String {
        let q = |v: &str| format!("\"{}\"", v.replace('\\', "\\\\").replace('"', "\\\""));
        [
            format!("url = {}", q(url)),
            "request = \"POST\"".into(),
            "silent".into(),
            "show-error".into(),
            "fail-with-body".into(),
            format!("header = {}", q(&format!("Authorization: Bearer {token}"))),
            format!("header = {}", q("Content-Type: application/json")),
            format!("data-raw = {}", q(body)),
        ]
        .join("\n")
            + "\n"
    }

    /// The Converse request for a window: its system span as the system
    /// prompt, the rest as alternating messages. None if any span is not text.
    fn body(spans: &[Span]) -> Option<Value> {
        let text = |s: &Span| std::str::from_utf8(s.text()).ok().map(str::to_owned);
        let mut system = Vec::new();
        let mut messages = Vec::new();
        for span in spans {
            let t = text(span)?;
            match span.role() {
                Role::System => system.push(json!({ "text": t })),
                Role::User => messages.push(json!({ "role": "user", "content": [{ "text": t }] })),
                Role::Assistant => messages.push(json!({ "role": "assistant", "content": [{ "text": t }] })),
            }
        }
        Some(json!({ "system": system, "messages": messages }))
    }

    /// The model's turn and its token counts from a Converse response.
    fn answer(response: &[u8]) -> Result<Answer, Failed> {
        let v: Value = serde_json::from_slice(response).map_err(|e| Failed::Relay(e.to_string()))?;
        let turn: String = v["output"]["message"]["content"]
            .as_array()
            .ok_or(Failed::NoTurn)?
            .iter()
            .filter_map(|c| c["text"].as_str())
            .collect();
        if turn.is_empty() {
            return Err(Failed::NoTurn);
        }
        let tokens = |k: &str| v["usage"][k].as_u64().unwrap_or(0);
        Ok(Answer { turn: turn.into_bytes(), input_tokens: tokens("inputTokens"), output_tokens: tokens("outputTokens") })
    }

    #[cfg(test)]
    mod tests {
        use super::{Answer, answer, body, curl_config};
        use crate::machine::window::Window;
        use serde_json::json;

        /// A window becomes Converse's system prompt and alternating messages.
        #[test]
        fn request_shape() {
            let mut w = Window::open(b"pinned".to_vec(), b"query".to_vec(), 100);
            w.push(b"ls".to_vec(), b"a\nexit 0".to_vec()).expect("fits");
            let spans = crate::machine::window::decode(&crate::machine::window::encode(w.spans())).expect("spans");
            assert_eq!(
                body(&spans).expect("text"),
                json!({
                    "system": [{ "text": "pinned" }],
                    "messages": [
                        { "role": "user", "content": [{ "text": "query" }] },
                        { "role": "assistant", "content": [{ "text": "ls" }] },
                        { "role": "user", "content": [{ "text": "a\nexit 0" }] },
                    ]
                })
            );
        }

        /// The turn is the response's text, joined; its tokens are counted.
        #[test]
        fn response_shape() {
            let response = json!({
                "output": { "message": { "role": "assistant", "content": [{ "text": "cat " }, { "text": "f" }] } },
                "usage": { "inputTokens": 12, "outputTokens": 3 },
                "stopReason": "end_turn"
            });
            let got = answer(response.to_string().as_bytes()).expect("answer");
            assert_eq!(got, Answer { turn: b"cat f".to_vec(), input_tokens: 12, output_tokens: 3 });
            assert!(answer(br#"{"output":{"message":{"content":[]}}}"#).is_err());
        }

        /// Quotes and backslashes in the body cannot end a config value early.
        #[test]
        fn config_quotes() {
            let c = curl_config("https://x", "t", r#"{"a":"b\"c"}"#);
            assert!(c.contains(r#"data-raw = "{\"a\":\"b\\\"c\"}""#), "{c}");
            assert!(c.contains(r#"header = "Authorization: Bearer t""#));
        }
    }
}

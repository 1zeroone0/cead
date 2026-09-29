//! cead: one binary, its role chosen at start. On the host, the operator's
//! `cead run`. In the machine, `cead init` as PID 1, the harness it execs,
//! and `agent`, the call cead adds, reached by its name on PATH.

mod host;
mod machine;
mod record;

use std::process::ExitCode;

/// What this process is, from its argv. Owns nothing; dropped once dispatched.
enum Role {
    /// `cead run QUERY`: one job, context on stdin, the answer on stdout.
    Run { query: Vec<u8> },
    /// `cead init`: PID 1 in the machine, for the whole boot.
    Init,
    /// `cead harness`: exec'd by init, so it starts without init's key.
    Harness,
    /// `agent QUERY`: a model's process asking the harness for a child.
    Agent { query: Vec<u8> },
}

/// argv that names no role, or names one wrongly. Owns the message for stderr.
struct Usage(String);

impl Role {
    /// Chooses the role from argv: `agent` by the name it was run as, the rest
    /// by subcommand.
    fn parse(args: Vec<std::ffi::OsString>) -> Result<Role, Usage> {
        use std::os::unix::ffi::OsStrExt;
        let bytes = |a: &std::ffi::OsString| a.as_bytes().to_vec();
        let name = args.first().and_then(|a| std::path::Path::new(a).file_name());
        let rest = args.get(1..).unwrap_or_default();
        match (name.map(|n| n.as_bytes()), rest) {
            (Some(b"agent"), [query]) => Ok(Role::Agent { query: bytes(query) }),
            (Some(b"agent"), _) => Err(Usage("usage: agent QUERY < slice".into())),
            (_, [verb, query]) if verb == "run" => Ok(Role::Run { query: bytes(query) }),
            (_, [verb]) if verb == "init" => Ok(Role::Init),
            (_, [verb]) if verb == "harness" => Ok(Role::Harness),
            _ => Err(Usage("usage: cead run QUERY < context > answer".into())),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::Role;

    fn parse(args: &[&str]) -> Option<Role> {
        Role::parse(args.iter().map(std::ffi::OsString::from).collect()).ok()
    }

    /// `agent` by the name it runs as; the rest by subcommand; nothing else.
    #[test]
    fn roles() {
        assert!(matches!(parse(&["/core/bin/agent", "find x"]), Some(Role::Agent { query }) if query == b"find x"));
        assert!(matches!(parse(&["cead", "run", "q"]), Some(Role::Run { query }) if query == b"q"));
        assert!(matches!(parse(&["/cead", "init"]), Some(Role::Init)));
        assert!(matches!(parse(&["/proc/self/exe", "harness"]), Some(Role::Harness)));
        assert!(parse(&["agent"]).is_none());
        assert!(parse(&["cead", "run"]).is_none());
        assert!(parse(&["cead"]).is_none());
    }
}

fn main() -> ExitCode {
    todo!()
}

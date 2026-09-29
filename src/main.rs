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
        todo!()
    }
}

fn main() -> ExitCode {
    todo!()
}

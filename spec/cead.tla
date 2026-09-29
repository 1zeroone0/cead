-------------------------------- MODULE cead --------------------------------
(***************************************************************************)
(* cead as a system. Layer 1: one job, one boot, one process.              *)
(*                                                                         *)
(* Assumptions, and who guarantees each. An attested boot proves them;     *)
(* trusted-host mode asserts them. The protocol is the same in both.       *)
(*   KeySecret  Only the machine can sign with its key.                    *)
(*              Attested: the processor. Trusted host: asserted.           *)
(*   KeyBound   Only the processor can sign a report, so a report names    *)
(*              the key of the boot that made it.                          *)
(*              Attested: the processor. Trusted host: the host.           *)
(* Availability is the host's in both modes: it can always stop a job.     *)
(* Everything on the path, the host included, is a Dolev-Yao network: it   *)
(* can lose, delay, replay and forge records, but signs only as itself.    *)
(***************************************************************************)
EXTENDS Naturals, Sequences

CONSTANTS
    Commands,   \* what the model can write; the spec never sees shell text
    Policy,     \* the commands the policy denies; {} is permit-all
    CallLimit,  \* the limit on calls for one process
    NoRecord       \* a model value: no record awaiting acknowledgment

ASSUME /\ Policy \subseteq Commands
       /\ CallLimit \in Nat

Decision(c) == IF c \in Policy THEN "deny" ELSE "allow"

CallTypes   == {"intent", "decision", "witness"}  \* one call's records
Reasons == {"finish", "timeout"}              \* what an exit record can say
Keys    == {"machine", "path"}                \* who can sign: the boot's key, the path's
Signers == Keys \cup {"processor"}            \* the processor signs only reports
MaxSeq  == 3 * CallLimit + 2                  \* the report, every call's records, the exit

\* One record of the boot. `seq` is its place in the boot's hash chain: the
\* order the machine sent it, whatever order it arrives in. The report
\* (seq 1, id 0) names the key the rest are signed with. A call's intent,
\* decision and witness carry its id and command; the exit record carries
\* id 0 and how the machine exited.
Record == [seq : 1..MaxSeq, id : 0..CallLimit,
            type : CallTypes \cup {"report", "exit"},
            body : Commands \cup Reasons \cup Keys, key : Signers]

VARIABLES
    machine,   \* "off", "up", "exiting", "evicted"
    process,   \* "initial", "running", "blocked", "zombie"
    calls,     \* calls issued so far; the current call's id
    seq,       \* the machine's last sequence number
    pending,   \* the record awaiting the log's acknowledgment, or NoRecord
    executed,  \* what the kernel ran, in order: the truth
    transit,   \* records in transit: can be lost, delayed, reordered, duplicated
    log        \* held outside the machine: a set of records

vars == <<machine, process, calls, seq, pending, executed, transit, log>>

Rec(s, i, p, b)  == [seq |-> s, id |-> i, type |-> p, body |-> b, key |-> "machine"]
Report           == [seq |-> 1, id |-> 0, type |-> "report", body |-> "machine", key |-> "processor"]
Logged(s)        == \E m \in log : m.seq = s
LoggedType(i, p) == \E m \in log : m.id = i /\ m.type = p
\* The log holds a processor-signed report naming key k.
Vouched(k)       == \E r \in log : r.type = "report" /\ r.key = "processor" /\ r.body = k

-----------------------------------------------------------------------------
(* The machine and its process                                             *)

Init ==
    /\ machine  = "off"
    /\ process  = "initial"
    /\ calls    = 0
    /\ seq      = 0
    /\ pending  = NoRecord
    /\ executed = <<>>
    /\ transit = {}
    /\ log      = {}

\* The VMM boots the machine. It makes its key and sends the report, the
\* first record, which awaits acknowledgment.
Boot ==
    /\ machine = "off"
    /\ machine' = "up"
    /\ seq' = 1
    /\ pending' = Report
    /\ transit' = transit \cup {Report}
    /\ UNCHANGED <<process, calls, executed, log>>

\* The log holds the report: init assembles the view, the harness starts the
\* root process. Nothing runs on a boot the log has not heard of.
Start ==
    /\ machine = "up"
    /\ process = "initial"
    /\ pending = Report
    /\ Logged(1)
    /\ process' = "running"
    /\ pending' = NoRecord
    /\ UNCHANGED <<machine, calls, seq, executed, transit, log>>

\* The model issues a call. The harness blocks the process and sends the
\* intent, which awaits acknowledgment.
Issue(c) ==
    /\ machine = "up"
    /\ process = "running"
    /\ calls < CallLimit
    /\ process' = "blocked"
    /\ calls' = calls + 1
    /\ seq' = seq + 1
    /\ pending' = Rec(seq + 1, calls + 1, "intent", c)
    /\ transit' = transit \cup {pending'}
    /\ UNCHANGED <<machine, executed, log>>

\* The log has not acknowledged the pending record: send it again.
Resend ==
    /\ machine \in {"up", "exiting"}
    /\ pending # NoRecord
    /\ ~Logged(pending.seq)
    /\ transit' = transit \cup {pending}
    /\ UNCHANGED <<machine, process, calls, seq, pending, executed, log>>

\* The log has acknowledged the intent: the harness checks the call against
\* policy. Deny returns to the model. Allow runs the command, and the tracer
\* witnesses it; both records go through the harness, which sequences them.
Decide ==
    /\ machine = "up"
    /\ process = "blocked"
    /\ pending # NoRecord
    /\ pending.type = "intent"
    /\ Logged(pending.seq)
    /\ LET c == pending.body
           i == pending.id
       IN IF Decision(c) = "allow"
            THEN /\ executed' = Append(executed, [id |-> i, cmd |-> c])
                 /\ transit' = transit \cup
                      {Rec(seq + 1, i, "decision", c), Rec(seq + 2, i, "witness", c)}
                 /\ seq' = seq + 2
            ELSE /\ executed' = executed
                 /\ transit' = transit \cup {Rec(seq + 1, i, "decision", c)}
                 /\ seq' = seq + 1
    /\ process' = "running"
    /\ pending' = NoRecord
    /\ UNCHANGED <<machine, calls, log>>

\* The model calls `finish`: the process is a zombie until the harness reaps it.
Finish ==
    /\ machine = "up"
    /\ process = "running"
    /\ process' = "zombie"
    /\ UNCHANGED <<machine, calls, seq, pending, executed, transit, log>>

\* The machine signs its exit record, its last record, and waits
\* for the log to acknowledge it. Any call in progress is cut off.
Exit(reason) ==
    /\ machine = "up"
    /\ machine' = "exiting"
    /\ seq' = seq + 1
    /\ pending' = Rec(seq + 1, 0, "exit", reason)
    /\ transit' = transit \cup {pending'}
    /\ UNCHANGED <<process, calls, executed, log>>

\* The harness reaps the root process.
Reap    == process = "zombie" /\ Exit("finish")
\* The machine's own wall-time limit fires.
Timeout == Exit("timeout")

\* The log has the exit record: the machine is gone.
Leave ==
    /\ machine = "exiting"
    /\ Logged(pending.seq)
    /\ machine' = "evicted"
    /\ pending' = NoRecord
    /\ UNCHANGED <<process, calls, seq, executed, transit, log>>

\* The machine ends without an acknowledged exit record. A crash can happen
\* at any point. The host's hard kill is the same event, but it is assumed
\* to happen (see Spec): it is what makes every job end.
Evict ==
    /\ machine \in {"up", "exiting"}
    /\ machine' = "evicted"
    /\ pending' = NoRecord
    /\ UNCHANGED <<process, calls, seq, executed, transit, log>>

Crash    == Evict
HostKill == Evict

-----------------------------------------------------------------------------
(* Records in transit: outside the machine, so they go on after eviction  *)

\* The log keeps a report only if the processor signed it, and any other
\* record only if a key it vouched for signed it. It keeps the first
\* record for each place in the chain; a duplicate or resend changes
\* nothing. First-wins matters only if KeySecret fails, so TLC never
\* exercises it.
Arrive(m) ==
    /\ IF m.type = "report" THEN m.key = "processor" ELSE Vouched(m.key)
    /\ ~Logged(m.seq)
    /\ log' = log \cup {m}
    /\ UNCHANGED <<machine, process, calls, seq, pending, executed, transit>>

Deliver(m) == m \in transit /\ Arrive(m)

Lose(m) ==
    /\ m \in transit
    /\ transit' = transit \ {m}
    /\ UNCHANGED <<machine, process, calls, seq, pending, executed, log>>

\* Anything on the path, the host included, can send the log a record at
\* any moment, but can sign only as itself. A forgery affects nothing until
\* it reaches the log, so it is modelled as arriving there directly.
Forge(m) == m.key = "path" /\ Arrive(m)

-----------------------------------------------------------------------------

Next ==
    \/ Boot
    \/ Start
    \/ \E c \in Commands : Issue(c)
    \/ Resend
    \/ Decide
    \/ Finish
    \/ Reap
    \/ Timeout
    \/ Leave
    \/ Crash
    \/ HostKill
    \/ \E m \in transit : Deliver(m) \/ Lose(m)
    \/ \E m \in Record : Forge(m)

Spec == Init /\ [][Next]_vars /\ WF_vars(HostKill)

-----------------------------------------------------------------------------
(* Properties                                                              *)

TypeOK ==
    /\ machine \in {"off", "up", "exiting", "evicted"}
    /\ process \in {"initial", "running", "blocked", "zombie"}
    /\ calls \in Nat
    /\ seq \in Nat
    /\ pending \in Record \cup {NoRecord}
    /\ executed \in Seq([id : 1..CallLimit, cmd : Commands])
    /\ transit \subseteq Record
    /\ log \subseteq Record

\* 1. Nothing is executed before its intent is in the log.
IntentFirst == \A k \in 1..Len(executed) : LoggedType(executed[k].id, "intent")

\* 2. The log only gains records.
LogOnlyGrows == [][log \subseteq log']_log

\* 3. Nothing whose decision is deny is executed.
DenyNeverRuns == \A k \in 1..Len(executed) : Decision(executed[k].cmd) = "allow"

\* 4. A process makes at most CallLimit calls.
WithinLimit == calls <= CallLimit

\* 5. Every job that starts ends, and its machine is evicted.
JobEnds == (machine = "up") ~> (machine = "evicted")

\* 6. The log holds only what the processor signed, or a key it vouched for.
OnlyMachine == \A m \in log : m.key = "processor" \/ Vouched(m.key)

\* 7. Each call is executed at most once.
ExecutedOnce ==
    \A j, k \in 1..Len(executed) : j # k => executed[j].id # executed[k].id

\* 8. The machine never signs two different records for one place in the
\*    chain, so the chain gives one order.
Unambiguous ==
    LET Seen == {m \in transit : m.key # "path"} \cup
                log
    IN \A m1, m2 \in Seen : m1.seq = m2.seq => m1 = m2

\* 9. An exit record saying `finish` means the model called `finish`: no
\*    call was cut off.
FinishHonest ==
    \A m \in log : (m.type = "exit" /\ m.body = "finish") => process = "zombie"

\* 10. An exit record with an unbroken chain before it proves the log
\*     complete: every executed call has all three records logged.
Complete ==
    \A x \in log :
        (x.type = "exit" /\ \A s \in 1..x.seq - 1 : Logged(s))
            => \A e \in 1..Len(executed) :
                 \A p \in CallTypes : LoggedType(executed[e].id, p)

\* 11. Nothing runs on a boot until the log holds its report.
ReportFirst == process # "initial" => Vouched("machine")

=============================================================================

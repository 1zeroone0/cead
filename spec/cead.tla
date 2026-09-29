-------------------------------- MODULE cead --------------------------------
(***************************************************************************)
(* cead as a system.                                                       *)
(* Layer 1: a boot, its process, its records and the log.                  *)
(* Layer 2: snapshot, and boots from one: fork and recovery.               *)
(*                                                                         *)
(* Assumptions, and who guarantees each. An attested boot proves them;     *)
(* trusted-host mode asserts them. The protocol is the same in both.       *)
(*   KeySecret       Only a boot can sign with its key.                    *)
(*                   Attested: the processor. Trusted host: asserted.      *)
(*   KeyBound        Only the processor can sign a report, so a report     *)
(*                   names the key of the boot that made it.               *)
(*                   Attested: the processor. Trusted host: the host.      *)
(*   SnapshotSealed  The host cannot alter a snapshot or read its key.     *)
(*                   Attested: open research. Trusted host: asserted.      *)
(* Availability is the host's in both modes: it can always stop a job.     *)
(* Everything on the path, the host included, is a Dolev-Yao network: it   *)
(* can lose, delay, replay and forge records, but signs only as itself.    *)
(***************************************************************************)
EXTENDS Naturals, Sequences

CONSTANTS
    Commands,   \* what the model can write; the spec never sees shell text
    Policy,     \* the commands the policy denies; {} is permit-all
    CallLimit,  \* the limit on calls for one process
    Boots,      \* model values: each boot, which is also its key
    Root,       \* the boot `cead run` starts
    NoRecord    \* a model value: no record awaiting acknowledgment

ASSUME /\ Policy \subseteq Commands
       /\ CallLimit \in Nat
       /\ Root \in Boots

Decision(c) == IF c \in Policy THEN "deny" ELSE "allow"

CallTypes == {"intent", "decision", "witness"}  \* one call's records
Reasons   == {"finish", "timeout"}              \* what an exit record can say
Origins   == {"run", "fork", "recovery"}        \* what a report says started its boot
Signers   == Boots \cup {"path", "processor"}   \* the processor signs only reports
MaxSeq    == 3 * CallLimit + 2                  \* the report, every call's records, the exit
None      == "none"                             \* a report not booted from a snapshot

\* One record of a boot. `seq` is its place in the boot's hash chain: the
\* order the machine sent it, whatever order it arrives in. A report (seq 1,
\* id 0) names its boot, whose key signs the rest, what started it, and for
\* a fork or recovery the snapshot it booted from: that boot and its last
\* record. A call's
\* intent, decision and witness carry its id and command; the exit record
\* carries id 0 and how the machine exited.
Record == [boot : Boots, seq : 1..MaxSeq, id : 0..CallLimit,
           type : CallTypes \cup {"report", "exit"},
           body : Commands \cup Reasons \cup Origins, key : Signers,
           from : Boots \cup {None}, last : 0..MaxSeq]

VARIABLES
    machine,    \* per boot: "off", "up", "exiting", "evicted"
    process,    \* per boot, its root process: "initial", "running", "blocked", "zombie"
    calls,      \* per boot: calls issued so far; the current call's id
    seq,        \* per boot: the machine's last sequence number
    pending,    \* per boot: the record awaiting the log's acknowledgment, or NoRecord
    executed,   \* per boot: what the kernel ran, in order: the truth
    job,        \* per boot: the boot that started its job
    snapshots,  \* every snapshot taken: a boot, its last record, its calls
    transit,    \* every record sent: each can be lost, delayed, reordered, duplicated
    log         \* held outside the machine: a set of records

vars == <<machine, process, calls, seq, pending, executed, job, snapshots, transit, log>>
boot == <<machine, process, calls, seq, pending, executed, job>>

Rec(b, s, i, t, x) == [boot |-> b, seq |-> s, id |-> i, type |-> t, body |-> x,
                       key |-> b, from |-> None, last |-> 0]
Report(b, o, p, h) == [boot |-> b, seq |-> 1, id |-> 0, type |-> "report", body |-> o,
                       key |-> "processor", from |-> p, last |-> h]
Logged(b, s)        == \E r \in log : r.boot = b /\ r.seq = s
LoggedType(b, i, t) == \E r \in log : r.boot = b /\ r.id = i /\ r.type = t
\* The log holds boot b's report: b's key is vouched for.
Vouched(b)          == Logged(b, 1)
\* The log holds a report recovering boot b.
Recovered(b)        == \E r \in log : r.type = "report" /\ r.body = "recovery" /\ r.from = b
\* Boot b is evicted without its exit record in the log.
Unknown(b)          == machine[b] = "evicted" /\ ~\E r \in log : r.boot = b /\ r.type = "exit"

-----------------------------------------------------------------------------
(* A boot and its process                                                  *)

Init ==
    /\ machine   = [b \in Boots |-> "off"]
    /\ process   = [b \in Boots |-> "initial"]
    /\ calls     = [b \in Boots |-> 0]
    /\ seq       = [b \in Boots |-> 0]
    /\ pending   = [b \in Boots |-> NoRecord]
    /\ executed  = [b \in Boots |-> <<>>]
    /\ job       = [b \in Boots |-> b]
    /\ snapshots = {}
    /\ transit   = {}
    /\ log       = {}

\* The VMM starts boot b: it makes its key and sends its report, which
\* awaits acknowledgment. `c` is the calls its process has already issued.
Begin(b, r, c, j) ==
    /\ machine' = [machine EXCEPT ![b] = "up"]
    /\ seq'     = [seq EXCEPT ![b] = 1]
    /\ calls'   = [calls EXCEPT ![b] = c]
    /\ pending' = [pending EXCEPT ![b] = r]
    /\ job'     = [job EXCEPT ![b] = j]
    /\ transit' = transit \cup {r}
    /\ UNCHANGED <<process, executed, snapshots, log>>

\* `cead run` boots the root.
Boot == machine[Root] = "off" /\ Begin(Root, Report(Root, "run", None, 0), 0, Root)

\* A boot from a snapshot. A fork starts a new job, whenever anyone asks;
\* a recovery continues the snapshot's job, once its boot is unknown.
BootFrom(b, s, o) ==
    /\ b # Root
    /\ machine[b] = "off"
    /\ o = "recovery" => Unknown(s.boot)
    /\ Begin(b, Report(b, o, s.boot, s.last), s.calls,
             IF o = "fork" THEN b ELSE job[s.boot])

\* The log holds the report: init assembles the view, the harness starts the
\* root process. Nothing runs on a boot the log has not heard of.
Start(b) ==
    /\ machine[b] = "up"
    /\ process[b] = "initial"
    /\ pending[b] # NoRecord
    /\ pending[b].type = "report"
    /\ Logged(b, 1)
    /\ process' = [process EXCEPT ![b] = "running"]
    /\ pending' = [pending EXCEPT ![b] = NoRecord]
    /\ UNCHANGED <<machine, calls, seq, executed, job, snapshots, transit, log>>

\* The model issues a call. The harness blocks the process and sends the
\* intent, which awaits acknowledgment.
Issue(b, c) ==
    /\ machine[b] = "up"
    /\ process[b] = "running"
    /\ calls[b] < CallLimit
    /\ LET r == Rec(b, seq[b] + 1, calls[b] + 1, "intent", c)
       IN /\ process' = [process EXCEPT ![b] = "blocked"]
          /\ calls'   = [calls EXCEPT ![b] = calls[b] + 1]
          /\ seq'     = [seq EXCEPT ![b] = seq[b] + 1]
          /\ pending' = [pending EXCEPT ![b] = r]
          /\ transit' = transit \cup {r}
    /\ UNCHANGED <<machine, executed, job, snapshots, log>>

\* The log has acknowledged the intent: the harness checks the call against
\* policy. Deny returns to the model. Allow runs the command, and the tracer
\* witnesses it; both records go through the harness, which sequences them.
Decide(b) ==
    /\ machine[b] = "up"
    /\ process[b] = "blocked"
    /\ pending[b] # NoRecord
    /\ pending[b].type = "intent"
    /\ Logged(b, pending[b].seq)
    /\ LET c == pending[b].body
           i == pending[b].id
           s == seq[b]
       IN IF Decision(c) = "allow"
            THEN /\ executed' = [executed EXCEPT ![b] = Append(@, [id |-> i, cmd |-> c])]
                 /\ transit' = transit \cup
                      {Rec(b, s + 1, i, "decision", c), Rec(b, s + 2, i, "witness", c)}
                 /\ seq' = [seq EXCEPT ![b] = s + 2]
            ELSE /\ executed' = executed
                 /\ transit' = transit \cup {Rec(b, s + 1, i, "decision", c)}
                 /\ seq' = [seq EXCEPT ![b] = s + 1]
    /\ process' = [process EXCEPT ![b] = "running"]
    /\ pending' = [pending EXCEPT ![b] = NoRecord]
    /\ UNCHANGED <<machine, calls, job, snapshots, log>>

\* The whole machine at an instant, between calls, once the log holds every
\* record so far.
Snapshot(b) ==
    /\ machine[b] = "up"
    /\ process[b] = "running"
    /\ \A s \in 1..seq[b] : Logged(b, s)
    /\ snapshots' = snapshots \cup {[boot |-> b, last |-> seq[b], calls |-> calls[b]]}
    /\ UNCHANGED <<machine, process, calls, seq, pending, executed, job, transit, log>>

\* The model replies without a command: the process is a zombie until the
\* harness reaps it. The exit record calls this `finish`.
Finish(b) ==
    /\ machine[b] = "up"
    /\ process[b] = "running"
    /\ process' = [process EXCEPT ![b] = "zombie"]
    /\ UNCHANGED <<machine, calls, seq, pending, executed, job, snapshots, transit, log>>

\* The machine signs its exit record, its last record, and waits for the log
\* to acknowledge it. Any call in progress is cut off.
Exit(b, reason) ==
    /\ machine[b] = "up"
    /\ LET r == Rec(b, seq[b] + 1, 0, "exit", reason)
       IN /\ machine' = [machine EXCEPT ![b] = "exiting"]
          /\ seq'     = [seq EXCEPT ![b] = seq[b] + 1]
          /\ pending' = [pending EXCEPT ![b] = r]
          /\ transit' = transit \cup {r}
    /\ UNCHANGED <<process, calls, executed, job, snapshots, log>>

\* The harness reaps the root process.
Reap(b)    == process[b] = "zombie" /\ Exit(b, "finish")
\* The machine's own wall-time limit fires.
Timeout(b) == Exit(b, "timeout")

\* The log has the exit record: the machine is gone.
Leave(b) ==
    /\ machine[b] = "exiting"
    /\ Logged(b, pending[b].seq)
    /\ machine' = [machine EXCEPT ![b] = "evicted"]
    /\ pending' = [pending EXCEPT ![b] = NoRecord]
    /\ UNCHANGED <<process, calls, seq, executed, job, snapshots, transit, log>>

\* The machine ends without an acknowledged exit record. A crash can happen
\* at any point. The host's hard kill is the same event, but it is assumed
\* to happen (see Spec): it is what makes every job end.
Evict(b) ==
    /\ machine[b] \in {"up", "exiting"}
    /\ machine' = [machine EXCEPT ![b] = "evicted"]
    /\ pending' = [pending EXCEPT ![b] = NoRecord]
    /\ UNCHANGED <<process, calls, seq, executed, job, snapshots, transit, log>>

Crash(b)    == Evict(b)
HostKill(b) == Evict(b)

-----------------------------------------------------------------------------
(* Records in transit: outside the machine, so they go on after eviction  *)
(* A record once sent stays in transit: one never delivered is lost, one  *)
(* delivered twice is duplicated, and the machine's resends add nothing.   *)

\* The log keeps a report only if the processor signed it; a recovery only
\* while the boot it recovers is not complete, and only the first for that
\* boot.
\* It keeps any other record only if its boot's key signed it, the log holds
\* that boot's report, and no recovery has taken the boot's place. It keeps
\* the first record for each place in a boot's hash chain; a duplicate or
\* resend changes nothing. First-wins matters only if KeySecret fails, so
\* TLC never exercises it.
Arrive(r) ==
    /\ IF r.type = "report"
         THEN /\ r.key = "processor"
              /\ r.body = "recovery" =>
                   /\ ~LoggedType(r.from, 0, "exit")
                   /\ ~Recovered(r.from)
         ELSE /\ r.key = r.boot
              /\ Vouched(r.boot)
              /\ ~Recovered(r.boot)
    /\ ~Logged(r.boot, r.seq)
    /\ log' = log \cup {r}
    /\ UNCHANGED <<machine, process, calls, seq, pending, executed, job, snapshots, transit>>

Deliver(r) == r \in transit /\ Arrive(r)

\* Anything on the path, the host included, can send the log any record at
\* any moment, but can sign only as itself: it can copy a record it has
\* seen and sign the copy. A forgery affects nothing until it reaches the
\* log, so it is modelled as arriving there directly.
Forge(r) == Arrive([r EXCEPT !.key = "path"])

-----------------------------------------------------------------------------

Next ==
    \/ Boot
    \/ \E b \in Boots, s \in snapshots, o \in {"fork", "recovery"} : BootFrom(b, s, o)
    \/ \E b \in Boots :
         \/ Start(b) \/ Decide(b) \/ Snapshot(b) \/ Finish(b)
         \/ Reap(b) \/ Timeout(b) \/ Leave(b) \/ Crash(b) \/ HostKill(b)
         \/ \E c \in Commands : Issue(b, c)
    \/ \E r \in transit : Deliver(r) \/ Forge(r)

Spec == Init /\ [][Next]_vars /\ \A b \in Boots : WF_vars(HostKill(b))

-----------------------------------------------------------------------------
(* Properties                                                              *)

TypeOK ==
    /\ machine \in [Boots -> {"off", "up", "exiting", "evicted"}]
    /\ process \in [Boots -> {"initial", "running", "blocked", "zombie"}]
    /\ calls \in [Boots -> 0..CallLimit]
    /\ seq \in [Boots -> 0..MaxSeq]
    /\ pending \in [Boots -> Record \cup {NoRecord}]
    /\ \A b \in Boots : executed[b] \in Seq([id : 1..CallLimit, cmd : Commands])
    /\ job \in [Boots -> Boots]
    /\ transit \subseteq Record
    /\ log \subseteq Record

\* 1. Nothing is executed before its intent is in the log.
IntentFirst ==
    \A b \in Boots : \A k \in 1..Len(executed[b]) :
        LoggedType(b, executed[b][k].id, "intent")

\* 2. The log only gains records.
LogOnlyGrows == [][log \subseteq log']_log

\* 3. Nothing whose decision is deny is executed.
DenyNeverRuns ==
    \A b \in Boots : \A k \in 1..Len(executed[b]) :
        Decision(executed[b][k].cmd) = "allow"

\* 4. A process makes at most CallLimit calls: TypeOK bounds `calls`.

\* 5. Every boot that starts ends, and its machine is evicted.
BootEnds == \A b \in Boots : (machine[b] = "up") ~> (machine[b] = "evicted")

\* 6. The log holds only what the processor signed, or a boot's own key.
OnlyMachine == \A r \in log : r.key = "processor" \/ (r.key = r.boot /\ Vouched(r.boot))

\* 7. Each call is executed at most once on a boot.
ExecutedOnce ==
    \A b \in Boots : \A j, k \in 1..Len(executed[b]) :
        j # k => executed[b][j].id # executed[b][k].id

\* 8. No boot signs two different records for one place in its hash chain,
\*    so each chain gives one order.
Unambiguous ==
    LET Seen == {r \in transit : r.key # "path"} \cup log
    IN \A r1, r2 \in Seen : (r1.boot = r2.boot /\ r1.seq = r2.seq) => r1 = r2

\* 9. An exit record saying `finish` means the model ended its turn: no
\*    call was cut off.
FinishHonest ==
    \A r \in log : (r.type = "exit" /\ r.body = "finish") => process[r.boot] = "zombie"

\* 10. A boot is complete when the log holds its exit record with no gap
\*     before it: then every call it executed has all three records logged.
Complete ==
    \A x \in log :
        (x.type = "exit" /\ \A s \in 1..x.seq - 1 : Logged(x.boot, s))
            => \A e \in 1..Len(executed[x.boot]) :
                 \A t \in CallTypes : LoggedType(x.boot, executed[x.boot][e].id, t)

\* 11. Nothing runs on a boot until the log holds its report.
ReportFirst == \A b \in Boots : process[b] # "initial" => Vouched(b)

\* 12. A fork or recovery names a record the log holds: its snapshot's last
\*     record when the snapshot was taken.
Rooted ==
    \A r \in log : (r.type = "report" /\ r.from # None) => Logged(r.from, r.last)

\* 13. A job has one outcome: a recovered boot is never complete, and no two
\*     boots of one job run at once.
OneOutcome ==
    /\ \A r \in log : (r.type = "report" /\ r.body = "recovery") =>
                        ~LoggedType(r.from, 0, "exit")
    /\ \A x, y \in Boots :
         (x # y /\ job[x] = job[y] /\ Vouched(x) /\ Vouched(y)) =>
            ~(machine[x] = "up" /\ machine[y] = "up")

=============================================================================

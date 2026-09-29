-------------------------------- MODULE cead --------------------------------
(***************************************************************************)
(* cead as a system.                                                       *)
(* Layer 1: a boot, its processes, their records and the log.              *)
(* Layer 2: snapshot, and boots from one: fork and recovery.               *)
(* Layer 3: sub-agents (`agent`), the model's processors, and meters,      *)
(*          inside one boot. cead.cfg checks boots; tree.cfg checks one    *)
(*          boot's process tree.                                           *)
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
(*   Descendants     A process can signal only its descendants.            *)
(*                   Both modes: a PID namespace per spawn.                *)
(* Availability is the host's and the scheduler's in both modes: the host  *)
(* can always stop a job; the scheduler decides when a ready process runs. *)
(* Everything on the path, the host included, is a Dolev-Yao network: it   *)
(* can lose, delay, replay and forge records, but signs only as itself.    *)
(***************************************************************************)
EXTENDS Naturals, Sequences, FiniteSets

CONSTANTS
    Commands,    \* what the model can write; the spec never sees shell text
    Policy,      \* the commands the policy denies; {} is permit-all
    CallLimit,   \* the limit on calls for one process
    Depth,       \* the limit on depth for the root process
    MeterCap,    \* the root's meter, and the most `agent` can cap a child's at
    Rights,      \* what descriptors the root holds rights to
    Processors,  \* how many of a boot's processes the model can run at once
    Procs,       \* model values: process slots in a boot
    RootProc,    \* the process `cead run` starts
    Replies,     \* what the model can reply without a command
    Boots,       \* model values: each boot, which is also its key
    Root,        \* the boot `cead run` starts
    NoRecord     \* a model value: no record awaiting acknowledgment

ASSUME /\ Policy \subseteq Commands
       /\ {CallLimit, Depth, MeterCap, Processors} \subseteq Nat
       /\ RootProc \in Procs
       /\ Root \in Boots

Decision(c) == IF c \in Policy THEN "deny" ELSE "allow"

CallTypes == {"intent", "decision", "witness"}          \* one call's records
Reasons   == {"finish", "meter", "limit", "timeout"}    \* why a process or boot ended
Origins   == {"run", "fork", "recovery"}                \* what a report says started its boot
Signers   == Boots \cup {"path", "processor"}           \* the processor signs only reports
MaxId     == Cardinality(Procs) * CallLimit             \* every call of every process
MaxSeq    == 3 * MaxId + 2                              \* the report, every call's records, the exit
None      == "none"                                     \* no process, snapshot or reply
Live      == {"ready", "running", "blocked"}

\* One record of a boot. `seq` is its place in the boot's sequence: the
\* order the machine sent it, whatever order it arrives in. A report (seq 1,
\* id 0) names its boot, whose key signs the rest, what started it, and for
\* a fork or recovery the snapshot it booted from: that boot and its last
\* record. A call's intent, decision and witness carry its id, its command
\* and the process that made it; a decision that spawns a process names it
\* as `child`, so the log holds the process tree. The exit record carries
\* id 0, why the boot ended, and the root process's reply if it finished:
\* the answer, signed.
Record == [boot : Boots, seq : 1..MaxSeq, id : 0..MaxId,
           type : CallTypes \cup {"report", "exit"},
           body : Commands \cup Reasons \cup Origins, key : Signers,
           from : Boots \cup {None}, last : 0..MaxSeq, reply : Replies \cup {None},
           proc : Procs \cup {None}, child : Procs \cup {None}]

\* One process, as the harness holds it. `cap` is the meter it was given,
\* `meter` what remains; `waits` is the child it waits for in the foreground;
\* `status` is why it ended, `by` the process that killed it, and `reply`
\* what it replied if it finished.
Proc == [state : {"unused", "zombie", "reaped"} \cup Live,
         parent : Procs \cup {None}, calls : 0..CallLimit,
         cap : 0..MeterCap, meter : 0..MeterCap, depth : 0..Depth,
         rights : SUBSET Rights, waits : Procs \cup {None},
         status : Reasons \cup {"killed", None}, by : Procs \cup {None},
         reply : Replies \cup {None}]

Unused == [state |-> "unused", parent |-> None, calls |-> 0, cap |-> 0, meter |-> 0,
           depth |-> 0, rights |-> {}, waits |-> None, status |-> None, by |-> None,
           reply |-> None]
Spawned(parent, cap, depth, rights) ==
          [state |-> "ready", parent |-> parent, calls |-> 0, cap |-> cap, meter |-> cap,
           depth |-> depth, rights |-> rights, waits |-> None, status |-> None, by |-> None,
           reply |-> None]
RootTable == [p \in Procs |-> IF p = RootProc THEN Spawned(None, MeterCap, Depth, Rights)
                                              ELSE Unused]

VARIABLES
    machine,    \* per boot: "off", "booting", "up", "exiting", "evicted"
    ps,         \* per boot and process: a Proc
    intent,     \* per boot and process: the intent awaiting acknowledgment, or NoRecord
    ids,        \* per boot: the last call id
    seq,        \* per boot: the machine's last sequence number
    pending,    \* per boot: the report or exit record awaiting acknowledgment, or NoRecord
    executed,   \* per boot: what the kernel ran, in order, and in which process: the truth
    unwitnessed, \* per boot: calls executed whose command has not yet ended
    job,        \* per boot: the boot that started its job
    snapshots,  \* every snapshot taken: a boot, its last record, its processes
    transit,    \* every record sent: each can be lost, delayed, reordered, duplicated
    log         \* held outside the machine: a set of records

vars == <<machine, ps, intent, ids, seq, pending, executed, unwitnessed, job, snapshots,
          transit, log>>

Rec(b, s, i, t, x, p) == [boot |-> b, seq |-> s, id |-> i, type |-> t, body |-> x,
                          key |-> b, from |-> None, last |-> 0, reply |-> None,
                          proc |-> p, child |-> None]
Report(b, o, f, l) == [boot |-> b, seq |-> 1, id |-> 0, type |-> "report", body |-> o,
                       key |-> "processor", from |-> f, last |-> l, reply |-> None,
                       proc |-> None, child |-> None]
Logged(b, s)        == \E r \in log : r.boot = b /\ r.seq = s
LoggedType(b, i, t) == \E r \in log : r.boot = b /\ r.id = i /\ r.type = t
\* The log holds boot b's report: b's key is vouched for.
Vouched(b)          == Logged(b, 1)
\* The log holds a report recovering boot b.
Recovered(b)        == \E r \in log : r.type = "report" /\ r.body = "recovery" /\ r.from = b
\* Boot b is evicted without its exit record in the log.
Unknown(b)          == machine[b] = "evicted" /\ ~\E r \in log : r.boot = b /\ r.type = "exit"

RECURSIVE Ancestors(_, _)
Ancestors(b, p) == IF ps[b, p].parent = None THEN {}
                   ELSE {ps[b, p].parent} \cup Ancestors(b, ps[b, p].parent)
Descendants(b, p) == {q \in Procs : p \in Ancestors(b, q)}
Running(b)        == {p \in Procs : ps[b, p].state = "running"}
\* Every meter from p up to the root has a unit left.
Chargeable(b, p)  == \A a \in {p} \cup Ancestors(b, p) : ps[b, a].meter >= 1

RECURSIVE CallsIn(_, _)
CallsIn(b, S) == IF S = {} THEN 0
                 ELSE LET p == CHOOSE p \in S : TRUE IN ps[b, p].calls + CallsIn(b, S \ {p})

\* Boot b's processes with p and its live descendants ended: p for `why`,
\* the rest killed by p. Their calls in progress are cut off.
Ended(b, p, why) ==
    LET T == {p} \cup {q \in Descendants(b, p) : ps[b, q].state \in Live}
    IN [x \in Boots \X Procs |->
          IF x[1] = b /\ x[2] \in T
            THEN [ps[x] EXCEPT !.state = "zombie", !.waits = None,
                                !.status = IF x[2] = p THEN why ELSE "killed",
                                !.by = IF x[2] = p THEN @ ELSE p]
            ELSE ps[x]]
CutOff(b, p) ==
    [x \in Boots \X Procs |->
       IF x[1] = b /\ x[2] \in {p} \cup Descendants(b, p) THEN NoRecord ELSE intent[x]]

-----------------------------------------------------------------------------
(* A boot                                                                  *)

Init ==
    /\ machine   = [b \in Boots |-> "off"]
    /\ ps        = [x \in Boots \X Procs |-> Unused]
    /\ intent    = [x \in Boots \X Procs |-> NoRecord]
    /\ ids       = [b \in Boots |-> 0]
    /\ seq       = [b \in Boots |-> 0]
    /\ pending   = [b \in Boots |-> NoRecord]
    /\ executed  = [b \in Boots |-> <<>>]
    /\ unwitnessed = [b \in Boots |-> {}]
    /\ job       = [b \in Boots |-> b]
    /\ snapshots = {}
    /\ transit   = {}
    /\ log       = {}

\* The VMM starts boot b with processes `t`: it makes its key and sends its
\* report, which awaits acknowledgment.
Begin(b, r, t, i, j) ==
    /\ machine' = [machine EXCEPT ![b] = "booting"]
    /\ ps'      = [x \in Boots \X Procs |-> IF x[1] = b THEN t[x[2]] ELSE ps[x]]
    /\ ids'     = [ids EXCEPT ![b] = i]
    /\ seq'     = [seq EXCEPT ![b] = 1]
    /\ pending' = [pending EXCEPT ![b] = r]
    /\ job'     = [job EXCEPT ![b] = j]
    /\ transit' = transit \cup {r}
    /\ unwitnessed' = [unwitnessed EXCEPT ![b] = {}]
    /\ UNCHANGED <<intent, executed, snapshots, log>>

\* `cead run` boots the root.
Boot == machine[Root] = "off" /\ Begin(Root, Report(Root, "run", None, 0), RootTable, 0, Root)

\* A boot from a snapshot. A fork starts a new job, whenever anyone asks;
\* a recovery continues the snapshot's job, once its boot is unknown.
BootFrom(b, s, o) ==
    /\ b # Root
    /\ machine[b] = "off"
    /\ o = "recovery" => Unknown(s.boot)
    /\ Begin(b, Report(b, o, s.boot, s.last), s.procs, s.ids,
             IF o = "fork" THEN b ELSE job[s.boot])

\* The log holds the report: init assembles the view, the harness runs.
\* Nothing runs on a boot the log has not heard of.
Start(b) ==
    /\ machine[b] = "booting"
    /\ Logged(b, 1)
    /\ machine' = [machine EXCEPT ![b] = "up"]
    /\ pending' = [pending EXCEPT ![b] = NoRecord]
    /\ UNCHANGED <<unwitnessed, ps, intent, ids, seq, executed, job, snapshots, transit, log>>

\* The whole machine at an instant: no call in progress, and the log holds
\* every record so far. A process that was running is ready: its inference
\* does not survive the snapshot.
Snapshot(b) ==
    /\ machine[b] = "up"
    /\ \A p \in Procs : intent[b, p] = NoRecord
    /\ unwitnessed[b] = {}
    /\ \A s \in 1..seq[b] : Logged(b, s)
    /\ snapshots' = snapshots \cup
         {[boot |-> b, last |-> seq[b], ids |-> ids[b],
           procs |-> [p \in Procs |-> IF ps[b, p].state = "running"
                                        THEN [ps[b, p] EXCEPT !.state = "ready"]
                                        ELSE ps[b, p]]]}
    /\ UNCHANGED <<unwitnessed, machine, ps, intent, ids, seq, pending, executed, job, transit, log>>

\* The root process has ended and every command has ended and been
\* witnessed: the machine signs its exit record, its last record, with the
\* root's reason and reply, and waits for the log to acknowledge it. The exit
\* record never hides a gap.
Reap(b) ==
    /\ machine[b] = "up"
    /\ ps[b, RootProc].state = "zombie"
    /\ unwitnessed[b] = {}
    /\ LET r == [Rec(b, seq[b] + 1, 0, "exit", ps[b, RootProc].status, None) EXCEPT
                    !.reply = ps[b, RootProc].reply]
       IN /\ machine' = [machine EXCEPT ![b] = "exiting"]
          /\ seq'     = [seq EXCEPT ![b] = seq[b] + 1]
          /\ pending' = [pending EXCEPT ![b] = r]
          /\ transit' = transit \cup {r}
    /\ UNCHANGED <<unwitnessed, ps, intent, ids, executed, job, snapshots, log>>

\* The job's wall-time limit fires: the root process ends, killing every
\* process below it. Their commands end and are witnessed; then Reap.
Timeout(b) ==
    /\ machine[b] = "up"
    /\ ps[b, RootProc].state \in Live
    /\ ps' = Ended(b, RootProc, "timeout")
    /\ intent' = CutOff(b, RootProc)
    /\ UNCHANGED <<unwitnessed, machine, ids, seq, pending, executed, job, snapshots, transit, log>>

\* The log has the exit record: the machine is gone.
Leave(b) ==
    /\ machine[b] = "exiting"
    /\ Logged(b, pending[b].seq)
    /\ machine' = [machine EXCEPT ![b] = "evicted"]
    /\ pending' = [pending EXCEPT ![b] = NoRecord]
    /\ UNCHANGED <<unwitnessed, ps, intent, ids, seq, executed, job, snapshots, transit, log>>

\* The machine ends without an acknowledged exit record. A crash can happen
\* at any point. The host's hard kill is the same event, but it is assumed
\* to happen (see Spec): it is what makes every job end.
Evict(b) ==
    /\ machine[b] \in {"booting", "up", "exiting"}
    /\ machine' = [machine EXCEPT ![b] = "evicted"]
    /\ pending' = [pending EXCEPT ![b] = NoRecord]
    /\ UNCHANGED <<unwitnessed, ps, intent, ids, seq, executed, job, snapshots, transit, log>>

Crash(b)    == Evict(b)
HostKill(b) == Evict(b)

-----------------------------------------------------------------------------
(* A boot's processes                                                      *)

\* The scheduler gives a ready process one of the model's processors.
Dispatch(b, p) ==
    /\ machine[b] = "up"
    /\ ps[b, p].state = "ready"
    /\ Cardinality(Running(b)) < Processors
    /\ ps' = [ps EXCEPT ![b, p].state = "running"]
    /\ UNCHANGED <<unwitnessed, machine, intent, ids, seq, pending, executed, job, snapshots, transit, log>>

\* The processor returns a command. Its unit is charged to every meter from
\* the process up to the root; the process releases the processor, blocks,
\* and sends the intent, which awaits acknowledgment.
Issue(b, p, c) ==
    /\ machine[b] = "up"
    /\ ps[b, p].state = "running"
    /\ ps[b, p].calls < CallLimit
    /\ Chargeable(b, p)
    /\ LET r == Rec(b, seq[b] + 1, ids[b] + 1, "intent", c, p)
           A == {p} \cup Ancestors(b, p)
       IN /\ ps' = [x \in Boots \X Procs |->
                      IF x[1] = b /\ x[2] \in A
                        THEN [ps[x] EXCEPT !.meter = @ - 1,
                                           !.calls = IF x[2] = p THEN @ + 1 ELSE @,
                                           !.state = IF x[2] = p THEN "blocked" ELSE @]
                        ELSE ps[x]]
          /\ intent'  = [intent EXCEPT ![b, p] = r]
          /\ ids'     = [ids EXCEPT ![b] = ids[b] + 1]
          /\ seq'     = [seq EXCEPT ![b] = seq[b] + 1]
          /\ transit' = transit \cup {r}
    /\ UNCHANGED <<unwitnessed, machine, pending, executed, job, snapshots, log>>

\* The log has acknowledged the intent: the harness checks the call against
\* policy and sends the decision. Deny returns to the model. Allow starts
\* the command; the process stays blocked until it ends (Witness).
\* `agent` spawns a child in the foreground (the caller waits) or the
\* background; it fails if the caller's depth is spent or no slot is free.
\* `kill` ends one of the caller's live children and its descendants.
Decide(b, p) ==
    /\ machine[b] = "up"
    /\ ps[b, p].state = "blocked"
    /\ intent[b, p] # NoRecord
    /\ Logged(b, intent[b, p].seq)
    /\ LET c == intent[b, p].body
           i == intent[b, p].id
           s == seq[b]
           me == ps[b, p]
           Free == {q \in Procs : ps[b, q].state = "unused"}
           Kids == {q \in Procs : ps[b, q].parent = p /\ ps[b, q].state \in Live}
           D(q) == [Rec(b, s + 1, i, "decision", c, p) EXCEPT !.child = q]
       IN /\ seq' = [seq EXCEPT ![b] = s + 1]
          /\ IF Decision(c) = "allow"
               THEN /\ executed' = [executed EXCEPT ![b] = Append(@, [id |-> i, cmd |-> c, proc |-> p])]
                    /\ unwitnessed' = [unwitnessed EXCEPT ![b] = @ \cup {[id |-> i, cmd |-> c, proc |-> p]}]
                    /\ IF c = "agent" /\ me.depth > 0 /\ Free # {}
                         THEN \E q \in Free, m \in 1..MeterCap, R \in SUBSET me.rights,
                                 fg \in BOOLEAN :
                                LET t == [ps EXCEPT ![b, q] = Spawned(p, m, me.depth - 1, R)]
                                IN /\ ps' = IF fg THEN [t EXCEPT ![b, p].waits = q] ELSE t
                                   /\ transit' = transit \cup {D(q)}
                       ELSE IF c = "kill" /\ Kids # {}
                         THEN \E q \in Kids :
                                LET t == [Ended(b, q, "killed") EXCEPT ![b, q].by = p]
                                IN /\ ps' = t
                                   /\ intent' = [CutOff(b, q) EXCEPT ![b, p] = NoRecord]
                                   /\ transit' = transit \cup {D(None)}
                       ELSE ps' = ps /\ transit' = transit \cup {D(None)}
               ELSE /\ executed' = executed
                    /\ unwitnessed' = unwitnessed
                    /\ transit' = transit \cup {D(None)}
                    /\ ps' = [ps EXCEPT ![b, p].state = "ready"]
          /\ (c # "kill" \/ Decision(c) = "deny" \/ Kids = {}) =>
               intent' = [intent EXCEPT ![b, p] = NoRecord]
    /\ UNCHANGED <<machine, ids, pending, job, snapshots, log>>

\* A command ends, however it ends (exit, signal, a kill from an ancestor
\* or the harness); a foreground `agent` ends when its child is reaped. The
\* tracer's witness goes through the harness, which sequences it, and the
\* process, if still live, is ready again. A killed process's commands are
\* witnessed too.
Witness(b, e) ==
    /\ machine[b] = "up"
    /\ e \in unwitnessed[b]
    /\ ps[b, e.proc].waits = None
    /\ unwitnessed' = [unwitnessed EXCEPT ![b] = @ \ {e}]
    /\ seq' = [seq EXCEPT ![b] = seq[b] + 1]
    /\ transit' = transit \cup {Rec(b, seq[b] + 1, e.id, "witness", e.cmd, e.proc)}
    /\ ps' = IF ps[b, e.proc].state = "blocked"
               THEN [ps EXCEPT ![b, e.proc].state = "ready"] ELSE ps
    /\ UNCHANGED <<machine, intent, ids, pending, executed, job, snapshots, log>>

\* The model replies without a command: the process ends, and its running
\* descendants are killed. The reply is its stdout.
Finish(b, p, y) ==
    /\ machine[b] = "up"
    /\ ps[b, p].state = "running"
    /\ ps' = [Ended(b, p, "finish") EXCEPT ![b, p].reply = y]
    /\ intent' = CutOff(b, p)
    /\ UNCHANGED <<unwitnessed, machine, ids, seq, pending, executed, job, snapshots, transit, log>>

\* The processor returns a command the process cannot pay for, or its call
\* limit is reached: it ends, and its descendants are killed.
Exhaust(b, p) ==
    /\ machine[b] = "up"
    /\ ps[b, p].state = "running"
    /\ \/ ~Chargeable(b, p) /\ ps' = Ended(b, p, "meter")
       \/ ps[b, p].calls = CallLimit /\ ps' = Ended(b, p, "limit")
    /\ intent' = CutOff(b, p)
    /\ UNCHANGED <<unwitnessed, machine, ids, seq, pending, executed, job, snapshots, transit, log>>

\* The harness reaps an ended child; a parent's foreground `agent` waiting
\* on it can now end (Witness).
ReapChild(b, q) ==
    /\ machine[b] = "up"
    /\ q # RootProc
    /\ ps[b, q].state = "zombie"
    /\ LET p == ps[b, q].parent
           t == [ps EXCEPT ![b, q].state = "reaped"]
       IN ps' = IF ps[b, p].waits = q THEN [t EXCEPT ![b, p].waits = None] ELSE t
    /\ UNCHANGED <<unwitnessed, machine, intent, ids, seq, pending, executed, job, snapshots, transit, log>>

-----------------------------------------------------------------------------
(* Records in transit: outside the machine, so they go on after eviction  *)
(* A record once sent stays in transit: one never delivered is lost, one  *)
(* delivered twice is duplicated, and the machine's resends add nothing.   *)

\* The log keeps a report only if the processor signed it; a recovery only
\* while the boot it recovers is not complete, and only the first for that
\* boot. It keeps any other record only if its boot's key signed it, the log
\* holds that boot's report, and no recovery has taken the boot's place. It
\* keeps the first record for each place in a boot's sequence; a
\* duplicate or resend changes nothing. First-wins matters only if
\* KeySecret fails, so TLC never exercises it.
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
    /\ UNCHANGED <<unwitnessed, machine, ps, intent, ids, seq, pending, executed, job, snapshots, transit>>

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
         \/ Start(b) \/ Snapshot(b) \/ Reap(b) \/ Timeout(b) \/ Leave(b)
         \/ Crash(b) \/ HostKill(b)
         \/ \E p \in Procs :
              \/ Dispatch(b, p) \/ Decide(b, p) \/ Exhaust(b, p) \/ ReapChild(b, p)
              \/ \E c \in Commands : Issue(b, p, c)
              \/ \E y \in Replies : Finish(b, p, y)
         \/ \E e \in unwitnessed[b] : Witness(b, e)
    \/ \E r \in transit : Deliver(r) \/ Forge(r)

Spec == Init /\ [][Next]_vars /\ \A b \in Boots : WF_vars(HostKill(b))

-----------------------------------------------------------------------------
(* Properties                                                              *)

TypeOK ==
    /\ machine \in [Boots -> {"off", "booting", "up", "exiting", "evicted"}]
    /\ ps \in [Boots \X Procs -> Proc]
    /\ intent \in [Boots \X Procs -> Record \cup {NoRecord}]
    /\ ids \in [Boots -> 0..MaxId]
    /\ seq \in [Boots -> 0..MaxSeq]
    /\ pending \in [Boots -> Record \cup {NoRecord}]
    /\ \A b \in Boots : executed[b] \in Seq([id : 1..MaxId, cmd : Commands, proc : Procs])
    /\ unwitnessed \in [Boots -> SUBSET [id : 1..MaxId, cmd : Commands, proc : Procs]]
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
BootEnds == \A b \in Boots : (machine[b] = "booting") ~> (machine[b] = "evicted")

\* 6. The log holds only what the processor signed, or a boot's own key.
OnlyMachine == \A r \in log : r.key = "processor" \/ (r.key = r.boot /\ Vouched(r.boot))

\* 7. Each call is executed at most once on a boot.
ExecutedOnce ==
    \A b \in Boots : \A j, k \in 1..Len(executed[b]) :
        j # k => executed[b][j].id # executed[b][k].id

\* 8. No boot signs two different records for one place in its sequence,
\*    so each boot gives one order.
Unambiguous ==
    LET Seen == {r \in transit : r.key # "path"} \cup log
    IN \A r1, r2 \in Seen : (r1.boot = r2.boot /\ r1.seq = r2.seq) => r1 = r2

\* 9. An exit record saying `finish` means the root process ended its turn,
\*    was not cut off, and replied what the record says.
FinishHonest ==
    \A r \in log : (r.type = "exit" /\ r.body = "finish") =>
                     /\ ps[r.boot, RootProc].status = "finish"
                     /\ r.reply = ps[r.boot, RootProc].reply

\* 10. A boot is complete when the log holds its exit record with no gap
\*     before it: then every call it executed has all three records logged.
Complete ==
    \A x \in log :
        (x.type = "exit" /\ \A s \in 1..x.seq - 1 : Logged(x.boot, s))
            => \A e \in 1..Len(executed[x.boot]) :
                 \A t \in CallTypes : LoggedType(x.boot, executed[x.boot][e].id, t)

\* 11. Nothing runs on a boot until the log holds its report.
ReportFirst == \A b \in Boots : machine[b] \in {"up", "exiting"} => Vouched(b)

\* 12. A fork or recovery names a record the log holds: its snapshot's last
\*     record.
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

\* 14. The model runs at most Processors of a boot's processes at once.
OnProcessors == \A b \in Boots : Cardinality(Running(b)) <= Processors

\* 15. No process tree spends more than its root's meter: every call below a
\*     process was charged to it.
WithinMeter ==
    \A b \in Boots, p \in Procs :
        ps[b, p].state # "unused" => CallsIn(b, {p} \cup Descendants(b, p)) <= ps[b, p].cap

\* 16. A child holds no right and no depth its parent lacked.
Attenuated ==
    \A b \in Boots, p \in Procs :
        LET q == ps[b, p].parent
        IN (ps[b, p].state # "unused" /\ q # None) =>
             /\ ps[b, p].rights \subseteq ps[b, q].rights
             /\ ps[b, p].depth < ps[b, q].depth

\* 17. A process is killed only by one of its ancestors.
KillReach ==
    \A b \in Boots, p \in Procs :
        ps[b, p].status = "killed" => ps[b, p].by \in Ancestors(b, p)

\* 18. A live process is blocked exactly while it waits: on its intent's
\*     decision, or on its command's end, a foreground `agent` on its child.
BlockedWaits ==
    \A b \in Boots, p \in Procs :
        ps[b, p].state \in Live =>
            /\ ps[b, p].state = "blocked" <=>
                 intent[b, p] # NoRecord \/ \E e \in unwitnessed[b] : e.proc = p
            /\ ps[b, p].waits # None =>
                 ps[b, p].state = "blocked" /\ ps[b, ps[b, p].waits].state \in Live \cup {"zombie"}

\* The records boot b sent through its record n, and, if it booted from a
\* snapshot, that boot's records through the snapshot's last record.
RECURSIVE Before(_, _)
Before(b, n) ==
    LET Sent == {r \in transit \cup log : r.key # "path"}
        R == {r \in Sent : r.boot = b /\ r.type = "report"}
        Mine == {r \in Sent : r.boot = b /\ r.seq <= n}
    IN IF R = {} THEN Mine
       ELSE LET x == CHOOSE x \in R : TRUE
            IN IF x.from = None THEN Mine ELSE Mine \cup Before(x.from, x.last)

\* 19. Every logged call names the process that ran it, and a process other
\*     than the root was spawned earlier in its boot's records, by a
\*     decision its parent made: the log holds the process tree.
ProcessTree ==
    \A r \in log :
        r.type \in CallTypes =>
            /\ r.proc \in Procs
            /\ \A k \in 1..Len(executed[r.boot]) :
                 executed[r.boot][k].id = r.id => executed[r.boot][k].proc = r.proc
            /\ r.proc # RootProc =>
                 \E d \in Before(r.boot, r.seq - 1) :
                    /\ d.type = "decision" /\ d.child = r.proc
                    /\ d.proc = ps[r.boot, r.proc].parent

=============================================================================

-------------------------------- MODULE cead --------------------------------
(***************************************************************************)
(* cead as a system. Layer 1: one job, one boot, one process.              *)
(***************************************************************************)
EXTENDS Naturals, Sequences

CONSTANTS
    Commands,   \* what the model can write; the spec never sees shell text
    Policy,     \* the commands the policy denies; {} is permit-all
    CallLimit,  \* the limit on calls for one process
    NoMsg       \* a model value: no message awaiting acknowledgment

ASSUME /\ Policy \subseteq Commands
       /\ CallLimit \in Nat

Decision(c) == IF c \in Policy THEN "deny" ELSE "allow"

Parts   == {"intent", "decision", "witness"}  \* of one call's audit record
Reasons == {"finish", "timeout"}              \* what an exit record can say
Senders == {"machine", "path"}                \* whose key signed a message
MaxSeq  == 3 * CallLimit + 1                  \* every part of every call, then the exit

\* One link in the machine's chain. `seq` is its place in the chain: the
\* order the machine sent it, whatever order it arrives in. An audit record
\* part carries its call's id and command; the exit record carries id 0 and
\* how the machine exited.
Message == [seq : 1..MaxSeq, id : 0..CallLimit, part : Parts \cup {"exit"},
            body : Commands \cup Reasons, sender : Senders]

VARIABLES
    machine,   \* "off", "up", "exiting", "evicted"
    process,   \* "initial", "running", "blocked", "zombie"
    calls,     \* calls issued so far; the current call's id
    seq,       \* the machine's last sequence number
    pending,   \* the message awaiting the log's acknowledgment, or NoMsg
    executed,  \* what the kernel ran, in order: the truth
    messages,  \* in transit: can be lost, delayed, reordered, duplicated
    log        \* held outside the machine: the record, a set of links

vars == <<machine, process, calls, seq, pending, executed, messages, log>>

Msg(s, i, p, b)  == [seq |-> s, id |-> i, part |-> p, body |-> b, sender |-> "machine"]
Logged(s)        == \E m \in log : m.seq = s
LoggedPart(i, p) == \E m \in log : m.id = i /\ m.part = p

-----------------------------------------------------------------------------
(* The machine and its process                                             *)

Init ==
    /\ machine  = "off"
    /\ process  = "initial"
    /\ calls    = 0
    /\ seq      = 0
    /\ pending  = NoMsg
    /\ executed = <<>>
    /\ messages = {}
    /\ log      = {}

\* The VMM boots the machine, init assembles the view, the harness starts
\* the root process.
Boot ==
    /\ machine = "off"
    /\ machine' = "up"
    /\ process' = "running"
    /\ UNCHANGED <<calls, seq, pending, executed, messages, log>>

\* The model issues a call. The harness blocks the process and sends the
\* intent, which awaits acknowledgment.
Issue(c) ==
    /\ machine = "up"
    /\ process = "running"
    /\ calls < CallLimit
    /\ process' = "blocked"
    /\ calls' = calls + 1
    /\ seq' = seq + 1
    /\ pending' = Msg(seq + 1, calls + 1, "intent", c)
    /\ messages' = messages \cup {pending'}
    /\ UNCHANGED <<machine, executed, log>>

\* The log has not acknowledged the pending message: send it again.
Resend ==
    /\ machine \in {"up", "exiting"}
    /\ pending # NoMsg
    /\ ~Logged(pending.seq)
    /\ messages' = messages \cup {pending}
    /\ UNCHANGED <<machine, process, calls, seq, pending, executed, log>>

\* The log has acknowledged the intent: the harness checks the call against
\* policy. Deny returns to the model. Allow runs the command, and the tracer
\* witnesses it; both parts go through the harness, which sequences them.
Decide ==
    /\ machine = "up"
    /\ process = "blocked"
    /\ pending # NoMsg
    /\ pending.part = "intent"
    /\ Logged(pending.seq)
    /\ LET c == pending.body
           i == pending.id
       IN IF Decision(c) = "allow"
            THEN /\ executed' = Append(executed, [id |-> i, cmd |-> c])
                 /\ messages' = messages \cup
                      {Msg(seq + 1, i, "decision", c), Msg(seq + 2, i, "witness", c)}
                 /\ seq' = seq + 2
            ELSE /\ executed' = executed
                 /\ messages' = messages \cup {Msg(seq + 1, i, "decision", c)}
                 /\ seq' = seq + 1
    /\ process' = "running"
    /\ pending' = NoMsg
    /\ UNCHANGED <<machine, calls, log>>

\* The model calls `finish`: the process is a zombie until the harness reaps it.
Finish ==
    /\ machine = "up"
    /\ process = "running"
    /\ process' = "zombie"
    /\ UNCHANGED <<machine, calls, seq, pending, executed, messages, log>>

\* The machine signs its exit record, the last link in its chain, and waits
\* for the log to acknowledge it. Any call in progress is cut off.
Exit(reason) ==
    /\ machine = "up"
    /\ machine' = "exiting"
    /\ seq' = seq + 1
    /\ pending' = Msg(seq + 1, 0, "exit", reason)
    /\ messages' = messages \cup {pending'}
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
    /\ pending' = NoMsg
    /\ UNCHANGED <<process, calls, seq, executed, messages, log>>

\* The machine ends without an acknowledged exit record. A crash can happen
\* at any point. The host's hard kill is the same event, but it is assumed
\* to happen (see Spec): it is what makes every job end.
Evict ==
    /\ machine \in {"up", "exiting"}
    /\ machine' = "evicted"
    /\ pending' = NoMsg
    /\ UNCHANGED <<process, calls, seq, executed, messages, log>>

Crash    == Evict
HostKill == Evict

-----------------------------------------------------------------------------
(* Messages: outside the machine, so they go on after it is evicted        *)

\* The log keeps a message only if the machine signed it, and keeps the first
\* message for each place in the chain. A duplicate or resend changes nothing.
\* First-wins matters only if the machine's key is stolen, which this spec
\* assumes away, so TLC never exercises it.
Arrive(m) ==
    /\ m.sender = "machine"
    /\ ~Logged(m.seq)
    /\ log' = log \cup {m}
    /\ UNCHANGED <<machine, process, calls, seq, pending, executed, messages>>

Deliver(m) == m \in messages /\ Arrive(m)

Lose(m) ==
    /\ m \in messages
    /\ messages' = messages \ {m}
    /\ UNCHANGED <<machine, process, calls, seq, pending, executed, log>>

\* Anything on the path, the host included, can send the log a message at
\* any moment, but can sign only as itself. A forgery affects nothing until
\* it reaches the log, so it is modelled as arriving there directly.
Forge(m) == m.sender = "path" /\ Arrive(m)

-----------------------------------------------------------------------------

Next ==
    \/ Boot
    \/ \E c \in Commands : Issue(c)
    \/ Resend
    \/ Decide
    \/ Finish
    \/ Reap
    \/ Timeout
    \/ Leave
    \/ Crash
    \/ HostKill
    \/ \E m \in messages : Deliver(m) \/ Lose(m)
    \/ \E m \in Message : Forge(m)

Spec == Init /\ [][Next]_vars /\ WF_vars(HostKill)

-----------------------------------------------------------------------------
(* Properties                                                              *)

TypeOK ==
    /\ machine \in {"off", "up", "exiting", "evicted"}
    /\ process \in {"initial", "running", "blocked", "zombie"}
    /\ calls \in Nat
    /\ seq \in Nat
    /\ pending \in Message \cup {NoMsg}
    /\ executed \in Seq([id : 1..CallLimit, cmd : Commands])
    /\ messages \subseteq Message
    /\ log \subseteq Message

\* 1. Nothing is executed before its intent is in the log.
IntentFirst == \A k \in 1..Len(executed) : LoggedPart(executed[k].id, "intent")

\* 2. The log only gains links.
LogOnlyGrows == [][log \subseteq log']_log

\* 3. Nothing whose decision is deny is executed.
DenyNeverRuns == \A k \in 1..Len(executed) : Decision(executed[k].cmd) = "allow"

\* 4. A process makes at most CallLimit calls.
WithinLimit == calls <= CallLimit

\* 5. Every job that starts ends, and its machine is evicted.
JobEnds == (machine = "up") ~> (machine = "evicted")

\* 6. The log holds only what the machine signed.
OnlyMachine == \A m \in log : m.sender = "machine"

\* 7. Each call is executed at most once.
ExecutedOnce ==
    \A j, k \in 1..Len(executed) : j # k => executed[j].id # executed[k].id

\* 8. The machine never signs two different messages for one place in the
\*    chain, so the chain gives one order.
Unambiguous ==
    LET Seen == {m \in messages : m.sender = "machine"} \cup
                log
    IN \A m1, m2 \in Seen : m1.seq = m2.seq => m1 = m2

\* 9. An exit record saying `finish` means the model called `finish`: no
\*    call was cut off.
FinishHonest ==
    \A m \in log : (m.part = "exit" /\ m.body = "finish") => process = "zombie"

\* 10. An exit record with an unbroken chain before it proves the log
\*     complete: every executed call has all three parts logged.
Complete ==
    \A x \in log :
        (x.part = "exit" /\ \A s \in 1..x.seq - 1 : Logged(s))
            => \A e \in 1..Len(executed) :
                 \A p \in Parts : LoggedPart(executed[e].id, p)

=============================================================================

import Cead.Log

/-!
A process's window, replayed from the log. The log holds every byte a window
holds (the pinned prompt and query to open it, each call's turn and what it
returned), so what the model saw on any call is a function of the records.
The harness assembles its windows by the same definition; the differential
test compares them, and the gateway's own record of each request is a
second, independent check.
-/
namespace Cead

inductive Role where
  | system
  | user
  | assistant
deriving DecidableEq

/-- One span of a window. -/
structure Span where
  role : Role
  text : Blob
deriving DecidableEq

/-- The pinned prompt, then the query, then each completed call: the model's
turn and what it returned. -/
def window (prompt query : Blob) (calls : List (Blob × Blob)) : List Span :=
  ⟨.system, prompt⟩ :: ⟨.user, query⟩ ::
    calls.flatMap fun (turn, returned) => [⟨.assistant, turn⟩, ⟨.user, returned⟩]

/-- A window only grows at its end: each call's window begins with the
previous call's, byte for byte. -/
theorem window_prefix (prompt query : Blob) (calls more : List (Blob × Blob)) :
    window prompt query calls <+: window prompt query (calls ++ more) := by
  simp [window, List.flatMap_append]

/-- The root is process 0; a spawning decision numbers the rest. -/
def Root : UInt64 := 0

section Replay
variable (log : Log) (b : Blob)

/-- The pinned prompt and the root's query, from boot `b`'s report. -/
def reportOf : Option (Blob × Blob) :=
  log.findSome? fun r =>
    if r.boot = b then
      match r.body with
      | .report _ _ _ prompt query => some (prompt, query)
      | _ => none
    else none

/-- Process `p`'s query: the root's from the report, any other's from the
decision that spawned it. -/
def queryOf (p : UInt64) : Option Blob :=
  if p = Root then (reportOf log b).map (·.2)
  else log.findSome? fun r =>
    if r.boot = b then
      match r.body with
      | .call _ _ (.decision (.spawn c q)) => if c = p then some q else none
      | _ => none
    else none

/-- Call `i`'s turn and what it returned, once the log holds both. -/
def callOf (i : UInt64) : Option (Blob × Blob) := do
  let turn ← log.findSome? fun r =>
    if r.boot = b then
      match r.body with
      | .call j _ (.intent t _) => if j = i then some t else none
      | _ => none
    else none
  let returned ← log.findSome? fun r =>
    if r.boot = b then
      match r.body with
      | .call j _ (.decision (.deny x)) | .call j _ (.witness _ _ x) =>
        if j = i then some x else none
      | _ => none
    else none
  pure (turn, returned)

/-- The ids of process `p`'s calls, in the order it made them. -/
def callIds (p : UInt64) : List UInt64 :=
  let ids := log.filterMap fun r =>
    if r.boot = b then
      match r.body with
      | .call i q (.intent ..) => if q = p then some i else none
      | _ => none
    else none
  ids.mergeSort (· ≤ ·)

/-- Process `p`'s window as the log replays it: its opening, then its
completed calls in order. -/
def replay (p : UInt64) : Option (List Span) := do
  let (prompt, _) ← reportOf log b
  let query ← queryOf log b p
  pure (window prompt query ((callIds log b p).filterMap (callOf log b)))

end Replay
end Cead

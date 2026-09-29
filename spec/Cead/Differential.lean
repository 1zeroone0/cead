import Cead.Window
import Cead.Meter

/-!
The Lean half of the differential test: random inputs through the spec,
printed one per line for `cargo test` to run through the Rust and compare.
The bridge is bytes, the interface itself.
-/
namespace Cead.Differential

def hex (b : Bytes) : String :=
  String.join (b.map fun x =>
    let s := String.ofList (Nat.toDigits 16 x.toNat)
    if s.length = 1 then "0" ++ s else s)

def byte : IO UInt8 := return (← IO.rand 0 255).toUInt8

def blob : IO Blob := do
  let n ← IO.rand 0 40
  let data ← (List.range n).mapM fun _ => byte
  if h : data.length < UInt64.size then return ⟨data, h⟩ else return ⟨[], by decide⟩

def u64 : IO UInt64 := do
  -- small values exercise the low bytes, large ones the high
  if (← IO.rand 0 1) = 0 then return (← IO.rand 0 1000).toUInt64
  else return (← IO.rand 0 (2^64 - 1)).toUInt64

def origin : IO Origin := do
  match ← IO.rand 0 2 with
  | 0 => return .run
  | 1 => return .fork (← blob) (← u64)
  | _ => return .recovery (← blob) (← u64)

def event : IO Event := do
  match ← IO.rand 0 2 with
  | 0 => return .intent (← blob) (← blob)
  | 1 =>
    match ← IO.rand 0 2 with
    | 0 => return .decision (.deny (← blob))
    | 1 => return .decision .allow
    | _ => return .decision (.spawn (← u64) (← blob))
  | _ =>
    let code ← byte
    let status := if (← IO.rand 0 1) = 0 then WaitStatus.exited code else .signaled code
    return .witness status (← blob) (← blob)

def body : IO Body := do
  match ← IO.rand 0 2 with
  | 0 =>
    let report ← blob
    let attestation := if (← IO.rand 0 1) = 0 then Attestation.unattested else .snp report
    return .report (← origin) (← blob) attestation (← blob) (← blob)
  | 1 => return .call (← u64) (← u64) (← event)
  | _ =>
    match ← IO.rand 0 3 with
    | 0 => return .exit (.finish (← blob))
    | 1 => return .exit .meter
    | 2 => return .exit .limit
    | _ => return .exit .timeout

def record : IO Record := return ⟨← blob, ← u64, ← body⟩

/-- A valid encoding, or one corrupted: a byte changed, cut short, or extended. -/
def recordBytes : IO Bytes := do
  let b := (← record).enc
  match ← IO.rand 0 3 with
  | 0 => return b
  | 1 =>
    let i ← IO.rand 0 (b.length - 1)
    return b.set i (← byte)
  | 2 => return b.take (← IO.rand 0 (b.length - 1))
  | _ => return b ++ [← byte]

/-- Each line: the input, then the encoding of what it decodes to, or `-`. -/
def records (n : Nat) : IO Unit := do
  for _ in [0:n] do
    let b ← recordBytes
    let out := match Record.dec b with
      | some r => hex r.enc
      | none => "-"
    IO.println s!"{hex b} {out}"

/-- Random spawns and charges from a root. Each line: the operation, Lean's
verdict, then every meter. -/
def meters (runs ops : Nat) : IO Unit := do
  for _ in [0:runs] do
    let cap ← IO.rand 1 10
    let mut t := Meter.root cap
    IO.println s!"root {cap}"
    for _ in [0:ops] do
      let (op, next) ← do
        if (← IO.rand 0 3) = 0 then
          let pa ← IO.rand 0 t.length
          let c ← IO.rand 1 10
          pure (s!"spawn {pa} {c}", Meter.spawn t pa c)
        else
          let q ← IO.rand 0 t.length
          pure (s!"charge {q}", Meter.charge t q)
      match next with
      | some t' =>
        t := t'
        IO.println s!"{op} ok {t.map (·.meter)}"
      | none => IO.println s!"{op} refused {t.map (·.meter)}"

def unhex (s : String) : Option Bytes :=
  let digit (c : Char) : Option Nat :=
    if '0' ≤ c ∧ c ≤ '9' then some (c.toNat - '0'.toNat)
    else if 'a' ≤ c ∧ c ≤ 'f' then some (c.toNat - 'a'.toNat + 10) else none
  let rec go : List Char → Option Bytes
    | [] => some []
    | a :: b :: rest => do
      let x ← digit a; let y ← digit b
      return (x * 16 + y).toUInt8 :: (← go rest)
    | [_] => none
  go s.toList

/-- Process `proc`'s window replayed from a log of hex-encoded records, one per
line. Each line out: the span's role, then its text in hex. -/
def replay (path : String) (boot : String) (proc : Nat) : IO UInt32 := do
  let lines := (← IO.FS.readFile path).splitOn "\n" |>.filter (· ≠ "")
  let some log := lines.mapM fun l => unhex l >>= Record.dec
    | IO.eprintln "a line is not a record"; return 65
  let some b := unhex boot
    | IO.eprintln "boot is not hex"; return 64
  if h : b.length < UInt64.size then
    match Cead.replay log ⟨b, h⟩ proc.toUInt64 with
    | some spans =>
      for sp in spans do
        let role := match sp.role with
          | .system => "system" | .user => "user" | .assistant => "assistant"
        IO.println s!"{role} {hex sp.text.data}"
      return 0
    | none => IO.eprintln "no window for that process"; return 66
  else return 64

end Cead.Differential

def main (args : List String) : IO UInt32 := do
  match args with
  | ["record", n, seed] =>
    IO.setRandSeed seed.toNat!
    Cead.Differential.records n.toNat!
    return 0
  | ["meter", runs, ops, seed] =>
    IO.setRandSeed seed.toNat!
    Cead.Differential.meters runs.toNat! ops.toNat!
    return 0
  | ["replay", log, boot, proc] => Cead.Differential.replay log boot proc.toNat!
  | _ =>
    IO.eprintln "usage: differential record COUNT SEED | meter RUNS OPS SEED | replay LOG BOOT PROC"
    return 64

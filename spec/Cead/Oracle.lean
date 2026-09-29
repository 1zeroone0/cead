import Cead.Record

/-!
The differential oracle: random inputs through the Lean spec, printed one
per line for `cargo test` to run through the Rust and compare. The bridge is
bytes, the interface itself.
-/
namespace Cead.Oracle

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
  | 0 => return .intent (← blob)
  | 1 =>
    match ← IO.rand 0 2 with
    | 0 => return .decision .deny
    | 1 => return .decision .allow
    | _ => return .decision (.spawn (← u64))
  | _ =>
    let code ← byte
    let status := if (← IO.rand 0 1) = 0 then WaitStatus.exited code else .signaled code
    return .witness status (← blob)

def body : IO Body := do
  match ← IO.rand 0 2 with
  | 0 =>
    let report ← blob
    let attestation := if (← IO.rand 0 1) = 0 then Attestation.unattested else .snp report
    return .report (← origin) (← blob) attestation
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

end Cead.Oracle

def main (args : List String) : IO UInt32 := do
  match args with
  | ["record", n, seed] =>
    IO.setRandSeed seed.toNat!
    Cead.Oracle.records n.toNat!
    return 0
  | _ =>
    IO.eprintln "usage: oracle record COUNT SEED"
    return 64

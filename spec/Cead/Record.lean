import Cead.Codec

/-!
A record, as the machine signs it: `spec/cead.tla`'s `Record` with each
field's real content. The signature covers `record.enc r`; the codec's laws
make that encoding canonical, so a signature names exactly one record.
-/
namespace Cead

open Codec

/-- What started a boot. A fork or recovery names its snapshot: that boot
and its last record. -/
inductive Origin where
  | run
  | fork (boot : Blob) (last : UInt64)
  | recovery (boot : Blob) (last : UInt64)
deriving DecidableEq

/-- What the processor signed about a boot. `unattested` is what trusted-host
mode sends: the host, not the processor, vouches for the key. -/
inductive Attestation where
  | unattested
  | snp (report : Blob)
deriving DecidableEq

/-- The outcome of checking a call against policy. A deny carries what the
call returned to the model, which ends the call. `spawn` allows an `agent` call and
names the process it starts and that process's query, which opens its
window. -/
inductive Decision where
  | deny (returned : Blob)
  | allow
  | spawn (child : UInt64) (query : Blob)
deriving DecidableEq

/-- How a command ended, as `wait(2)` reports it. -/
inductive WaitStatus where
  | exited (code : UInt8)
  | signaled (signal : UInt8)
deriving DecidableEq

/-- One call's record, sharing its id and process with the call's other two.
Together they hold what the call added to its process's window. -/
inductive Event where
  /-- The model's whole turn, and the command the harness took from it. -/
  | intent (turn : Blob) (command : Blob)
  | decision (decision : Decision)
  /-- `output` is the digest of the command's whole output; `returned` what the
  call returned to the model: the output if it fit the bound, else where it
  spilled. -/
  | witness (status : WaitStatus) (output : Blob) (returned : Blob)
deriving DecidableEq

/-- Why a boot ended: the root process's status. Only `finish` has a reply,
and the record carries its digest. -/
inductive Exit where
  | finish (reply : Blob)
  | meter
  | limit
  | timeout
deriving DecidableEq

inductive Body where
  /-- `prompt` is the pinned prompt and `query` the root's: its window opens
  with them. -/
  | report (origin : Origin) (measurement : Blob) (attestation : Attestation)
      (prompt : Blob) (query : Blob)
  /-- `proc` is the boot's number for the process that made the call. -/
  | call (id : UInt64) (proc : UInt64) (event : Event)
  | exit (exit : Exit)
deriving DecidableEq

/-- `boot` is the boot's public key, which signs the record; `seq` its place
in the boot's sequence, the report first. -/
structure Record where
  boot : Blob
  seq : UInt64
  body : Body
deriving DecidableEq

namespace Codec

def blobU64 : Codec (Blob × UInt64) := pair blob u64

private def OriginT : Fin 3 → Type
  | 0 => Unit | 1 => Blob × UInt64 | 2 => Blob × UInt64

def origin : Codec Origin :=
  iso (tagged 3 (by decide) OriginT fun | 0 => unit | 1 => blobU64 | 2 => blobU64)
    (fun | ⟨0, _⟩ => .run | ⟨1, (b, l)⟩ => .fork b l | ⟨2, (b, l)⟩ => .recovery b l)
    (fun | .run => ⟨0, ()⟩ | .fork b l => ⟨1, (b, l)⟩ | .recovery b l => ⟨2, (b, l)⟩)
    (by rintro ⟨i, x⟩; match i, x with | 0, () => rfl | 1, (_, _) => rfl | 2, (_, _) => rfl)
    (by intro o; cases o <;> rfl)

private def AttestationT : Fin 2 → Type
  | 0 => Unit | 1 => Blob

def attestation : Codec Attestation :=
  iso (tagged 2 (by decide) AttestationT fun | 0 => unit | 1 => blob)
    (fun | ⟨0, _⟩ => .unattested | ⟨1, r⟩ => .snp r)
    (fun | .unattested => ⟨0, ()⟩ | .snp r => ⟨1, r⟩)
    (by rintro ⟨i, x⟩; match i, x with | 0, () => rfl | 1, _ => rfl)
    (by intro e; cases e <;> rfl)

private def DecisionT : Fin 3 → Type
  | 0 => Blob | 1 => Unit | 2 => UInt64 × Blob

def decision : Codec Decision :=
  iso (tagged 3 (by decide) DecisionT fun | 0 => blob | 1 => unit | 2 => pair u64 blob)
    (fun | ⟨0, m⟩ => .deny m | ⟨1, _⟩ => .allow | ⟨2, (c, q)⟩ => .spawn c q)
    (fun | .deny m => ⟨0, m⟩ | .allow => ⟨1, ()⟩ | .spawn c q => ⟨2, (c, q)⟩)
    (by rintro ⟨i, x⟩; match i, x with | 0, _ => rfl | 1, () => rfl | 2, (_, _) => rfl)
    (by intro d; cases d <;> rfl)

private def u8 : Codec UInt8 :=
  iso (tag 256 (by decide)) (fun i => i.val.toUInt8) (fun b => ⟨b.toNat, b.toNat_lt⟩)
    (by intro i; apply Fin.ext; simp [Nat.toUInt8])
    (by intro b; simp [Nat.toUInt8])

private def WaitStatusT : Fin 2 → Type
  | 0 => UInt8 | 1 => UInt8

def waitStatus : Codec WaitStatus :=
  iso (tagged 2 (by decide) WaitStatusT fun | 0 => u8 | 1 => u8)
    (fun | ⟨0, c⟩ => .exited c | ⟨1, s⟩ => .signaled s)
    (fun | .exited c => ⟨0, c⟩ | .signaled s => ⟨1, s⟩)
    (by rintro ⟨i, x⟩; match i, x with | 0, _ => rfl | 1, _ => rfl)
    (by intro e; cases e <;> rfl)

private def EventT : Fin 3 → Type
  | 0 => Blob × Blob | 1 => Decision | 2 => WaitStatus × Blob × Blob

def event : Codec Event :=
  iso (tagged 3 (by decide) EventT
        fun | 0 => pair blob blob | 1 => decision | 2 => pair waitStatus (pair blob blob))
    (fun | ⟨0, (t, c)⟩ => .intent t c | ⟨1, d⟩ => .decision d
         | ⟨2, (w, o, m)⟩ => .witness w o m)
    (fun | .intent t c => ⟨0, (t, c)⟩ | .decision d => ⟨1, d⟩
         | .witness w o m => ⟨2, (w, o, m)⟩)
    (by rintro ⟨i, x⟩
        match i, x with | 0, (_, _) => rfl | 1, _ => rfl | 2, (_, _, _) => rfl)
    (by intro e; cases e <;> rfl)

private def ExitT : Fin 4 → Type
  | 0 => Blob | 1 => Unit | 2 => Unit | 3 => Unit

def exit : Codec Exit :=
  iso (tagged 4 (by decide) ExitT fun | 0 => blob | 1 => unit | 2 => unit | 3 => unit)
    (fun | ⟨0, r⟩ => .finish r | ⟨1, _⟩ => .meter | ⟨2, _⟩ => .limit | ⟨3, _⟩ => .timeout)
    (fun | .finish r => ⟨0, r⟩ | .meter => ⟨1, ()⟩ | .limit => ⟨2, ()⟩ | .timeout => ⟨3, ()⟩)
    (by rintro ⟨i, x⟩; match i, x with | 0, _ => rfl | 1, () => rfl | 2, () => rfl | 3, () => rfl)
    (by intro e; cases e <;> rfl)

private def BodyT : Fin 3 → Type
  | 0 => Origin × Blob × Attestation × Blob × Blob | 1 => UInt64 × UInt64 × Event | 2 => Exit

def body : Codec Body :=
  iso (tagged 3 (by decide) BodyT
        fun | 0 => pair origin (pair blob (pair attestation (pair blob blob)))
            | 1 => pair u64 (pair u64 event) | 2 => exit)
    (fun | ⟨0, (o, m, a, p, q)⟩ => .report o m a p q | ⟨1, (i, p, e)⟩ => .call i p e
         | ⟨2, x⟩ => .exit x)
    (fun | .report o m a p q => ⟨0, (o, m, a, p, q)⟩ | .call i p e => ⟨1, (i, p, e)⟩
         | .exit x => ⟨2, x⟩)
    (by rintro ⟨i, x⟩
        match i, x with | 0, (_, _, _, _, _) => rfl | 1, (_, _, _) => rfl | 2, _ => rfl)
    (by intro b; cases b <;> rfl)

def record : Codec Record :=
  iso (pair blob (pair u64 body))
    (fun (b, s, x) => ⟨b, s, x⟩)
    (fun r => (r.boot, r.seq, r.body))
    (fun _ => rfl)
    (fun _ => rfl)

end Codec

/-- The bytes a boot's key signs. -/
def Record.enc (r : Record) : Bytes := Codec.record.enc r

def Record.dec (b : Bytes) : Option Record := Codec.record.decAll b

theorem Record.dec_enc (r : Record) : Record.dec r.enc = some r :=
  Codec.record.decAll_enc r

/-- Canonical: the only bytes that decode to a record are its encoding. -/
theorem Record.enc_dec {b : Bytes} {r : Record} (h : Record.dec b = some r) : r.enc = b :=
  Codec.record.enc_decAll h

/-- Two records sign the same bytes only if they are the same record. -/
theorem Record.enc_injective {r s : Record} (h : r.enc = s.enc) : r = s :=
  Codec.record.enc_injective h

end Cead

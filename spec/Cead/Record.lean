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
inductive Evidence where
  | unattested
  | snp (report : Blob)
deriving DecidableEq

inductive Verdict where
  | allow
  | deny
deriving DecidableEq

/-- How a command ended. -/
inductive Ended where
  | exited (code : UInt8)
  | signaled (signal : UInt8)
deriving DecidableEq

/-- One call's record, sharing its id with the call's other two. -/
inductive Event where
  | intent (command : Blob)
  | decision (verdict : Verdict)
  /-- `output` is the digest of the command's whole output, before truncation. -/
  | witness (ended : Ended) (output : Blob)
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
  | report (origin : Origin) (measurement : Blob) (evidence : Evidence)
  | call (id : UInt64) (event : Event)
  | exit (exit : Exit)
deriving DecidableEq

/-- `boot` is the boot's public key; `prev` the digest of the previous
record's encoding, empty for the report. -/
structure Record where
  boot : Blob
  seq : UInt64
  prev : Blob
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

private def EvidenceT : Fin 2 → Type
  | 0 => Unit | 1 => Blob

def evidence : Codec Evidence :=
  iso (tagged 2 (by decide) EvidenceT fun | 0 => unit | 1 => blob)
    (fun | ⟨0, _⟩ => .unattested | ⟨1, r⟩ => .snp r)
    (fun | .unattested => ⟨0, ()⟩ | .snp r => ⟨1, r⟩)
    (by rintro ⟨i, x⟩; match i, x with | 0, () => rfl | 1, _ => rfl)
    (by intro e; cases e <;> rfl)

def verdict : Codec Verdict :=
  iso (tag 2 (by decide))
    (fun | 0 => .allow | 1 => .deny)
    (fun | .allow => 0 | .deny => 1)
    (by intro i; match i with | 0 => rfl | 1 => rfl)
    (by intro v; cases v <;> rfl)

private def u8 : Codec UInt8 :=
  iso (tag 256 (by decide)) (fun i => i.val.toUInt8) (fun b => ⟨b.toNat, b.toNat_lt⟩)
    (by intro i; apply Fin.ext; simp [Nat.toUInt8])
    (by intro b; simp [Nat.toUInt8])

private def EndedT : Fin 2 → Type
  | 0 => UInt8 | 1 => UInt8

def ended : Codec Ended :=
  iso (tagged 2 (by decide) EndedT fun | 0 => u8 | 1 => u8)
    (fun | ⟨0, c⟩ => .exited c | ⟨1, s⟩ => .signaled s)
    (fun | .exited c => ⟨0, c⟩ | .signaled s => ⟨1, s⟩)
    (by rintro ⟨i, x⟩; match i, x with | 0, _ => rfl | 1, _ => rfl)
    (by intro e; cases e <;> rfl)

private def EventT : Fin 3 → Type
  | 0 => Blob | 1 => Verdict | 2 => Ended × Blob

def event : Codec Event :=
  iso (tagged 3 (by decide) EventT fun | 0 => blob | 1 => verdict | 2 => pair ended blob)
    (fun | ⟨0, c⟩ => .intent c | ⟨1, v⟩ => .decision v | ⟨2, (e, o)⟩ => .witness e o)
    (fun | .intent c => ⟨0, c⟩ | .decision v => ⟨1, v⟩ | .witness e o => ⟨2, (e, o)⟩)
    (by rintro ⟨i, x⟩; match i, x with | 0, _ => rfl | 1, _ => rfl | 2, (_, _) => rfl)
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
  | 0 => Origin × Blob × Evidence | 1 => UInt64 × Event | 2 => Exit

def body : Codec Body :=
  iso (tagged 3 (by decide) BodyT
        fun | 0 => pair origin (pair blob evidence) | 1 => pair u64 event | 2 => exit)
    (fun | ⟨0, (o, m, e)⟩ => .report o m e | ⟨1, (i, e)⟩ => .call i e | ⟨2, x⟩ => .exit x)
    (fun | .report o m e => ⟨0, (o, m, e)⟩ | .call i e => ⟨1, (i, e)⟩ | .exit x => ⟨2, x⟩)
    (by rintro ⟨i, x⟩; match i, x with | 0, (_, _, _) => rfl | 1, (_, _) => rfl | 2, _ => rfl)
    (by intro b; cases b <;> rfl)

def record : Codec Record :=
  iso (pair blob (pair u64 (pair blob body)))
    (fun (b, s, p, x) => ⟨b, s, p, x⟩)
    (fun r => (r.boot, r.seq, r.prev, r.body))
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

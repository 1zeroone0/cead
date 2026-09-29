/-!
A codec is a self-delimiting encoding: a value's bytes say where they end, so
encodings laid end to end parse back with no separator. Each combinator
proves its two laws once; anything built from them inherits both.
-/
namespace Cead

abbrev Bytes := List UInt8

structure Codec (α : Type) where
  enc : α → Bytes
  dec : Bytes → Option (α × Bytes)
  /-- Decoding an encoding gives the value back, and leaves what follows. -/
  dec_enc : ∀ a rest, dec (enc a ++ rest) = some (a, rest)
  /-- Whatever decodes was an encoding, so no two byte strings decode to one value. -/
  enc_dec : ∀ b a rest, dec b = some (a, rest) → enc a ++ rest = b

/-- Bytes whose length fits a u64: every Rust `Vec<u8>` on a 64-bit host. -/
structure Blob where
  data : Bytes
  fits : data.length < UInt64.size
deriving DecidableEq

/-- Exactly `n` bytes: a key or a digest. -/
structure Fixed (n : Nat) where
  data : Bytes
  len : data.length = n
deriving DecidableEq

namespace Codec

/-- Equal encodings mean equal values. -/
theorem enc_injective (c : Codec α) {a b : α} (h : c.enc a = c.enc b) : a = b := by
  have ha := c.dec_enc a []
  rw [h, c.dec_enc] at ha
  cases ha; rfl

/-- A whole message: one value, nothing after it. -/
def decAll (c : Codec α) (b : Bytes) : Option α :=
  match c.dec b with
  | some (a, []) => some a
  | _ => none

theorem decAll_enc (c : Codec α) (a : α) : c.decAll (c.enc a) = some a := by
  have h := c.dec_enc a []
  rw [List.append_nil] at h
  simp [decAll, h]

/-- Canonical: the only bytes that decode to a value are its encoding. -/
theorem enc_decAll (c : Codec α) {b : Bytes} {a : α} (h : c.decAll b = some a) : c.enc a = b := by
  unfold decAll at h
  split at h
  · rename_i hd; cases h
    simpa using c.enc_dec _ _ _ hd
  · cases h

def unit : Codec Unit where
  enc _ := []
  dec b := some ((), b)
  dec_enc _ _ := rfl
  enc_dec _ _ _ h := by cases h; rfl

/-- One tag byte, below `n`. -/
def tag (n : Nat) (hn : n ≤ 256) : Codec (Fin n) where
  enc i := [i.val.toUInt8]
  dec
    | t :: rest => if h : t.toNat < n then some (⟨t.toNat, h⟩, rest) else none
    | [] => none
  dec_enc i rest := by
    have : i.val < 256 := by omega
    simp [Nat.toUInt8, Nat.mod_eq_of_lt this]
  enc_dec b i rest h := by
    match b, h with
    | t :: r, h =>
      simp only at h
      split at h
      · cases h; simp [Nat.toUInt8]
      · cases h

private def be (n : UInt64) : List UInt8 :=
  [(n.toNat / 2^56 % 256).toUInt8, (n.toNat / 2^48 % 256).toUInt8,
   (n.toNat / 2^40 % 256).toUInt8, (n.toNat / 2^32 % 256).toUInt8,
   (n.toNat / 2^24 % 256).toUInt8, (n.toNat / 2^16 % 256).toUInt8,
   (n.toNat / 2^8 % 256).toUInt8, (n.toNat % 256).toUInt8]

private def unbe (a b c d e f g h : UInt8) : UInt64 :=
  (a.toNat * 2^56 + b.toNat * 2^48 + c.toNat * 2^40 + d.toNat * 2^32 +
   e.toNat * 2^24 + f.toNat * 2^16 + g.toNat * 2^8 + h.toNat).toUInt64

private theorem digits (x : Nat) (hx : x < 2^64) :
    x / 2^56 % 256 * 2^56 + x / 2^48 % 256 * 2^48 + x / 2^40 % 256 * 2^40 +
    x / 2^32 % 256 * 2^32 + x / 2^24 % 256 * 2^24 + x / 2^16 % 256 * 2^16 +
    x / 2^8 % 256 * 2^8 + x % 256 = x := by
  omega

private theorem unbe_be (n : UInt64) :
    unbe (n.toNat / 2^56 % 256).toUInt8 (n.toNat / 2^48 % 256).toUInt8
         (n.toNat / 2^40 % 256).toUInt8 (n.toNat / 2^32 % 256).toUInt8
         (n.toNat / 2^24 % 256).toUInt8 (n.toNat / 2^16 % 256).toUInt8
         (n.toNat / 2^8 % 256).toUInt8 (n.toNat % 256).toUInt8 = n := by
  apply UInt64.toNat_inj.mp
  simp only [unbe, Nat.toUInt8, UInt8.toNat_ofNat', Nat.mod_mod, Nat.toUInt64, UInt64.toNat_ofNat']
  rw [digits _ n.toNat_lt_size, Nat.mod_eq_of_lt n.toNat_lt_size]

private theorem be_unbe (a b c d e f g h : UInt8) :
    be (unbe a b c d e f g h) = [a, b, c, d, e, f, g, h] := by
  have := a.toNat_lt; have := b.toNat_lt; have := c.toNat_lt; have := d.toNat_lt
  have := e.toNat_lt; have := f.toNat_lt; have := g.toNat_lt; have := h.toNat_lt
  simp only [be, unbe, List.cons.injEq, and_true, Nat.toUInt64, UInt64.toNat_ofNat', Nat.reducePow]
  refine ⟨?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_⟩ <;> apply UInt8.toNat_inj.mp <;>
    simp only [Nat.toUInt8, UInt8.toNat_ofNat', Nat.reducePow] <;> omega

/-- Eight bytes, big-endian. -/
def u64 : Codec UInt64 where
  enc := be
  dec
    | a :: b :: c :: d :: e :: f :: g :: h :: rest => some (unbe a b c d e f g h, rest)
    | _ => none
  dec_enc n rest := by simp only [be, List.cons_append, List.nil_append, unbe_be]
  enc_dec bs n rest hd := by
    match bs, hd with
    | a :: b :: c :: d :: e :: f :: g :: h :: r, hd =>
      cases hd; simp [be_unbe]

/-- A u64 length, then the bytes. -/
def blob : Codec Blob where
  enc b := u64.enc (UInt64.ofNat b.data.length) ++ b.data
  dec bs := do
    let (n, r) ← u64.dec bs
    if h : n.toNat ≤ r.length then
      some (⟨r.take n.toNat, by have := n.toNat_lt_size; simp; omega⟩, r.drop n.toNat)
    else none
  dec_enc b rest := by
    have hn : (UInt64.ofNat b.data.length).toNat = b.data.length :=
      UInt64.toNat_ofNat_of_lt b.fits
    simp [List.append_assoc, u64.dec_enc, hn]
  enc_dec bs b rest hd := by
    simp only [Option.bind_eq_bind] at hd
    match hn : u64.dec bs, hd with
    | some (n, r), hd =>
      simp only [Option.bind_some] at hd
      split at hd
      · cases hd
        have := u64.enc_dec _ _ _ hn
        simp [List.length_take, Nat.min_eq_left ‹n.toNat ≤ r.length›, List.append_assoc, this]
      · cases hd

/-- The `n` bytes as they are: their length says where they end. -/
def fixed (n : Nat) : Codec (Fixed n) where
  enc b := b.data
  dec bs := if h : n ≤ bs.length then some (⟨bs.take n, by simp; omega⟩, bs.drop n) else none
  dec_enc b rest := by
    have := b.len
    simp [this, List.take_left', List.drop_left']
  enc_dec bs b rest hd := by
    split at hd
    · cases hd; simp
    · cases hd

def pair (ca : Codec α) (cb : Codec β) : Codec (α × β) where
  enc p := ca.enc p.1 ++ cb.enc p.2
  dec bs := do
    let (a, r) ← ca.dec bs
    let (b, r) ← cb.dec r
    pure ((a, b), r)
  dec_enc p rest := by simp [List.append_assoc, ca.dec_enc, cb.dec_enc]
  enc_dec bs p rest hd := by
    match ha : ca.dec bs, hd with
    | some (a, r), hd =>
      simp only [Option.bind_eq_bind, Option.bind_some] at hd
      match hb : cb.dec r, hd with
      | some (b, r'), hd =>
        simp only [Option.bind_some, Option.pure_def, Option.some.injEq] at hd
        cases hd
        simp [List.append_assoc, cb.enc_dec _ _ _ hb, ca.enc_dec _ _ _ ha]

/-- A tag byte picks the variant; the variant's codec follows. -/
def tagged (n : Nat) (hn : n ≤ 256) (T : Fin n → Type) (cs : (i : Fin n) → Codec (T i)) :
    Codec ((i : Fin n) × T i) where
  enc x := (tag n hn).enc x.1 ++ (cs x.1).enc x.2
  dec bs := do
    let (i, r) ← (tag n hn).dec bs
    let (x, r) ← (cs i).dec r
    pure (⟨i, x⟩, r)
  dec_enc x rest := by
    obtain ⟨i, x⟩ := x
    simp [List.append_assoc, (tag n hn).dec_enc, (cs i).dec_enc]
  enc_dec bs x rest hd := by
    match hi : (tag n hn).dec bs, hd with
    | some (i, r), hd =>
      simp only [Option.bind_eq_bind, Option.bind_some] at hd
      match hx : (cs i).dec r, hd with
      | some (y, r'), hd =>
        simp only [Option.bind_some, Option.pure_def, Option.some.injEq] at hd
        cases hd
        simp [List.append_assoc, (cs i).enc_dec _ _ _ hx, (tag n hn).enc_dec _ _ _ hi]

/-- A codec for `β` through a bijection with `α`. -/
def iso (c : Codec α) (f : α → β) (g : β → α) (gf : ∀ a, g (f a) = a) (fg : ∀ b, f (g b) = b) :
    Codec β where
  enc b := c.enc (g b)
  dec bs := (c.dec bs).map fun (a, r) => (f a, r)
  dec_enc b rest := by simp [c.dec_enc, fg]
  enc_dec bs b rest hd := by
    match ha : c.dec bs, hd with
    | some (a, r), hd =>
      simp only [Option.map_some, Option.some.injEq, Prod.mk.injEq] at hd
      obtain ⟨rfl, rfl⟩ := hd
      rw [gf]; exact c.enc_dec _ _ _ ha

end Codec
end Cead

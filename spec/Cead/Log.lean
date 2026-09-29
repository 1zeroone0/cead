import Cead.Record

/-!
The log's acceptance, `spec/cead.tla`'s `Arrive` over real records, proved
for every log size (TLC checks it up to its bounds).

`accept` sees only records whose signature already verified: `boot` is the
boot's public key, so the check needs no log. A report's attestation is
verified by then too (attested) or accepted as `unattested` (trusted-host
mode). Everything that depends on the log is here.
-/
namespace Cead

abbrev Log := List Record

def Body.isReport : Body → Bool
  | .report .. => true
  | _ => false

def Body.isExit : Body → Bool
  | .exit _ => true
  | _ => false

/-- The boot a report recovers, if it is a recovery. -/
def Body.recovers : Body → Option Blob
  | .report (.recovery b _) .. => some b
  | _ => none

section
variable (log : Log)

def Logged (b : Blob) (s : UInt64) : Prop := ∃ r ∈ log, r.boot = b ∧ r.seq = s

def Vouched (b : Blob) : Prop := Logged log b 1

def Exited (b : Blob) : Prop := ∃ r ∈ log, r.boot = b ∧ r.body.isExit

def Recovered (b : Blob) : Prop := ∃ r ∈ log, r.body.recovers = some b

instance : Decidable (Logged log b s) := by unfold Logged; infer_instance
instance : Decidable (Vouched log b) := by unfold Vouched; infer_instance
instance : Decidable (Exited log b) := by unfold Exited; infer_instance
instance : Decidable (Recovered log b) := by unfold Recovered; infer_instance
end

/-- What a report's origin demands: a fork or recovery names a record the
log holds; a recovery only while its boot has no exit record and no other
recovery. -/
def Origin.Admits (log : Log) : Origin → Prop
  | .run => True
  | .fork b l => Logged log b l
  | .recovery b l => Logged log b l ∧ ¬ Exited log b ∧ ¬ Recovered log b

instance : Decidable (Origin.Admits log o) := by cases o <;> unfold Origin.Admits <;> infer_instance

/-- What a record's kind demands of the log. A report opens its boot's
sequence. Any other record needs its boot's report, and no recovery of its
boot: a recovery fences the boot it recovers. -/
def Admits (log : Log) (r : Record) : Prop :=
  match r.body with
  | .report o .. => r.seq = 1 ∧ o.Admits log
  | _ => 1 < r.seq ∧ Vouched log r.boot ∧ ¬ Recovered log r.boot

instance : Decidable (Admits log r) := by unfold Admits; split <;> infer_instance

/-- The log keeps a record, or refuses it. It keeps the first record for each
place in a boot's sequence, so a duplicate or resend is refused and changes
nothing. -/
def accept (log : Log) (r : Record) : Option Log :=
  if ¬ Logged log r.boot r.seq ∧ Admits log r then some (log ++ [r]) else none

/-- The snapshot a fork or recovery booted from. -/
def Body.source : Body → Option (Blob × UInt64)
  | .report (.fork b l) .. | .report (.recovery b l) .. => some (b, l)
  | _ => none

/-- What every log `accept` builds from empty satisfies. -/
structure Valid (log : Log) : Prop where
  /-- A report opens each boot's sequence; every other record comes after it. -/
  opens : ∀ r ∈ log, if r.body.isReport then r.seq = 1 else 1 < r.seq
  /-- One record per place in a boot's sequence. -/
  firstWins : log.Pairwise fun r s => ¬ (r.boot = s.boot ∧ r.seq = s.seq)
  /-- Every record's boot has its report in the log. -/
  vouched : ∀ r ∈ log, Vouched log r.boot
  /-- A fork or recovery names a record the log holds. -/
  rooted : ∀ r ∈ log, ∀ b l, r.body.source = some (b, l) → Logged log b l
  /-- Nothing of a boot follows its recovery. -/
  fenced : log.Pairwise fun r s => r.body.recovers ≠ some s.boot
  /-- At most one recovery per boot. -/
  recoveredOnce : log.Pairwise fun r s => ∀ b, r.body.recovers = some b → s.body.recovers ≠ some b
  /-- A job has one outcome: no boot both exits and is recovered. -/
  oneOutcome : ∀ b, Exited log b → ¬ Recovered log b

theorem valid_nil : Valid [] := by
  constructor <;> simp [Exited]

section Proofs
variable {log : Log} {r : Record} {b : Blob} {s : UInt64}

private theorem logged_append (h : Logged log b s) : Logged (log ++ [r]) b s := by
  obtain ⟨x, hx, h⟩ := h; exact ⟨x, by simp [hx], h⟩

private theorem recovers_source {x : Record} (h : x.body.recovers = some b) :
    ∃ l, x.body.source = some (b, l) := by
  match hb : x.body, h with
  | .report (.recovery b' l) .., h =>
    simp only [Body.recovers, Option.some.injEq] at h; subst h; exact ⟨l, rfl⟩

/-- A recovered boot's report is in the log: the recovery names one of its records. -/
private theorem recovered_vouched (hv : Valid log) (h : Recovered log b) : Logged log b 1 := by
  obtain ⟨x, hx, hr⟩ := h
  obtain ⟨l, hs⟩ := recovers_source hr
  obtain ⟨y, hy, rfl, -⟩ := hv.rooted x hx b l hs
  exact hv.vouched y hy

/-- `accept` keeps the record and refuses nothing it should keep: the log only grows. -/
theorem accept_grows {log' : Log} (h : accept log r = some log') : log' = log ++ [r] := by
  unfold accept at h; split at h <;> simp_all

theorem accept_valid {log' : Log} (hv : Valid log) (h : accept log r = some log') :
    Valid log' := by
  unfold accept at h
  split at h
  case isFalse => cases h
  rename_i hc
  obtain ⟨hnew, hadm⟩ := hc
  cases h
  -- No recovery of r's boot is in the log.
  have hfresh : ¬ Recovered log r.boot := by
    unfold Admits at hadm
    split at hadm
    · intro hr
      exact hnew (hadm.1 ▸ recovered_vouched hv hr)
    · exact hadm.2.2
  constructor
  · intro x hx
    rcases List.mem_append.mp hx with hx | hx
    · exact hv.opens x hx
    · simp only [List.mem_singleton] at hx; subst hx
      unfold Admits at hadm
      split at hadm
      · rename_i hb; simp [Body.isReport, hb, hadm.1]
      · rename_i hb
        have : x.body.isReport = false := by
          unfold Body.isReport; split
          · rename_i h; exact absurd h (hb _ _ _ _ _)
          · rfl
        simp [this, hadm.1]
  · rw [List.pairwise_append]
    refine ⟨hv.firstWins, by simp, ?_⟩
    intro x hx y hy ⟨hb, hs⟩
    simp only [List.mem_singleton] at hy; subst hy
    exact hnew ⟨x, hx, hb, hs⟩
  · intro x hx
    rcases List.mem_append.mp hx with hx | hx
    · exact logged_append (hv.vouched x hx)
    · simp only [List.mem_singleton] at hx; subst hx
      unfold Admits at hadm
      split at hadm
      · exact ⟨x, by simp, rfl, hadm.1⟩
      · exact logged_append hadm.2.1
  · intro x hx b l hs
    rcases List.mem_append.mp hx with hx | hx
    · exact logged_append (hv.rooted x hx b l hs)
    · simp only [List.mem_singleton] at hx; subst hx
      unfold Admits at hadm
      split at hadm
      · rename_i o _ _ _ _ hb
        rw [hb] at hs
        cases o <;> simp only [Body.source, Option.some.injEq, Prod.mk.injEq, reduceCtorEq] at hs
        all_goals
          obtain ⟨rfl, rfl⟩ := hs
          simp only [Origin.Admits] at hadm
        · exact logged_append hadm.2
        · exact logged_append hadm.2.1
      · rename_i hb
        match hx : x.body, hs with
        | .report (.fork _ _) .., _ | .report (.recovery _ _) .., _ =>
          exact absurd hx (hb _ _ _ _ _)
  · rw [List.pairwise_append]
    refine ⟨hv.fenced, by simp, ?_⟩
    intro x hx y hy h
    simp only [List.mem_singleton] at hy; subst hy
    exact hfresh ⟨x, hx, h⟩
  · rw [List.pairwise_append]
    refine ⟨hv.recoveredOnce, by simp, ?_⟩
    intro x hx y hy b hxb hyb
    simp only [List.mem_singleton] at hy; subst hy
    unfold Admits at hadm
    split at hadm
    · rename_i o _ _ _ _ hb
      cases o <;> simp [Body.recovers, hb] at hyb
      subst hyb
      exact hadm.2.2.2 ⟨x, hx, hxb⟩
    · rename_i hb
      match hy : y.body, hyb with
      | .report (.recovery _ _) .., _ => exact absurd hy (hb _ _ _ _ _)
  · intro b hex hrec
    obtain ⟨x, hx, hxb, hxe⟩ := hex
    obtain ⟨y, hy, hyr⟩ := hrec
    rcases List.mem_append.mp hx with hxo | hxr <;> rcases List.mem_append.mp hy with hyo | hyr'
    · exact hv.oneOutcome b ⟨x, hxo, hxb, hxe⟩ ⟨y, hyo, hyr⟩
    · -- r recovers b, which already has an exit record
      simp only [List.mem_singleton] at hyr'; subst hyr'
      unfold Admits at hadm
      split at hadm
      · rename_i o _ _ _ _ hb
        cases o <;> simp [Body.recovers, hb] at hyr
        subst hyr
        exact hadm.2.2.1 ⟨x, hxo, hxb, hxe⟩
      · rename_i hb
        match hyb : y.body, hyr with
        | .report (.recovery _ _) .., _ => exact absurd hyb (hb _ _ _ _ _)
    · -- r is b's exit record, and b is already recovered
      simp only [List.mem_singleton] at hxr; subst hxr
      exact hfresh (hxb ▸ ⟨y, hyo, hyr⟩)
    · simp only [List.mem_singleton] at hxr hyr'
      rw [hxr] at hxe; rw [hyr'] at hyr
      match hb : r.body, hxe, hyr with
      | .report (.recovery _ _) .., hxe, _ => simp [Body.isExit] at hxe

/-- The logs `accept` builds from empty, one record at a time. -/
inductive Accepted : Log → Prop
  | nil : Accepted []
  | cons {log log' r} : Accepted log → accept log r = some log' → Accepted log'

/-- Every log built by `accept` from empty is valid. -/
theorem accepted_valid (h : Accepted log) : Valid log := by
  induction h with
  | nil => exact valid_nil
  | cons _ ha ih => exact accept_valid ih ha

end Proofs
end Cead

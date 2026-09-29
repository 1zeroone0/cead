/-!
Meters, from KeyKOS: what a process tree may spend. `spec/cead.tla`'s
`Chargeable`, `Issue`'s charge and property 15 (`WithinMeter`), proved for
every tree and every sequence of spawns and charges.

A process's number is its index; a child is appended, so its parent's number
is smaller. Every call is charged to each meter from its process up to the
root.
-/
namespace Cead.Meter

structure Proc where
  parent : Option Nat
  /-- The meter it was given. -/
  cap : Nat
  /-- What remains of it. -/
  meter : Nat
  /-- The calls it made. -/
  calls : Nat

abbrev Tree := List Proc

def root (cap : Nat) : Tree := [⟨none, cap, cap, 0⟩]

/-- `q`, its parent, and so on up to the root. -/
def chain (t : Tree) (q : Nat) : List Nat :=
  q :: match t[q]?.bind (·.parent) with
    | some pa => if pa < q then chain t pa else []
    | none => []
termination_by q
decreasing_by omega

theorem chain_le (t : Tree) (q : Nat) : ∀ a ∈ chain t q, a ≤ q := by
  induction q using Nat.strongRecOn with
  | _ q ih =>
    intro a ha
    rw [chain] at ha
    simp only [List.mem_cons] at ha
    rcases ha with rfl | ha
    · exact Nat.le_refl _
    · split at ha
      · split at ha
        · rename_i pa _ hlt; exact Nat.le_of_lt (Nat.lt_of_le_of_lt (ih pa hlt a ha) hlt)
        · simp at ha
      · simp at ha

/-- `chain` reads only parents at indices up to `q`: trees agreeing there agree on it. -/
theorem chain_congr (t t' : Tree) (q : Nat)
    (h : ∀ i ≤ q, t'[i]?.bind (·.parent) = t[i]?.bind (·.parent)) : chain t' q = chain t q := by
  induction q using Nat.strongRecOn with
  | _ q ih =>
    rw [chain, chain, h q (Nat.le_refl _)]
    split
    · rename_i pa _
      split
      · rename_i hlt
        rw [ih pa hlt (fun i hi => h i (by omega))]
      · rfl
    · rfl

/-- Every meter from `q` up to the root has a unit left. -/
def Chargeable (t : Tree) (q : Nat) : Prop :=
  q < t.length ∧ ∀ a ∈ chain t q, 0 < (t[a]?.map (·.meter)).getD 0

instance : Decidable (Chargeable t q) := by unfold Chargeable; infer_instance

/-- Process `a` after a call by `q`: one unit off its meter if the call is
charged to it, and one more call if it made it. -/
def bump (t : Tree) (q a : Nat) (x : Proc) : Proc :=
  { x with meter := if a ∈ chain t q then x.meter - 1 else x.meter,
           calls := if a = q then x.calls + 1 else x.calls }

/-- A call by `q`: one unit from each meter up to the root, or refused. -/
def charge (t : Tree) (q : Nat) : Option Tree :=
  if Chargeable t q then some (t.mapIdx (bump t q)) else none

/-- `agent`: a child of `pa` with meter `cap`. -/
def spawn (t : Tree) (pa cap : Nat) : Option Tree :=
  if pa < t.length then some (t ++ [⟨some pa, cap, cap, 0⟩]) else none

/-- The calls made anywhere in `p`'s subtree: by every process whose chain
passes through `p`. -/
def spent (t : Tree) (p : Nat) : Nat :=
  (((List.range t.length).filter fun q => p ∈ chain t q).map
    fun q => (t[q]?.map (·.calls)).getD 0).sum

/-- Every process's remaining meter and its subtree's calls add up to what it
was given. -/
def Balanced (t : Tree) : Prop :=
  ∀ p x, t[p]? = some x → x.meter + spent t p = x.cap

/-- No subtree spends more than its root's meter. -/
theorem within_meter (h : Balanced t) (hp : t[p]? = some x) : spent t p ≤ x.cap := by
  have := h p x hp; omega

theorem balanced_root (cap : Nat) : Balanced (root cap) := by
  intro p x hp
  match p, hp with
  | 0, hp =>
    simp only [root, List.getElem?_cons_zero, Option.some.injEq] at hp; subst hp
    unfold spent
    simp only [root, List.length_singleton, List.range_one, List.filter_cons, List.filter_nil]
    split <;> simp

private theorem sum_bump (l : List Nat) (hl : l.Nodup) (f : Nat → Nat) (q : Nat) :
    (l.map fun i => f i + if i = q then 1 else 0).sum = (l.map f).sum + if q ∈ l then 1 else 0 := by
  induction l with
  | nil => simp
  | cons a l ih =>
    simp only [List.nodup_cons] at hl
    simp only [List.map_cons, List.sum_cons, ih hl.2, List.mem_cons]
    by_cases ha : a = q
    · subst ha; simp [hl.1]; omega
    · simp [ha, Ne.symm ha]; omega

theorem charge_balanced (h : Balanced t) (hc : charge t q = some t') : Balanced t' := by
  unfold charge at hc
  split at hc
  case isFalse => cases hc
  rename_i hq
  cases hc
  have hget : ∀ i, (t.mapIdx (bump t q))[i]? = t[i]?.map (bump t q i) := by
    intro i; simp [List.getElem?_mapIdx]
  have hchain : ∀ i, chain (t.mapIdx (bump t q)) i = chain t i := by
    intro i; apply chain_congr; intro j _; rw [hget j]; cases t[j]? <;> rfl
  have hspent : ∀ p, spent (t.mapIdx (bump t q)) p = spent t p + if p ∈ chain t q then 1 else 0 := by
    intro p
    unfold spent
    simp only [List.length_mapIdx, hchain, hget]
    have : ∀ i, ((t[i]?.map (bump t q i)).map (·.calls)).getD 0 =
        (t[i]?.map (·.calls)).getD 0 + if i = q then 1 else 0 := by
      intro i
      cases hi : t[i]? with
      | none =>
        simp only [Option.map_none, Option.getD_none]
        split
        · subst_vars; have := hq.1; simp at hi; omega
        · rfl
      | some z => simp only [Option.map_some, Option.getD_some, bump]; split <;> simp
    simp only [this]
    rw [sum_bump _ ((List.nodup_range).filter _)]
    congr 1
    simp [hq.1]
  intro p x hp
  rw [hget p] at hp
  cases hy : t[p]? with
  | none => rw [hy] at hp; cases hp
  | some y =>
    rw [hy] at hp
    simp only [Option.map_some, Option.some.injEq] at hp
    subst hp
    have hb := h p y hy
    rw [hspent p]
    by_cases hpq : p ∈ chain t q
    · have hm := hq.2 p hpq
      simp [hy] at hm
      simp [bump, hpq]; omega
    · simp [bump, hpq]; omega

theorem spawn_balanced (h : Balanced t) (hs : spawn t pa cap = some t') : Balanced t' := by
  unfold spawn at hs
  split at hs
  case isFalse => cases hs
  rename_i hpa
  cases hs
  let c : Proc := ⟨some pa, cap, cap, 0⟩
  have hold : ∀ i < t.length, (t ++ [c])[i]? = t[i]? := fun i hi => List.getElem?_append_left hi
  have hchain : ∀ i < t.length, chain (t ++ [c]) i = chain t i := by
    intro i hi; apply chain_congr; intro j hj; rw [hold j (by omega)]
  -- A new process adds no calls, so no subtree's spending changes.
  have hspent : ∀ p, spent (t ++ [c]) p = spent t p := by
    intro p
    unfold spent
    rw [List.length_append, List.length_singleton, List.range_succ, List.filter_append,
      List.map_append, List.sum_append]
    have hnew : ((([t.length].filter fun q => decide (p ∈ chain (t ++ [c]) q)).map
        fun q => ((t ++ [c])[q]?.map (·.calls)).getD 0)).sum = 0 := by
      simp only [List.filter_cons, List.filter_nil]
      split <;> simp [c]
    rw [hnew, Nat.add_zero]
    congr 1
    rw [List.filter_congr (fun i hi => by rw [hchain i (List.mem_range.mp hi)])]
    apply List.map_congr_left
    intro i hi
    rw [hold i (List.mem_range.mp (List.mem_filter.mp hi).1)]
  intro p x hp
  rw [hspent p]
  by_cases hlt : p < t.length
  · rw [hold p hlt] at hp; exact h p x hp
  · have hpn : p = t.length := by
      have := (List.getElem?_eq_some_iff.mp hp).1; simp at this; omega
    subst hpn
    rw [List.getElem?_append_right (Nat.le_refl _)] at hp
    simp only [Nat.sub_self, List.getElem?_cons_zero, Option.some.injEq] at hp
    subst hp
    -- Nothing in `t` has the new process in its chain.
    have : spent t t.length = 0 := by
      unfold spent
      rw [List.filter_eq_nil_iff.mpr]
      · rfl
      · intro i hi hm
        have := chain_le t i _ (of_decide_eq_true hm)
        have := List.mem_range.mp hi
        omega
    simp [this]

/-- The trees a job builds from its root, one spawn or charge at a time. -/
inductive Reachable : Tree → Prop
  | root (cap : Nat) : Reachable (root cap)
  | spawn {t t' pa cap} : Reachable t → spawn t pa cap = some t' → Reachable t'
  | charge {t t' q} : Reachable t → charge t q = some t' → Reachable t'

theorem reachable_balanced (hr : Reachable t) : Balanced t := by
  induction hr with
  | root cap => exact balanced_root cap
  | spawn _ hs ih => exact spawn_balanced ih hs
  | charge _ hc ih => exact charge_balanced ih hc

/-- In every tree a job can build, no subtree spends more than its root's
meter: property 15, `WithinMeter`, for every tree size. -/
theorem reachable_within_meter (hr : Reachable t) (hp : t[p]? = some x) : spent t p ≤ x.cap :=
  within_meter (reachable_balanced hr) hp

end Cead.Meter

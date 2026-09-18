import Base
import ./LAWS.bend as Laws
import ./src/compute.bend as Compute

# Nat.add(x, 0n) == x, by induction on x (identical to the `add_zero`
# example in `bend guide`; Base does not export this fact itself).
def Nat.add_zero(x: Nat) -> {Nat.add(x, 0n) == x : Nat}:
  match x:
    case 0n:
      {==}
    case 1n+p:
      %Nat.add_zero(p) : {1n+Nat.add(p, 0n) == 1n+_ : Nat}
      {==}

# Nat.mul(2n, b) == Nat.add(b, b): 2n is a concrete literal, so
# Nat.mul(2n, b) unfolds by computation alone (no induction on b needed)
# to Nat.add(b, Nat.add(b, 0n)); Nat.add_zero finishes it.
def Nat.mul2(b: Nat) -> {Nat.mul(2n, b) == Nat.add(b, b) : Nat}:
  %Equal.sym(Nat, Nat.add(b, 0n), b, Nat.add_zero(b))
    : {Nat.add(b, _) == Nat.add(b, b) : Nat}
  {==}

def Laws.pow2_gpu_agrees(n):
  {==}

def Laws.in_range_matches_max_n(n):
  {==}

# Compute.pow2's fork-join doubling always equals the sequential spec
# 2^n, by induction on n. The parallel call `a b = pow2(p) pow2(p)` is
# just two lets to the proof engine (Bend's guarantee that a parallel
# call is semantically identical to a sequential one), so this is the
# same shape of proof as `add_zero` in `bend guide`.
def Laws.pow2_spec(n):
  match n:
    case 0n:
      {==}
    case 1n+ +p:
      %Equal.sym(Nat, Nat.mul(2n, Nat.pow(2n, p)), Nat.add(Nat.pow(2n, p), Nat.pow(2n, p)),
        Nat.mul2(Nat.pow(2n, p)))
        : {Nat.add(Compute.pow2(p), Compute.pow2(p)) == _ : Nat}
      %Equal.sym(Nat, Compute.pow2(p), Nat.pow(2n, p), Laws.pow2_spec(p))
        : {Nat.add(_, Compute.pow2(p)) == Nat.add(Nat.pow(2n, p), Nat.pow(2n, p)) : Nat}
      %Equal.sym(Nat, Compute.pow2(p), Nat.pow(2n, p), Laws.pow2_spec(p))
        : {Nat.add(Nat.pow(2n, p), _) == Nat.add(Nat.pow(2n, p), Nat.pow(2n, p)) : Nat}
      {==}


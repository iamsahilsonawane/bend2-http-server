import Base

# Compute
# =======
#
# The one CPU/GPU-heavy workload the server exposes over HTTP. It is a
# fork-join binary tree, exactly the shape `bend guide` recommends for
# parallel code: every branch is independent, and both branches do the
# same amount of work, so the scheduler splits it evenly across cores
# (plain call) or across the GPU (`!` call) with no change to the code.
#
# `Compute.pow2(n)` returns `2^n`, computed by doubling a leaf of `1n`
# `n` times. LAWS.bend states, and PROOF.bend proves, that this parallel
# definition always equals the sequential spec `Nat.pow(2n, n)` -- so
# running it on more cores, or on the GPU, can never change the answer.

# A request above this depth is rejected with 400 before any work starts:
# 2^28 leaves is already ~268M additions, plenty to soak every core (or
# the GPU) for a visible amount of time without risking an unbounded
# response time.
def max_n() -> Nat:
  28n

def pow2(+n: Nat) -> Nat:
  match n:
    case 0n:
      1n
    case 1n+p:
      a b = pow2(p) pow2(p)
      Nat.add(a, b)

def in_range(n: Nat) -> Bool:
  Nat.is_le(n, max_n())

import Base
import ./src/compute.bend as Compute

# LAWS
# ====
#
# Every fact below is an open claim; PROOF.bend fills each one in with a
# def of the same name. `bend PROOF.bend` is the gate: it fails while any
# law is open or false, and prints "All terms check." once every law
# holds. These are the facts that let us say the parallel/GPU workload
# behind /compute/<n> and /gpu/<n> has no bugs, not just that it seemed
# to work in a curl test.

# The heavy workload the server exposes over HTTP is a fork-join
# doubling tree (compute.bend). This is the fact that actually matters
# for "parallel code has no bugs": no matter how the scheduler splits
# pow2's recursion across cores, the *value* it returns is always 2^n,
# the same as the obviously-correct sequential spec `Nat.pow(2n, n)`.
# Holds for every n; the routes separately cap n at max_n() to keep
# response times reasonable, not because correctness needs it.
law pow2_spec:
  for n: Nat
  {Compute.pow2(n) == Nat.pow(2n, n) : Nat}

# `!` only changes *where* a parallel call runs (a core vs the GPU),
# never *what* it computes. This is the law that lets /compute/<n> and
# /gpu/<n> promise callers the same answer.
law pow2_gpu_agrees:
  for n: Nat
  {Compute.pow2(n) == Compute.pow2!(n) : Nat}

# The bound the routes enforce before running any work (Compute.in_range)
# is exactly the bound pow2_spec assumes: nobody can ask for a request
# large enough to fall outside the proven-correct range. Stated as an
# unconditional identity so a future edit to either side that drifts out
# of sync breaks this law immediately, instead of silently.
law in_range_matches_max_n:
  for n: Nat
  {Compute.in_range(n) == Nat.is_le(n, Compute.max_n()) : Bool}


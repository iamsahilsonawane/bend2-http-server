import Base

# Runtime
# =======
#
# One tiny escape hatch outside the pure/proven core: asks the C or JS
# host, at request time, how many worker threads this process actually
# started with and whether the GPU lane is active, so /info can answer
# "how many cores, is the GPU really on" instead of asking the reader to
# trust the README. Both numbers come straight from the flags the binary
# was launched with (`--threads`, `--gpu`); nothing here is computed or
# proven, which is exactly why it stays out of Http/Compute/Route and
# out of LAWS.bend.
def info() -> IO(U32 & U32):
  import "./effs/runtime_info.c"
  import "./effs/runtime_info.js"

# How much CPU time (user + system, summed across every worker thread)
# this whole process has consumed so far, in milliseconds. Bracketing a
# computation with two calls to this and dividing the delta by the
# wall-clock delta (see IO.now) is the standard way to measure how many
# cores, on average, were actually kept busy doing that work -- unlike
# `info`'s thread count, which is only the size of the pool, not how much
# of it any one request used. There is no equivalent for the GPU: a
# kernel launch's actual core occupancy is a fact about the GPU driver,
# not something this process can observe about itself.
def cpu_ms() -> IO(Nat):
  import "./effs/cpu_time.c"
  import "./effs/cpu_time.js"

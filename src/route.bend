import Base
import ./http.bend as Http
import ./compute.bend as Compute

# Route
# =====
#
# The pure request -> response dispatcher. Kept separate from both Http
# (protocol mechanics) and the socket-facing Server, so LAWS.bend can
# state routing facts -- e.g. "/compute/<n>" and "/gpu/<n>" always agree
# -- as ordinary equalities over strings, with no IO in sight.

def home_body() -> String:
  String.concat([
    "bend http_server\n",
    "\n",
    "routes:\n",
    "  GET /                healthy check-in, this page\n",
    "  GET /health           \"OK\"\n",
    "  GET /info             thread count and GPU status of this process\n",
    "  GET /compute/<n>      2^n, run on every CPU core (n <= 28)\n",
    "  GET /gpu/<n>          2^n, run on the GPU when present (n <= 28)\n"])

def home() -> String:
  Http.text_response(200n, home_body())

def health() -> String:
  Http.text_response(200n, "OK\n")

# /info is answered with real numbers read from the running process (see
# runtime.bend): how many worker threads this binary actually started
# with, and whether the GPU lane is on. `wants_info` only inspects the
# request; the effect that fetches those numbers happens in server.bend,
# since this file has no IO in it.
def wants_info(method: String, path: String) -> Bool:
  Bool.and(String.eq(method, "GET"), String.eq(path, "/info"))

def info_body(+threads: U32, gpu_on: Bool) -> String:
  String.concat([
    "threads: ", U32.show(threads), "\n",
    "gpu: ", Bool.show(gpu_on), "\n"])

def info_page(threads: U32, gpu_on: Bool) -> String:
  Http.text_response(200n, info_body(threads, gpu_on))

# Parses the numeric path segment left after the route prefix and
# checks it is within the bound proven safe in LAWS.bend.
def parse_n.checked(+n: Nat, ok: Bool) -> Maybe<&2, Nat>:
  match ok:
    case True{}:
      Some{n}
    case False{}:
      None{}

def parse_n.got(digits: Maybe<&2, Nat>) -> Maybe<&2, Nat>:
  match digits:
    case None{}:
      None{}
    case Some{+n}:
      parse_n.checked(n, Compute.in_range(n))

def parse_n(rest: String) -> Maybe<&2, Nat>:
  parse_n.got(Nat.read(rest))

def bad_n_response() -> String:
  Http.bad_request(String.concat([
    "n must be a whole number from 0 to ", Nat.show(Compute.max_n())]))

# The actual computation (Compute.pow2 or pow2!) and its timing happen in
# server.bend, since forcing a value and reading the clock are both IO.
# This only formats the already-computed result plus the measurement:
# cpu_ms is the process's total CPU time (every worker thread summed)
# spent between the two clock reads, so cpu_ms / wall_ms is a real,
# measured "how many cores were kept busy for this one request" -- not
# the pool's size (see /info), which is only an upper bound.
def cores_used.calc(cpu_ms: Nat, wall_ms: Nat) -> String:
  +tenths = Nat.div(Nat.mul(cpu_ms, 10n), wall_ms)
  whole = Nat.div(tenths, 10n)
  frac = Nat.mod(tenths, 10n)
  String.concat([Nat.show(whole), ".", Nat.show(frac)])

def cores_used.if(cpu_ms: Nat, wall_ms: Nat, too_fast: Bool) -> String:
  match too_fast:
    case True{}:
      "n/a (too fast to measure)"
    case False{}:
      cores_used.calc(cpu_ms, wall_ms)

def cores_used(+cpu_ms: Nat, +wall_ms: Nat) -> String:
  cores_used.if(cpu_ms, wall_ms, Nat.is_eq(wall_ms, 0n))

def timed_response(+n: Nat, +result: Nat, +wall_ms: Nat, +cpu_ms: Nat) -> String:
  Http.text_response(200n, String.concat([
    "n: ", Nat.show(n), "\n",
    "result: ", Nat.show(result), "\n",
    "wall_ms: ", Nat.show(wall_ms), "\n",
    "cpu_ms (every worker thread, summed): ", Nat.show(cpu_ms), "\n",
    "cores_used (cpu_ms / wall_ms): ", cores_used(cpu_ms, wall_ms), "\n"]))

# Every branch below matches a plain field of the parsed Request, per
# the rule that a match may only scrutinize a parameter or a
# pattern-bound field, never a computed value.
def dispatch.exact_health(is_health: Bool) -> String:
  match is_health:
    case True{}:
      health()
    case False{}:
      Http.not_found()

def dispatch.exact(is_root: Bool, is_health: Bool) -> String:
  match is_root:
    case True{}:
      home()
    case False{}:
      dispatch.exact_health(is_health)

def dispatch.on_exact(+path: String) -> String:
  is_root = String.eq(path, "/")
  is_health = String.eq(path, "/health")
  dispatch.exact(is_root, is_health)

def dispatch.on_method(+path: String, is_get: Bool) -> String:
  match is_get:
    case True{}:
      dispatch.on_exact(path)
    case False{}:
      Http.text_response(400n, "only GET is supported\n")

def dispatch.got(req: Http.Request) -> String:
  Http.Request{method, +path} = req
  dispatch.on_method(path, String.eq(method, "GET"))

def dispatch(raw: String) -> String:
  dispatch.got(Http.parse_request(raw))

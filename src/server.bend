import Base
import ./http.bend as Http
import ./route.bend as Route
import ./runtime.bend as Runtime
import ./compute.bend as Compute

# Server
# ======
#
# The IO shell: bind a listener, then loop forever accepting
# connections and handing each one to its own concurrently-spawned
# handler, so one slow client never blocks another. Request parsing and
# formatting stay pure (Http/Route); this file is where the one heavy
# computation actually gets called and timed, since forcing a value and
# reading a clock are both IO.
#
# Concurrency model, in short:
#  - `IO.spawn` puts a handler on the single-threaded event loop as a
#    green task; many connections are served interleaved without
#    blocking each other on `recv`/`send` (both non-blocking + poll).
#  - Inside a handler, `Compute.pow2`/`pow2!` fan out across every CPU
#    core (plain parallel calls) or the GPU (`!` calls) for the one
#    workload heavy enough to want it, so one request can use the whole
#    machine without starving the accept loop.
#  - Real multi-core and GPU use only happens in a binary built with
#    `bend main.bend -o build/http_server` and run with `--threads N` /
#    `--gpu`; see README.md.

def port() -> U32:
  8080

def recv_max() -> U32:
  16384

# The accept loop is bounded by fuel, not a true infinite loop, per
# `bend guide`'s rule that recursion must terminate structurally. A
# ~2^32-step budget is, in practice, forever (the same trick Base's own
# `App.loop` uses for a window's frame loop).
def forever() -> Nat:
  U32.to_nat(4294967295)

def close_after_send.go(
  sock: Socket, r: Result<&1, &1, U32 & String, Unit>
) -> IO(Unit):
  match r:
    case Done{v}:
      Socket.close(sock)
    case Fail{e}:
      Socket.close(sock)

def close_after_send(sr: Socket & Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  (sock, r) = sr
  close_after_send.go(sock, r)

def reply(sock: Socket, resp: String) -> IO(Unit):
  do IO<Unit>:
    sr : Socket & Result<&1, &1, U32 & String, Unit> <- TCP.send(sock, resp)
    close_after_send(sr)

def handle.info_done(sock: Socket, ti: U32 & U32) -> IO(Unit):
  (threads, gpu) = ti
  reply(sock, Route.info_page(threads, U32.is_eq(gpu, 1)))

def handle.info(sock: Socket) -> IO(Unit):
  do IO<Unit>:
    ti : U32 & U32 <- Runtime.info()
    handle.info_done(sock, ti)

# Picks the CPU-parallel or GPU call. Both are proven (LAWS.bend,
# `pow2_gpu_agrees`) to return the same value; the flag only decides
# *where* the fork-join tree runs.
def compute_calc(is_gpu: Bool, +k: Nat) -> Nat:
  match is_gpu:
    case True{}:
      Compute.pow2!(k)
    case False{}:
      Compute.pow2(k)

# Forcing `result` here (by printing it, server-side) before the second
# clock read is what makes `cpu_ms`/`wall_ms` measure the computation
# itself, instead of the near-zero time it takes to build an unevaluated
# thunk. `+result` (Nat is Data) means the print does not recompute
# anything the reply below reuses.
def handle.timed_done(
  sock: Socket, +n: Nat, +result: Nat, t0: Nat, c0: Nat, t1: Nat, c1: Nat
) -> IO(Unit):
  reply(sock, Route.timed_response(n, result, Nat.sub(t1, t0), Nat.sub(c1, c0)))

def handle.timed_calc(sock: Socket, is_gpu: Bool, +n: Nat, t0: Nat, c0: Nat) -> IO(Unit):
  do IO<Unit>:
    +result : Nat = compute_calc(is_gpu, n)
    logged : Unit <- IO.print(String.concat(["computed 2^", Nat.show(n), " = ", Nat.show(result)]))
    t1 : Nat <- IO.now()
    c1 : Nat <- Runtime.cpu_ms()
    handle.timed_done(sock, n, result, t0, c0, t1, c1)

def handle.timed(sock: Socket, is_gpu: Bool, +n: Nat) -> IO(Unit):
  do IO<Unit>:
    t0 : Nat <- IO.now()
    c0 : Nat <- Runtime.cpu_ms()
    handle.timed_calc(sock, is_gpu, n, t0, c0)

def handle.compute_or_bad(sock: Socket, is_gpu: Bool, parsed: Maybe<&2, Nat>) -> IO(Unit):
  match parsed:
    case None{}:
      reply(sock, Route.bad_n_response())
    case Some{+n}:
      handle.timed(sock, is_gpu, n)

def handle.gpu(sock: Socket, +raw: String, hit: Maybe<&2, String>) -> IO(Unit):
  match hit:
    case Some{rest}:
      handle.compute_or_bad(sock, True{}, Route.parse_n(rest))
    case None{}:
      reply(sock, Route.dispatch(raw))

def handle.compute(
  sock: Socket, +path: String, +raw: String, hit: Maybe<&2, String>
) -> IO(Unit):
  match hit:
    case Some{rest}:
      handle.compute_or_bad(sock, False{}, Route.parse_n(rest))
    case None{}:
      handle.gpu(sock, raw, Http.strip_prefix(path, "/gpu/"))

def handle.info_or_more(
  sock: Socket, +path: String, +raw: String, is_info: Bool
) -> IO(Unit):
  match is_info:
    case True{}:
      handle.info(sock)
    case False{}:
      handle.compute(sock, path, raw, Http.strip_prefix(path, "/compute/"))

def handle.req(sock: Socket, req: Http.Request, +raw: String) -> IO(Unit):
  Http.Request{method, +path} = req
  handle.info_or_more(sock, path, raw, Route.wants_info(method, path))

def handle.parsed(sock: Socket, +raw: String) -> IO(Unit):
  handle.req(sock, Http.parse_request(raw), raw)

def handle.route(sock: Socket, r: Result<&1, &1, U32 & String, String>) -> IO(Unit):
  match r:
    case Fail{e}:
      Socket.close(sock)
    case Done{raw}:
      handle.parsed(sock, raw)

def handle.recvd(rr: Socket & Result<&1, &1, U32 & String, String>) -> IO(Unit):
  (sock, r) = rr
  handle.route(sock, r)

# One connection's whole lifetime: read one request (assumed to arrive
# in a single `recv`, which every request line + header block under
# `recv_max()` bytes does), route it, reply, close. `Connection: close`
# in every response (see http.bend) matches this one-shot handling.
def handle(sock: Socket) -> IO(Unit):
  do IO<Unit>:
    rr : Socket & Result<&1, &1, U32 & String, String> <- TCP.recv(sock, recv_max())
    handle.recvd(rr)

def accept_loop.route(
  listener: Listener, r: Result<&1, &1, U32 & String, Socket>,
  cont: Listener -> IO(Unit)
) -> IO(Unit):
  match r:
    case Fail{e}:
      # A transient accept error (e.g. the accepting fd hiccuped): the
      # listener is still good, so keep serving instead of dying.
      cont(listener)
    case Done{sock}:
      do IO<Unit>:
        IO.spawn(Unit, handle(sock))
        cont(listener)

def accept_loop.got(
  ar: Listener & Result<&1, &1, U32 & String, Socket>, cont: Listener -> IO(Unit)
) -> IO(Unit):
  (listener, r) = ar
  accept_loop.route(listener, r, cont)

# Self-recursion only, exactly as `App.loop` does it: the fuel argument
# comes first and is what shrinks (`1n+f` hands out the smaller `f`),
# so every other helper above calls back through the `cont` closure
# instead of naming `accept_loop` itself -- Bend disallows mutual
# recursion, so the loop-back must happen through a value, not a name.
def accept_loop(fuel: Nat, listener: Listener) -> IO(Unit):
  match fuel:
    case 0n:
      Listener.close(listener)
    case 1n+f:
      do IO<Unit>:
        ar : Listener & Result<&1, &1, U32 & String, Socket> <- TCP.accept(listener)
        accept_loop.got(ar, next => accept_loop(f, next))

def run() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.append("http_server listening on :", Nat.show(U32.to_nat(port()))))
    listener : Listener <- IO.try(Listener, TCP.listen(port()))
    accept_loop(forever(), listener)


# bend-http-server

An HTTP server written in Bend2 supporting running on multi-core CPU and GPU.

Built in [Bend](https://bend-lang.com), a language that compiles the same
source to a parallel CPU program and a GPU kernel. This project uses that
to run a real HTTP/1.1 server across every core (and the GPU, where it
helps) -- and proves, in `LAWS.bend`/`PROOF.bend`, that splitting the work
across hardware never changes the answer.

https://github.com/user-attachments/assets/d31c3356-b942-4a69-852b-25a7d211e0b9

## Layout

```
main.bend          entry point: def main() -> IO(Unit)
src/server.bend     IO shell: listen, accept loop, one handler per connection
src/route.bend      pure request -> response dispatcher (routing)
src/http.bend       pure HTTP/1.1 parsing + response formatting, no IO
src/compute.bend    the one CPU/GPU-heavy workload (pow2 fork-join tree)
src/runtime.bend    two small IO effects: how many threads / whether the
                    GPU is active (GET /info), and process CPU time for
                    measuring realized parallelism per request
src/effs/           the C + JS implementation of those two custom effects
LAWS.bend           open claims (human-authored, per `bend guide`'s convention)
PROOF.bend          proofs of every law above (`bend PROOF.bend` is the gate)
```

`Http`/`Compute`/`Route` are pure (no `IO`), which is what makes them provable
in `LAWS.bend`/`PROOF.bend`. `Server` is the only file that touches a socket.

## Running it

Development (checks the file, runs on Bun's JS backend -- correct, but
single-threaded; the JS backend "ignores" parallel calls and the GPU per
`bend guide`):

```bash
bend main.bend
```

For real multi-core / GPU use, compile to a native binary and run that
instead -- this is the only way `!` calls and plain parallel calls actually
fan out across hardware:

```bash
bend main.bend -o build/http_server
./build/http_server                       # --threads defaults to the CPU count
./build/http_server --threads 8           # pin the worker-thread pool
./build/http_server --gpu off             # CPU-only, for comparison
./build/http_server --threads 4 --gpu on  # both
```

A build that uses `!` (ours does, in `/gpu/<n>`) also writes
`build/http_server.gpu`; keep it next to the binary. GPU builds need clang 19+
(Apple clang 17 ships LLVM 19) -- `bend main.bend -o ...` will tell you if
your toolchain is too old, and the binary simply runs `!` calls on the CPU
instead when no GPU is present at runtime.

## Routes

| Route            | What it does                                              |
|-------------------|-----------------------------------------------------------|
| `GET /`           | this list                                                  |
| `GET /health`     | `OK`                                                       |
| `GET /info`       | **actual** thread count and GPU on/off for this process    |
| `GET /compute/<n>`| `2^n`, computed by a fork-join tree fanned across CPU cores, with a real measurement of how much of the machine it used |
| `GET /gpu/<n>`    | the same computation, offloaded to the GPU via `!`, same measurement |

`<n>` is capped at 28 (`Compute.max_n`); a larger value is a `400`, not a slow
or crashed request. `/compute` and `/gpu` are proven to always agree (see
below), so which one you call is purely a perf choice.

```bash
curl localhost:8080/compute/26
# n: 26
# result: 67108864
# wall_ms: 48
# cpu_ms (every worker thread, summed): 303
# cores_used (cpu_ms / wall_ms): 6.3
```

`GET /info` is the honest answer to "is this actually parallel / on the
GPU?" -- it doesn't guess from flags, it reads the runtime's own
`pool_size`/`io_gpu` globals through a tiny custom effect
(`src/effs/runtime_info.c`), the same mechanism Base's own `TCP`/`File`
effects use.

```bash
curl localhost:8080/info
# threads: 8
# gpu: True
```

Note: `bend main.bend` (no `-o`) runs on Bun's JS backend, which is always
single-threaded and never touches the GPU (`bend guide`: "The JavaScript
target ignores all that and just runs sequentially"). `/info` on that
backend reports the OS's CPU count as a courtesy, and `gpu: False` always --
neither is a real measurement there. Build with `-o` and run the binary to
get real numbers.

## How many threads / GPU cores did *this* request actually use?

`/info`'s thread count is only the size of the worker pool the process
started with -- an upper bound, not what any one request used. `/compute`
and `/gpu` answer the sharper question for real, per request:

- `wall_ms` -- wall-clock time the computation took.
- `cpu_ms` -- CPU time consumed by the whole process (every worker thread's
  user + system time, summed) over that same window, read via
  `getrusage(RUSAGE_SELF, ...)` (`src/effs/cpu_time.c`).
- `cores_used = cpu_ms / wall_ms` -- if one core were busy the whole time,
  this is ~1.0; if six cores were busy the whole time, it's ~6.0. This is
  the standard way to measure realized parallelism (it's what `time`'s
  `user+sys` vs `real` columns are doing), applied to one request instead
  of a whole process run.

This is a real measurement, not a guess -- confirmed against `--threads N`:
`--threads 1` -> ~1.0, `--threads 4` -> ~3.7, `--threads 8` -> ~6.0 (never
quite N, because of scheduling/join overhead).

For the GPU, the honest answer is narrower: Bend has no equivalent of
`getrusage` for a GPU device, and how many of a GPU's physical cores a
kernel launch actually occupied is a fact the GPU driver knows, not
something this process can observe about itself. `cores_used` on `/gpu/<n>`
still means exactly what it says (CPU cores kept busy meanwhile) -- for
this workload that number is low (~0.2), because the CPU is mostly idle
waiting on the GPU round-trip, which is itself useful information (see
below).

If you need actual GPU occupancy, that requires a vendor profiler outside
Bend: Instruments' Metal System Trace on macOS, or Nsight Compute for CUDA,
attached to the running binary while you hit `/gpu/<n>`.

## How the concurrency actually works

- One event loop accepts connections; each accepted socket is handed to
  `IO.spawn`, so many connections are served concurrently without one slow
  client blocking another (`recv`/`send` are non-blocking + poll-driven under
  the hood).
- Inside a single request, the heavy workload (`Compute.pow2`) is a
  fork-join binary tree: a plain parallel call (`a b = pow2(p) pow2(p)`)
  fans across every worker thread on a native build; the same call written
  with `!` (`pow2!(n)`) fans across the GPU instead. Nothing about the code
  changes between the two -- only where the scheduler puts the work.
- Real numbers, measured on a 10-core M1 Pro: `/compute/26` at
  `--threads 8` measured `cores_used: 6.3`; `/compute/28` scaled from ~1.2s
  single-threaded to ~0.2s at `--threads 10` (~6x from parallel CPU alone).
  `/gpu/26` measured `wall_ms: 882` vs `/compute/26`'s `wall_ms: 48` -- GPU
  dispatch overhead makes the GPU path slower than CPU-parallel for this
  specific fine-grained workload, expected per `bend guide`: the GPU shines
  on bulk uniform numeric work (mandelbrot, n-body), not on cheap,
  pointer-chasing fork-join trees. `/gpu/<n>` is kept as a real,
  correctness-proven GPU code path (useful once the workload is the
  GPU-friendly kind), not as a performance claim.

## Proofs

```bash
bend PROOF.bend
# All terms check.
```

`LAWS.bend` states three facts, each proven in `PROOF.bend`:

- **`pow2_spec`** -- the parallel fork-join tree (`Compute.pow2`) always
  equals the sequential spec `2^n`. This is the fact that actually backs
  "the parallel code has no bugs": no matter how the scheduler splits the
  recursion across cores, the *value* can't change.
- **`pow2_gpu_agrees`** -- `Compute.pow2(n) == Compute.pow2!(n)`: the `!`
  annotation changes *where* a parallel call runs, never *what* it computes.
  This is what lets `/compute/<n>` and `/gpu/<n>` promise callers the same
  answer.
- **`in_range_matches_max_n`** -- the bound the routes enforce before
  running any work is exactly the bound the proofs above hold for, kept as
  an explicit law so the two can't silently drift apart.

## Known limits (by design, not oversight)

- One request per connection (`Connection: close`); no keep-alive, no
  pipelining. Keeps the protocol subset small enough that `Http`/`Route` stay
  easy to state laws about.
- A request must arrive in a single `recv` (16 KiB budget) -- true for every
  plain `GET` this server handles; a request split across TCP segments large
  enough to miss that budget is answered with whatever arrived, which for the
  routes here (`GET`, no body, short paths) does not occur in practice.
- No HTTPS/TLS.

## License

MIT -- see [LICENSE](LICENSE).

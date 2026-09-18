// Runtime
// =======
//
// User + system CPU time for the whole process, in milliseconds.
// `getrusage(RUSAGE_SELF, ...)` sums this across every thread the
// process has ever run, which is exactly what makes "cpu_ms delta /
// wall_ms delta" over one computation a real measurement of how many
// cores were kept busy doing it -- not a guess from `--threads`.
#include <sys/resource.h>

Term cpu_ms_run(Env e, Term* f, IoWork* w) {
  struct rusage ru;
  getrusage(RUSAGE_SELF, &ru);
  u64 user_ms = (u64)ru.ru_utime.tv_sec * 1000 + (u64)ru.ru_utime.tv_usec / 1000;
  u64 sys_ms  = (u64)ru.ru_stime.tv_sec * 1000 + (u64)ru.ru_stime.tv_usec / 1000;
  return (Term)(user_ms + sys_ms);
}

static void __attribute__((constructor)) cpu_ms_use(void) {
  io_eff(CID_CPU_MS, cpu_ms_run, 0);
}

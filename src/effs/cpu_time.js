// Runtime
// =======
//
// The JS backend is always single-threaded, so this number is only ever
// a lower bound / sanity check there -- the honest measurement (see
// cpu_time.c) only means something in a native, multi-threaded build.
function cpu_ms() {
  const u = process.cpuUsage();
  return BigInt(Math.floor((u.user + u.system) / 1000));
}

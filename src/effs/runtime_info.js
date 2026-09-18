// Runtime
// =======
//
// The JS backend never threads or touches a GPU (`bend guide`: "The
// JavaScript target ignores all that and just runs sequentially"), so
// this reports the OS's logical core count -- an honest number for
// "how many cores could a native build use here" -- next to a GPU flag
// pinned to 0. Only the C effect (runtime_info.c) reports what the
// running process is actually doing.
function info() {
  return io_tup(require("node:os").cpus().length, 0);
}

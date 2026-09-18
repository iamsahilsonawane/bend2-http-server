// Runtime
// =======
//
// `pool_size` and `io_gpu` are the runtime's own record of the flags the
// binary was launched with (`--threads N`, `--gpu on|off`); reading them
// here, instead of hard-coding a guess, is the only way `/info` can answer
// honestly about how many workers and whether the GPU lane are really in
// use. Both are file-scope globals declared earlier in the same generated
// C file (see corpus_setup), so this effect only has to read them.
Term runtime_info_run(Env e, Term* f, IoWork* w) {
  return io_tup(e, (Term)pool_size, (Term)(io_gpu ? 1u : 0u));
}

static void __attribute__((constructor)) runtime_info_use(void) {
  io_eff(CID_INFO, runtime_info_run, 0);
}

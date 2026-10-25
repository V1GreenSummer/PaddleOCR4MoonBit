///|
test "engine options builders keep the standard defaults" {
  let options = @engine.EngineOptions::standard()
    .with_intra_op_threads(4)
    .with_inter_op_threads(2)
    .with_graph_optimization(@engine.Extended)
    .with_execution_mode(@engine.Parallel)
    .with_rec_batch_size(16)
  inspect(options.intra_op_threads, content="4")
  inspect(options.inter_op_threads, content="2")
  debug_inspect(options.graph_optimization, content="Extended")
  debug_inspect(options.execution_mode, content="Parallel")
  inspect(options.rec_batch_size, content="16")
}

///|
test "engine options default is the standard preset" {
  let options : @engine.EngineOptions = Default::default()
  inspect(options.intra_op_threads, content="0")
  debug_inspect(options.graph_optimization, content="All")
  debug_inspect(options.execution_mode, content="Sequential")
  inspect(options.rec_batch_size, content="8")
}

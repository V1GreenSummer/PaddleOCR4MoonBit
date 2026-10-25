///|
/// Graph optimization level passed to ONNX Runtime.
pub(all) enum GraphOptimizationLevel {
  DisableAll
  Basic
  Extended
  Layout
  All
} derive(Debug, Eq, ToJson)

///|
pub extend GraphOptimizationLevel with Eq::{not_equal, equal}

///|
pub extend GraphOptimizationLevel with @debug.Debug::{to_repr}

///|
pub extend GraphOptimizationLevel with ToJson::{to_json}

///|
/// Sequential or parallel execution inside one ONNX Runtime session.
pub(all) enum ExecutionMode {
  Sequential
  Parallel
} derive(Debug, Eq, ToJson)

///|
pub extend ExecutionMode with Eq::{not_equal, equal}

///|
pub extend ExecutionMode with @debug.Debug::{to_repr}

///|
pub extend ExecutionMode with ToJson::{to_json}

///|
/// Native session configuration. Zero thread counts keep ONNX Runtime's
/// default. `rec_batch_size` is only used when the recognition model has a
/// dynamic batch axis.
pub(all) struct EngineOptions {
  intra_op_threads : Int32
  inter_op_threads : Int32
  graph_optimization : GraphOptimizationLevel
  execution_mode : ExecutionMode
  rec_batch_size : Int32
} derive(Debug, Eq, ToJson)

///|
pub extend EngineOptions with Eq::{not_equal, equal}

///|
pub extend EngineOptions with @debug.Debug::{to_repr}

///|
pub extend EngineOptions with ToJson::{to_json}

///|
/// CPU defaults: ONNX Runtime thread counts, all graph optimizations, sequential
/// execution, and up to 8 crops per recognition run.
///
/// # Example
/// ```mbt check
/// test {
///   let options = @engine.EngineOptions::standard().with_intra_op_threads(4)
///   inspect(options.intra_op_threads, content="4")
///   inspect(options.rec_batch_size, content="8")
/// }
/// ```
pub fn EngineOptions::standard() -> EngineOptions {
  {
    intra_op_threads: 0,
    inter_op_threads: 0,
    graph_optimization: All,
    execution_mode: Sequential,
    rec_batch_size: 8,
  }
}

///|
pub impl Default for EngineOptions with fn default() {
  EngineOptions::standard()
}

///|
pub extend EngineOptions with Default::{default}

///|
pub fn EngineOptions::with_intra_op_threads(
  self : EngineOptions,
  intra_op_threads : Int32,
) -> EngineOptions {
  { ..self, intra_op_threads, }
}

///|
pub fn EngineOptions::with_inter_op_threads(
  self : EngineOptions,
  inter_op_threads : Int32,
) -> EngineOptions {
  { ..self, inter_op_threads, }
}

///|
pub fn EngineOptions::with_graph_optimization(
  self : EngineOptions,
  graph_optimization : GraphOptimizationLevel,
) -> EngineOptions {
  { ..self, graph_optimization, }
}

///|
pub fn EngineOptions::with_execution_mode(
  self : EngineOptions,
  execution_mode : ExecutionMode,
) -> EngineOptions {
  { ..self, execution_mode, }
}

///|
pub fn EngineOptions::with_rec_batch_size(
  self : EngineOptions,
  rec_batch_size : Int32,
) -> EngineOptions {
  { ..self, rec_batch_size, }
}

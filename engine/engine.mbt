///|
/// Native PP-OCR pipeline. Detection and recognition are two CPU ONNX sessions
/// loaded through moon-ort. Close the engine once, or use `with_scope` /
/// `with_engine` to close it automatically.
pub struct Engine {
  priv runtime : @raw.Runtime
  priv options : @session.SessionOptions
  priv det : @session.Session
  priv rec : @session.Session
  priv charset : @paddleocr.Charset
  priv det_input : String
  priv det_output : String
  priv rec_input : String
  priv rec_output : String
  priv rec_height : Int32
  priv rec_fixed_width : Int32?
  priv rec_dynamic_batch : Bool
  priv rec_batch_size : Int32
}

///|
/// `MOON_ORT_LIBRARY`, when the process set it.
pub fn runtime_library() -> String? {
  @session.configured_library()
}

///|
fn runtime_error(error : Error) -> @paddleocr.OcrError {
  @paddleocr.OcrError::runtime(error.to_string())
}

///|
fn ignore_close(tensor : @tensor.Tensor) -> Unit {
  tensor.close() catch {
    _ => ()
  }
}

///|
fn close_all(tensors : Array[@tensor.Tensor]) -> Unit {
  for tensor in tensors {
    ignore_close(tensor)
  }
}

///|
fn require_float(
  session : @session.Session,
  input : Bool,
) -> Unit raise @paddleocr.OcrError {
  let dtype = if input {
    session.input_dtype(0) catch {
      error => raise runtime_error(error)
    }
  } else {
    session.output_dtype(0) catch {
      error => raise runtime_error(error)
    }
  }
  match dtype {
    @session.Float32 => ()
    other =>
      raise @paddleocr.OcrError::model(
        "tensor must be float32, got \{other.text()}",
      )
  }
}

///|
fn io_name(
  session : @session.Session,
  input : Bool,
) -> String raise @paddleocr.OcrError {
  let count = if input {
    session.input_count() catch {
      error => raise runtime_error(error)
    }
  } else {
    session.output_count() catch {
      error => raise runtime_error(error)
    }
  }
  if count < 1 {
    raise @paddleocr.OcrError::model("model has no tensor")
  }
  if input {
    session.input_name(0) catch {
      error => raise runtime_error(error)
    }
  } else {
    session.output_name(0) catch {
      error => raise runtime_error(error)
    }
  }
}

///|
fn rec_geometry(
  session : @session.Session,
) -> (Int32, Int32?, Bool) raise @paddleocr.OcrError {
  let dims = session.input_dimensions(0) catch {
    error => raise runtime_error(error)
  }
  if dims.length() != 4 {
    raise @paddleocr.OcrError::model("recognition input must be NCHW")
  }
  let height = match dims[2] {
    @session.Fixed(size) =>
      if size > 0L && size <= 4096L {
        size.to_int()
      } else {
        48
      }
    @session.Symbolic(_) => 48
  }
  let width = match dims[3] {
    @session.Fixed(size) =>
      if size > 0L && size <= 4096L {
        Some(size.to_int())
      } else {
        None
      }
    @session.Symbolic(_) => None
  }
  let dynamic_batch = match dims[0] {
    @session.Fixed(_) => false
    @session.Symbolic(_) => true
  }
  (height, width, dynamic_batch)
}

///|
fn require_model_file(
  path : String,
  label : String,
) -> Unit raise @paddleocr.OcrError {
  if !@fs.path_exists(path) {
    raise @paddleocr.OcrError::config("\{label} model not found: \{path}")
  }
}

///|
fn session_graph(level : GraphOptimizationLevel) -> @session.GraphOptimization {
  match level {
    DisableAll => @session.DisableAll
    Basic => @session.Basic
    Extended => @session.Extended
    Layout => @session.Layout
    All => @session.All
  }
}

///|
fn session_execution(mode : ExecutionMode) -> @session.ExecutionMode {
  match mode {
    Sequential => @session.Sequential
    Parallel => @session.Parallel
  }
}

///|
/// Load the ONNX Runtime shared library and the two PP-OCR models.
///
/// `options` controls thread counts, graph optimization, execution mode, and
/// the recognition batch size. Omitted options use `EngineOptions::standard`.
pub fn Engine::open(
  library~ : String,
  det_model~ : String,
  rec_model~ : String,
  charset~ : @paddleocr.Charset,
  options? : EngineOptions,
) -> Engine raise @paddleocr.OcrError {
  let settings = match options {
    Some(options) => options
    None => EngineOptions::standard()
  }
  if settings.intra_op_threads < 0 || settings.inter_op_threads < 0 {
    raise @paddleocr.OcrError::config("thread counts must be non-negative")
  }
  if settings.rec_batch_size < 1 {
    raise @paddleocr.OcrError::config("rec_batch_size must be at least 1")
  }
  let runtime = @raw.Runtime::load(library) catch {
    error => raise runtime_error(error)
  }
  errdefer (runtime.close() catch { _ => () })
  let session_options = @session.SessionOptions::create(runtime) catch {
    error => raise runtime_error(error)
  }
  errdefer (session_options.close() catch { _ => () })
  session_options.set_execution_mode(session_execution(settings.execution_mode)) catch {
    error => raise runtime_error(error)
  }
  session_options.set_graph_optimization_level(
    session_graph(settings.graph_optimization),
  ) catch {
    error => raise runtime_error(error)
  }
  if settings.intra_op_threads > 0 {
    session_options.set_intra_op_threads(settings.intra_op_threads) catch {
      error => raise runtime_error(error)
    }
  }
  if settings.inter_op_threads > 0 {
    session_options.set_inter_op_threads(settings.inter_op_threads) catch {
      error => raise runtime_error(error)
    }
  }
  require_model_file(det_model, "detection")
  require_model_file(rec_model, "recognition")
  let det = @session.Session::create(runtime, session_options, det_model) catch {
    error => raise @paddleocr.OcrError::model(error.to_string())
  }
  errdefer (det.close() catch { _ => () })
  let rec = @session.Session::create(runtime, session_options, rec_model) catch {
    error => raise @paddleocr.OcrError::model(error.to_string())
  }
  errdefer (rec.close() catch { _ => () })
  require_float(det, true)
  require_float(det, false)
  require_float(rec, true)
  require_float(rec, false)
  let (rec_height, rec_fixed_width, rec_dynamic_batch) = rec_geometry(rec)
  {
    runtime,
    options: session_options,
    det,
    rec,
    charset,
    det_input: io_name(det, true),
    det_output: io_name(det, false),
    rec_input: io_name(rec, true),
    rec_output: io_name(rec, false),
    rec_height,
    rec_fixed_width,
    rec_dynamic_batch,
    rec_batch_size: if rec_dynamic_batch {
      settings.rec_batch_size
    } else {
      1
    },
  }
}

///|
/// Release both sessions, the options, and the runtime.
pub fn Engine::close(self : Engine) -> Unit {
  self.det.close() catch {
    _ => ()
  }
  self.rec.close() catch {
    _ => ()
  }
  self.options.close() catch {
    _ => ()
  }
  self.runtime.close() catch {
    _ => ()
  }
}

///|
fn Engine::run_nchw(
  self : Engine,
  session : @session.Session,
  input_name : String,
  output_name : String,
  batch : Int32,
  height : Int32,
  width : Int32,
  values : Array[Float],
) -> (Array[Float], Array[Int64]) raise @paddleocr.OcrError {
  let input = @tensor.Tensor::from_f32(
    self.runtime,
    [batch.to_int64(), 3L, height.to_int64(), width.to_int64()],
    values,
  ) catch {
    error => raise runtime_error(error)
  }
  errdefer ignore_close(input)
  let outputs = session.run([input_name], [input], [output_name]) catch {
    error => raise runtime_error(error)
  }
  errdefer close_all(outputs)
  if outputs.length() != 1 {
    raise @paddleocr.OcrError::model("expected one output tensor")
  }
  let values = outputs[0].read_f32() catch {
    error => raise runtime_error(error)
  }
  let shape = outputs[0].shape() catch { error => raise runtime_error(error) }
  close_all(outputs)
  input.close() catch {
    error => raise runtime_error(error)
  }
  (values, shape)
}

///|
fn Engine::run_chw(
  self : Engine,
  session : @session.Session,
  input_name : String,
  output_name : String,
  tensor : @paddleocr.ChwTensor,
) -> (Array[Float], Array[Int64]) raise @paddleocr.OcrError {
  self.run_nchw(
    session,
    input_name,
    output_name,
    1,
    tensor.height,
    tensor.width,
    tensor.values,
  )
}

///|
fn map_hw(shape : Array[Int64]) -> (Int32, Int32) raise @paddleocr.OcrError {
  if shape.length() < 2 {
    raise @paddleocr.OcrError::model("detection map rank is too small")
  }
  let height = shape[shape.length() - 2].to_int()
  let width = shape[shape.length() - 1].to_int()
  if height <= 0 || width <= 0 {
    raise @paddleocr.OcrError::model("detection map size is empty")
  }
  let mut lead = 1
  for index in 0..<(shape.length() - 2) {
    lead = lead * shape[index].to_int()
  }
  if lead != 1 {
    raise @paddleocr.OcrError::model("detection map must be a single channel")
  }
  (height, width)
}

///|
fn map_tc(
  shape : Array[Int64],
) -> (Int32, Int32, Int32) raise @paddleocr.OcrError {
  let (batch, time, classes) = match shape.length() {
    2 => (1, shape[0].to_int(), shape[1].to_int())
    3 => (shape[0].to_int(), shape[1].to_int(), shape[2].to_int())
    _ =>
      raise @paddleocr.OcrError::model("recognition output rank must be 2 or 3")
  }
  if batch < 1 || time <= 0 || classes <= 0 {
    raise @paddleocr.OcrError::model("recognition output shape is empty")
  }
  (batch, time, classes)
}

///|
fn Engine::prepare_rec_tensor(
  self : Engine,
  image : @paddleocr.Rgba,
  options : @paddleocr.RecognizeOptions,
) -> @paddleocr.ChwTensor raise @paddleocr.OcrError {
  match self.rec_fixed_width {
    Some(width) =>
      @paddleocr.prepare_rec(image, height=self.rec_height, fixed_width=width)
    None =>
      @paddleocr.prepare_rec(
        image,
        height=self.rec_height,
        max_width=options.rec_max_width,
      )
  }
}

///|
fn library_path(library : String?) -> String raise @paddleocr.OcrError {
  match library {
    Some(path) => path
    None =>
      match runtime_library() {
        Some(path) => path
        None =>
          raise @paddleocr.OcrError::usage(
            "set MOON_ORT_LIBRARY or pass library",
          )
      }
  }
}

///|
/// Read a PP-OCR dictionary, append its space class, and open both models.
///
/// `library` defaults to `MOON_ORT_LIBRARY`. The dictionary is read before the
/// runtime is loaded. One engine can then recognize many images; call `close`
/// once when finished. `options` configures ONNX Runtime and recognition
/// batching.
pub fn Engine::load(
  det~ : String,
  rec~ : String,
  dict~ : String,
  library? : String,
  options? : EngineOptions,
) -> Engine raise @paddleocr.OcrError {
  let resolved = library_path(library)
  let text = @fs.read_file_to_string(dict) catch {
    @fs.IOError(message) => raise @paddleocr.OcrError::io(message)
  }
  Engine::open(
    library=resolved,
    det_model=det,
    rec_model=rec,
    charset=@paddleocr.Charset::ppocr(text),
    options?,
  )
}

///|
/// Run the detection session and return quads in source-image coordinates.
///
/// Omitted `options` use `RecognizeOptions::standard`. Only the detection
/// fields of the options are used.
pub fn Engine::detect(
  self : Engine,
  image : @paddleocr.Rgba,
  options? : @paddleocr.RecognizeOptions,
) -> Array[@paddleocr.DetQuad] raise @paddleocr.OcrError {
  let options = resolve_recognize_options(options)
  let prepared = @paddleocr.prepare_det(
    image,
    limit_side_len=options.limit_side_len,
  )
  let (prob, shape) = self.run_chw(
    self.det,
    self.det_input,
    self.det_output,
    prepared.tensor,
  )
  let (map_h, map_w) = map_hw(shape)
  let found = @paddleocr.db_quads(
    prob,
    height=map_h,
    width=map_w,
    thresh=options.det_thresh,
    box_thresh=options.box_thresh,
    unclip_ratio=options.unclip_ratio,
    min_size=options.min_size,
  )
  let scale_x = prepared.tensor.width.to_double() /
    map_w.to_double() /
    prepared.ratio_w
  let scale_y = prepared.tensor.height.to_double() /
    map_h.to_double() /
    prepared.ratio_h
  let quads : Array[@paddleocr.DetQuad] = []
  for quad in found {
    quads.push(quad.scale(scale_x, scale_y))
  }
  quads
}

///|
/// Recognize existing RGBA crops and return one CTC result per crop.
///
/// Results are in input order. `rec_thresh` is not applied here, so callers can
/// inspect low-confidence output. Crops with the same prepared width are run
/// together when the model has a dynamic batch axis.
pub fn Engine::recognize_regions(
  self : Engine,
  crops : Array[@paddleocr.Rgba],
  options? : @paddleocr.RecognizeOptions,
) -> Array[@paddleocr.CtcText] raise @paddleocr.OcrError {
  let options = resolve_recognize_options(options)
  if crops.length() == 0 {
    return []
  }
  let tensors : Array[@paddleocr.ChwTensor] = []
  for crop in crops {
    tensors.push(self.prepare_rec_tensor(crop, options))
  }
  let results : Array[@paddleocr.CtcText?] = Array::make(crops.length(), None)
  if !self.rec_dynamic_batch || self.rec_batch_size <= 1 {
    for index in 0..<tensors.length() {
      let tensor = tensors[index]
      let (logits, shape) = self.run_nchw(
        self.rec,
        self.rec_input,
        self.rec_output,
        1,
        tensor.height,
        tensor.width,
        tensor.values,
      )
      let (batch, time, classes) = map_tc(shape)
      if batch != 1 {
        raise @paddleocr.OcrError::model("expected a single recognition batch")
      }
      results[index] = Some(
        @paddleocr.ctc_decode(logits, time~, classes~, charset=self.charset),
      )
    }
  } else {
    let widths : Array[Int32] = []
    let groups : Array[Array[Int32]] = []
    for index in 0..<tensors.length() {
      let width = tensors[index].width
      let mut slot = -1
      for candidate in 0..<widths.length() {
        if widths[candidate] == width {
          slot = candidate
          break
        }
      }
      if slot < 0 {
        widths.push(width)
        groups.push([index])
      } else {
        groups[slot].push(index)
      }
    }
    for group in groups {
      let mut start = 0
      while start < group.length() {
        let end = if start + self.rec_batch_size < group.length() {
          start + self.rec_batch_size
        } else {
          group.length()
        }
        let batch = end - start
        let first = tensors[group[start]]
        let values : Array[Float] = Array::make(
          first.values.length() * batch,
          0.0,
        )
        let mut offset = 0
        for cursor in start..<end {
          let tensor = tensors[group[cursor]]
          if tensor.height != first.height || tensor.width != first.width {
            raise @paddleocr.OcrError::model("recognition batch shapes differ")
          }
          for value_index in 0..<tensor.values.length() {
            values[offset + value_index] = tensor.values[value_index]
          }
          offset = offset + tensor.values.length()
        }
        let (logits, shape) = self.run_nchw(
          self.rec,
          self.rec_input,
          self.rec_output,
          batch,
          first.height,
          first.width,
          values,
        )
        let (out_batch, time, classes) = map_tc(shape)
        if out_batch != batch {
          raise @paddleocr.OcrError::model(
            "recognition batch size does not match the model output",
          )
        }
        let sample_size = time * classes
        if logits.length() != sample_size * batch {
          raise @paddleocr.OcrError::model(
            "recognition output length does not match its shape",
          )
        }
        for cursor in 0..<batch {
          let sample = logits[cursor * sample_size:(cursor + 1) * sample_size]
          results[group[start + cursor]] = Some(
            @paddleocr.ctc_decode(sample, time~, classes~, charset=self.charset),
          )
        }
        start = end
      }
    }
  }
  let ordered : Array[@paddleocr.CtcText] = []
  for result in results {
    match result {
      Some(text) => ordered.push(text)
      None => raise @paddleocr.OcrError::model("recognition result is missing")
    }
  }
  ordered
}

///|
fn Engine::backend(self : Engine) -> Backend {
  {
    detect: (image : @paddleocr.Rgba, options : @paddleocr.RecognizeOptions) => {
      self.detect(image, options~)
    },
    recognize_regions: (
      crops : Array[@paddleocr.Rgba],
      options : @paddleocr.RecognizeOptions,
    ) => self.recognize_regions(crops, options~),
  }
}

///|
/// Detect lines, warp each quadrilateral upright, and join a line without
/// inserting spaces.
///
/// Omitted `options` use `RecognizeOptions::standard`. Spans below
/// `rec_thresh` are dropped. `det_score` is the detection score and
/// `rec_confidence` is the CTC confidence.
pub fn Engine::recognize(
  self : Engine,
  image : @paddleocr.Rgba,
  options? : @paddleocr.RecognizeOptions,
) -> @paddleocr.Page raise @paddleocr.OcrError {
  recognize_with(self.backend(), image, options?)
}

///|
/// Group and recognize quads that are already in source-image coordinates.
///
/// Use this after `detect` when boxes need to be edited before recognition.
pub fn Engine::recognize_quads(
  self : Engine,
  image : @paddleocr.Rgba,
  quads : Array[@paddleocr.DetQuad],
  options? : @paddleocr.RecognizeOptions,
) -> @paddleocr.Page raise @paddleocr.OcrError {
  recognize_quads_with(self.backend(), image, quads, options?)
}

///|
/// Decode PNG, baseline JPEG, or BMP bytes and recognize the image.
pub fn Engine::recognize_bytes(
  self : Engine,
  bytes : Bytes,
  options? : @paddleocr.RecognizeOptions,
) -> @paddleocr.Page raise @paddleocr.OcrError {
  let image = @paddleocr.decode_raster(bytes)
  self.recognize(image, options?)
}

///|
/// Read an image file and recognize it. The engine stays open.
pub fn Engine::recognize_file(
  self : Engine,
  path : String,
  options? : @paddleocr.RecognizeOptions,
) -> @paddleocr.Page raise @paddleocr.OcrError {
  let bytes = @fs.read_file_to_bytes(path) catch {
    @fs.IOError(message) => raise @paddleocr.OcrError::io(message)
  }
  self.recognize_bytes(bytes, options?)
}

///|
/// Run `f` with this engine and close it when `f` returns or raises.
pub fn[T] Engine::with_scope(
  self : Engine,
  f : (Engine) -> T raise @paddleocr.OcrError,
) -> T raise @paddleocr.OcrError {
  errdefer self.close()
  let value = f(self)
  self.close()
  value
}

///|
/// Load an engine, run `f`, and close the engine on both success and failure.
///
/// This is the recommended shape for library callers:
/// `with_engine(det~, rec~, dict~, engine => { ... })`.
pub fn[T] with_engine(
  det~ : String,
  rec~ : String,
  dict~ : String,
  library? : String,
  options? : EngineOptions,
  f : (Engine) -> T raise @paddleocr.OcrError,
) -> T raise @paddleocr.OcrError {
  let engine = Engine::load(det~, rec~, dict~, library?, options?)
  engine.with_scope(f)
}

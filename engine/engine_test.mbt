///|
test "missing runtime library fails before the models are read" {
  let charset = @paddleocr.Charset::from_text("a\n")
  try
    @engine.Engine::open(
      library="/no/such/libonnxruntime.so",
      det_model="missing-det.onnx",
      rec_model="missing-rec.onnx",
      charset~,
    )
  catch {
    @paddleocr.OcrError::Runtime(_) => ()
    _ => fail("unexpected error")
  } noraise {
    _ => fail("expected to fail")
  }
}

///|
test "load reads the dictionary before opening the runtime" {
  try
    @engine.Engine::load(
      det="missing-det.onnx",
      rec="missing-rec.onnx",
      dict="no-such-dictionary.txt",
      library="/no/such/libonnxruntime.so",
    )
  catch {
    @paddleocr.OcrError::Io(_) => ()
    _ => fail("unexpected error")
  } noraise {
    _ => fail("expected to fail")
  }
}

///|
test "invalid engine options fail before the runtime is loaded" {
  try
    @engine.Engine::open(
      library="/no/such/libonnxruntime.so",
      det_model="missing-det.onnx",
      rec_model="missing-rec.onnx",
      charset=@paddleocr.Charset::from_text("a\n"),
      options=@engine.EngineOptions::standard().with_intra_op_threads(-1),
    )
  catch {
    @paddleocr.OcrError::Config(_) => ()
    _ => fail("unexpected error")
  } noraise {
    _ => fail("expected to fail")
  }
}

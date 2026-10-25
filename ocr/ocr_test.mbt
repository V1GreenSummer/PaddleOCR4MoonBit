///|
test "facade re-exports engine options and result types" {
  let engine_options = @ocr.EngineOptions::standard()
    .with_inter_op_threads(2)
    .with_rec_batch_size(4)
  inspect(engine_options.inter_op_threads, content="2")
  inspect(engine_options.rec_batch_size, content="4")
  let options = @ocr.RecognizeOptions::standard().with_min_size(5)
  inspect(options.min_size, content="5")
  let page : @ocr.Page = @ocr.Page::from_lines([])
  inspect(page.text(), content="")
  let error = @ocr.OcrError::config("missing")
  inspect(error.to_string(), content="config: missing")
}

///|
test "facade re-exports error and raster variants" {
  let error : @ocr.OcrError = @ocr.OcrError::io("missing")
  match error {
    @ocr.OcrError::Io(message) => inspect(message, content="missing")
    _ => fail("unexpected error")
  }
  let kind = @ocr.sniff_raster([
    b'\x89', b'\x50', b'\x4e', b'\x47', b'\x0d', b'\x0a', b'\x1a', b'\x0a',
  ])
  match kind {
    @ocr.RasterKind::Png => ()
    _ => fail("unexpected raster kind")
  }
}

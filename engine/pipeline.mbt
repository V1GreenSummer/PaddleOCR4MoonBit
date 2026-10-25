///|
/// Detection step for a backend.
pub type DetectFn = (@paddleocr.Rgba, @paddleocr.RecognizeOptions) -> Array[
  @paddleocr.DetQuad,
] raise @paddleocr.OcrError

///|
/// Recognition step for a backend. The output must have one entry per crop.
pub type RecognizeFn = (Array[@paddleocr.Rgba], @paddleocr.RecognizeOptions) -> Array[
  @paddleocr.CtcText,
] raise @paddleocr.OcrError

///|
/// The two inference steps the page pipeline needs. `Engine::backend` builds
/// one from ONNX Runtime sessions; tests can build one from plain functions.
pub(all) struct Backend {
  detect : DetectFn
  recognize_regions : RecognizeFn
}

///|
fn resolve_recognize_options(
  options : @paddleocr.RecognizeOptions?,
) -> @paddleocr.RecognizeOptions {
  match options {
    Some(options) => options
    None => @paddleocr.RecognizeOptions::standard()
  }
}

///|
/// Detect once, then group, warp, and recognize the page through `backend`.
pub fn recognize_with(
  backend : Backend,
  image : @paddleocr.Rgba,
  options? : @paddleocr.RecognizeOptions,
) -> @paddleocr.Page raise @paddleocr.OcrError {
  let options = resolve_recognize_options(options)
  let quads = (backend.detect)(image, options)
  recognize_quads_with(backend, image, quads, options~)
}

///|
/// Recognize quads that are already in source-image coordinates.
///
/// Quads are grouped into reading lines, warped in that order, and sent to the
/// backend in one call so backends can batch them. Spans below
/// `options.rec_thresh` or with empty text are omitted.
pub fn recognize_quads_with(
  backend : Backend,
  image : @paddleocr.Rgba,
  quads : Array[@paddleocr.DetQuad],
  options? : @paddleocr.RecognizeOptions,
) -> @paddleocr.Page raise @paddleocr.OcrError {
  let options = resolve_recognize_options(options)
  let placed : Array[@paddleocr.PlacedText] = []
  for quad in quads {
    match quad.place(image.width, image.height) {
      Some(item) => placed.push(item)
      None => ()
    }
  }
  let rows = @paddleocr.group_placed(placed)
  let crops : Array[@paddleocr.Rgba] = []
  for row in rows {
    for item in row {
      crops.push(image.warp(item.quad))
    }
  }
  let decoded = (backend.recognize_regions)(crops, options)
  if decoded.length() != crops.length() {
    raise @paddleocr.OcrError::model(
      "backend returned \{decoded.length()} texts for \{crops.length()} crops",
    )
  }
  let lines : Array[@paddleocr.TextLine] = []
  let mut index = 0
  for row in rows {
    let spans : Array[@paddleocr.TextSpan] = []
    for item in row {
      let result = decoded[index]
      index = index + 1
      if result.text.length() == 0 || result.confidence < options.rec_thresh {
        continue
      }
      spans.push({
        quad: item.quad,
        bounds: item.bounds,
        text: result.text,
        det_score: item.bounds.score,
        rec_confidence: result.confidence,
      })
    }
    if spans.length() > 0 {
      lines.push(@paddleocr.TextLine::from_spans(spans))
    }
  }
  @paddleocr.Page::from_lines(lines)
}

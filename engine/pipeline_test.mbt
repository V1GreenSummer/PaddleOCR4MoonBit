///|
fn pipeline_image() -> @paddleocr.Rgba raise @paddleocr.OcrError {
  @paddleocr.Rgba::from_rgba(4, 4, Bytes::make(4 * 4 * 4, b'\x80'))
}

///|
fn pipeline_quad() -> @paddleocr.DetQuad {
  {
    top_left: { x: 0.0, y: 0.0, },
    top_right: { x: 4.0, y: 0.0, },
    bottom_right: { x: 4.0, y: 4.0, },
    bottom_left: { x: 0.0, y: 4.0, },
    score: 0.8,
  }
}

///|
test "pipeline calls detection and recognition backends in order" {
  let calls : Array[String] = []
  let backend : @engine.Backend = {
    detect: (_image, _options) => {
      calls.push("detect")
      [pipeline_quad()]
    },
    recognize_regions: (crops, _options) => {
      calls.push("recognize")
      let decoded : Array[@paddleocr.CtcText] = []
      for _crop in crops {
        decoded.push({ text: "hi", confidence: 0.9, })
      }
      decoded
    },
  }
  let page = @engine.recognize_with(backend, pipeline_image())
  inspect(page.text(), content="hi")
  inspect(calls.length(), content="2")
  inspect(calls[0], content="detect")
  inspect(calls[1], content="recognize")
  let spans = page.spans()
  inspect(spans.length(), content="1")
  assert_true(spans[0].det_score == 0.8)
  assert_true(spans[0].rec_confidence == 0.9)
  inspect(spans[0].quad.top_left.x, content="0")
}

///|
test "pipeline drops low-confidence spans" {
  let backend : @engine.Backend = {
    detect: (_image, _options) => [pipeline_quad()],
    recognize_regions: (crops, _options) => {
      let decoded : Array[@paddleocr.CtcText] = []
      for _crop in crops {
        decoded.push({ text: "low", confidence: 0.1, })
      }
      decoded
    },
  }
  let page = @engine.recognize_with(backend, pipeline_image())
  inspect(page.lines.length(), content="0")
}

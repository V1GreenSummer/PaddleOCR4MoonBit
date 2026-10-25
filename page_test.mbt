///|
fn sample_quad() -> @paddleocr.DetQuad {
  {
    top_left: { x: 1.0, y: 2.0, },
    top_right: { x: 4.0, y: 2.0, },
    bottom_right: { x: 4.0, y: 6.0, },
    bottom_left: { x: 1.0, y: 6.0, },
    score: 0.5,
  }
}

///|
fn sample_span(text : String, x : Int32) -> @paddleocr.TextSpan {
  {
    quad: sample_quad(),
    bounds: { x, y: 2, width: 3, height: 4, score: 0.5, },
    text,
    det_score: 0.5,
    rec_confidence: 0.9,
  }
}

///|
test "a line text is computed from its spans" {
  let line = @paddleocr.TextLine::from_spans([
    sample_span("你", 1),
    sample_span("好", 4),
  ])
  inspect(line.text(), content="你好")
}

///|
test "page flattens spans in reading order" {
  let page = @paddleocr.Page::from_lines([
    @paddleocr.TextLine::from_spans([sample_span("a", 1), sample_span("b", 4)]),
    @paddleocr.TextLine::from_spans([sample_span("c", 1)]),
  ])
  inspect(page.text(), content="ab\nc")
  let spans = page.spans()
  assert_eq(spans.length(), 3)
  inspect(spans[2].text, content="c")
  inspect(spans[0].quad.top_left.x, content="1")
}

///|
test "page render uses the split detection and recognition scores" {
  let page = @paddleocr.Page::from_lines([
    @paddleocr.TextLine::from_spans([sample_span("你好", 1)]),
  ])
  inspect(page.render(boxes=true), content="1,2,3,4\t0.5\t0.9\t你好")
}

///|
test "page JSON includes the computed line text" {
  let page = @paddleocr.Page::from_lines([
    @paddleocr.TextLine::from_spans([sample_span("你好", 1)]),
  ])
  let text = page.to_json_string()
  assert_true(text.contains("\"text\":\"你好\""))
  assert_true(text.contains("\"rec_confidence\":0.9"))
  assert_true(text.contains("\"quad\""))
}

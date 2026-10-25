///|
test "charset drops one trailing newline and keeps a crlf line" {
  let charset = @paddleocr.Charset::from_text("你\r\n好\n")
  debug_inspect(charset.glyph(1), content="Some(\"你\")")
  debug_inspect(charset.glyph(2), content="Some(\"好\")")
  debug_inspect(charset.glyph(3), content="None")
}

///|
test "ppocr appends one space class and does not append a second" {
  let charset = @paddleocr.Charset::ppocr("你\n好\n")
  debug_inspect(charset.glyph(3), content="Some(\" \")")
  debug_inspect(charset.glyph(4), content="None")
  let again = @paddleocr.Charset::ppocr("你\n好\n \n")
  debug_inspect(again.glyph(3), content="Some(\" \")")
  debug_inspect(again.glyph(4), content="None")
  let logits : Array[Float] = [
    0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 1.0, 0.0,
  ]
  inspect(
    @paddleocr.ctc_greedy(logits, time=3, classes=4, charset~),
    content="你 好",
  )
  let decoded = @paddleocr.ctc_decode(logits, time=3, classes=4, charset~)
  assert_true(decoded.confidence > 0.9)
}

///|
test "ctc rejects a short logit buffer" {
  let charset = @paddleocr.Charset::from_text("a\n")
  try @paddleocr.ctc_greedy([1.0], time=2, classes=2, charset~) catch {
    @paddleocr.OcrError::Model(_) => ()
    _ => fail("unexpected error")
  } noraise {
    _ => fail("expected to fail")
  }
}

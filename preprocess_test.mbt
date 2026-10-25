///|
fn solid(
  width : Int32,
  height : Int32,
  value : Byte,
) -> @paddleocr.Rgba raise @paddleocr.OcrError {
  @paddleocr.Rgba::from_rgba(
    width,
    height,
    Bytes::make(width * height * 4, value),
  )
}

///|
fn near(actual : Float, expected : Float) -> Bool {
  actual.is_close(expected, absolute_tolerance=0.0001)
}

///|
test "long side is limited and aligned to 32" {
  let (width, height) = @paddleocr.limit_side_size(1000, 500, limit=960)
  inspect(width, content="960")
  inspect(height, content="480")
}

///|
test "detection tensor uses imagenet normalization" {
  let prepared = @paddleocr.prepare_det(
    solid(40, 40, b'\xff'),
    limit_side_len=960,
  )
  inspect(prepared.tensor.width, content="32")
  inspect(prepared.tensor.height, content="32")
  inspect(prepared.ratio_w, content="0.8")
  inspect(prepared.ratio_h, content="0.8")
  let expected = Float::from_double((1.0 - 0.485) / 0.229)
  assert_true(near(prepared.tensor.values[0], expected))
  assert_eq(prepared.tensor.values.length(), 3 * 32 * 32)
}

///|
test "recognition tensor keeps aspect and pads a fixed width" {
  let dynamic = @paddleocr.prepare_rec(solid(10, 20, b'\xff'))
  inspect(dynamic.height, content="48")
  inspect(dynamic.width, content="24")
  assert_true(near(dynamic.values[0], 1.0))
  let fixed = @paddleocr.prepare_rec(solid(10, 20, b'\xff'), fixed_width=32)
  inspect(fixed.width, content="32")
  assert_true(near(fixed.values[0], 1.0))
  assert_true(near(fixed.values[24], 0.0))
}

///|
fn sample_rgba() -> @paddleocr.Rgba raise @paddleocr.OcrError {
  @paddleocr.Rgba::from_rgba(2, 2, [
    b'\xff', b'\x00', b'\x00', b'\xff', b'\x00', b'\xff', b'\x00', b'\xff', b'\x00',
    b'\x00', b'\xff', b'\xff', b'\xff', b'\xff', b'\xff', b'\xff',
  ])
}

///|
test "sniff rejects an unknown payload" {
  try @paddleocr.sniff_raster(b"hello") catch {
    @paddleocr.OcrError::Image(_) => ()
    _ => fail("unexpected error")
  } noraise {
    _ => fail("expected to fail")
  }
}

///|
test "crop clamps to the image" {
  let image = sample_rgba()
  let crop = image.crop(-1, 0, 2, 1)
  inspect(crop.width, content="1")
  inspect(crop.height, content="1")
  assert_eq(crop.pixels[0], b'\xff')
}

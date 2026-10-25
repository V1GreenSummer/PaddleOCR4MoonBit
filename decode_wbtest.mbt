///|
fn sample_rgba() -> Rgba raise OcrError {
  Rgba::from_rgba(2, 2, [
    b'\xff', b'\x00', b'\x00', b'\xff', b'\x00', b'\xff', b'\x00', b'\xff', b'\x00',
    b'\x00', b'\xff', b'\xff', b'\xff', b'\xff', b'\xff', b'\xff',
  ])
}

///|
fn packed(image : Rgba) -> @codec.ImageData {
  { width: image.width, height: image.height, data: image.pixels, }
}

///|
test "png and bmp roundtrip keep rgba pixels" {
  let image = sample_rgba()
  let png = decode_raster(@codec.encode_png(packed(image)))
  let bmp = decode_raster(@codec.encode_bmp(packed(image)))
  assert_eq(png, image)
  assert_eq(bmp, image)
}

///|
test "jpeg decode keeps the raster size" {
  let image = sample_rgba()
  let jpeg = @codec.encode_jpeg(packed(image), quality=90)
  debug_inspect(sniff_raster(jpeg), content="Jpeg")
  let decoded = decode_raster(jpeg)
  inspect(decoded.width, content="2")
  inspect(decoded.height, content="2")
}

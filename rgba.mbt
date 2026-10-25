///|
/// 8-bit RGBA image, row-major, top-left origin. Alpha is kept and ignored by
/// the recognition normalizer.
pub(all) struct Rgba {
  width : Int32
  height : Int32
  pixels : Bytes
} derive(Eq, Debug)

///|
pub extend Rgba with Eq::{not_equal, equal}

///|
pub extend Rgba with @debug.Debug::{to_repr}

///|
/// Build an image from packed RGBA bytes.
///
/// # Example
/// ```mbt check
/// test {
///   let image = @paddleocr.Rgba::from_rgba(1, 1, [
///     b'\x01', b'\x02', b'\x03', b'\xff',
///   ])
///   inspect(image.width, content="1")
///   inspect(image.height, content="1")
/// }
/// ```
pub fn Rgba::from_rgba(
  width : Int32,
  height : Int32,
  pixels : Bytes,
) -> Rgba raise OcrError {
  if width <= 0 || height <= 0 {
    raise OcrError::Image("image size must be positive")
  }
  if width > 1000000 || height > 1000000 {
    raise OcrError::Image("image side is too large")
  }
  if pixels.length() != width * height * 4 {
    raise OcrError::Image("rgba byte length does not match width*height*4")
  }
  { width, height, pixels, }
}

///|
/// Crop a rectangle and clamp it to the image. The result is still RGBA.
pub fn Rgba::crop(
  self : Rgba,
  x : Int32,
  y : Int32,
  width : Int32,
  height : Int32,
) -> Rgba raise OcrError {
  if width <= 0 || height <= 0 {
    raise OcrError::Image("crop is empty")
  }
  let x0 = if x < 0 { 0 } else { x }
  let y0 = if y < 0 { 0 } else { y }
  let x1 = if x + width > self.width { self.width } else { x + width }
  let y1 = if y + height > self.height { self.height } else { y + height }
  if x1 <= x0 || y1 <= y0 {
    raise OcrError::Image("crop is empty")
  }
  let crop_width = x1 - x0
  let crop_height = y1 - y0
  let pixels = Bytes::makei(crop_width * crop_height * 4, fn(index) {
    let pixel = index / 4
    let channel = index % 4
    let column = pixel % crop_width
    let row = pixel / crop_width
    let source = ((y0 + row) * self.width + (x0 + column)) * 4 + channel
    self.pixels[source]
  })
  { width: crop_width, height: crop_height, pixels, }
}

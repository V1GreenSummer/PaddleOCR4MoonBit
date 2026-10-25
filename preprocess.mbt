///|
/// NCHW float tensor without the leading batch axis. `values` is channel-major
/// RGB, length `3 * height * width`.
pub(all) struct ChwTensor {
  height : Int32
  width : Int32
  values : Array[Float]
} derive(Eq, Debug)

///|
pub extend ChwTensor with Eq::{not_equal, equal}

///|
pub extend ChwTensor with @debug.Debug::{to_repr}

///|
/// Detection input plus the scale from the resized map back to the source.
pub(all) struct DetTensor {
  tensor : ChwTensor
  ratio_w : Double
  ratio_h : Double
} derive(Debug, Eq)

///|
pub extend DetTensor with Eq::{not_equal, equal}

///|
pub extend DetTensor with @debug.Debug::{to_repr}

///|
priv struct Norm {
  r : Double
  g : Double
  b : Double
  sr : Double
  sg : Double
  sb : Double
}

///|
let det_norm : Norm = {
  r: 0.485,
  g: 0.456,
  b: 0.406,
  sr: 0.229,
  sg: 0.224,
  sb: 0.225,
}

///|
let rec_norm : Norm = { r: 0.5, g: 0.5, b: 0.5, sr: 0.5, sg: 0.5, sb: 0.5, }

///|
fn trunc_int(value : Double) -> Int32 {
  value.trunc().to_int()
}

///|
fn align32(size : Int32) -> Int32 {
  let aligned = (size.to_double() / 32.0).round().to_int() * 32
  if aligned < 32 {
    32
  } else {
    aligned
  }
}

///|
/// Resize size used by PP-OCR detection: limit the long side, then round both
/// sides to a multiple of 32.
///
/// # Example
/// ```mbt check
/// test {
///   let (width, height) = @paddleocr.limit_side_size(10, 20, limit=960)
///   inspect(width, content="32")
///   inspect(height, content="32")
/// }
/// ```
pub fn limit_side_size(
  width : Int32,
  height : Int32,
  limit~ : Int32,
) -> (Int32, Int32) raise OcrError {
  if width <= 0 || height <= 0 {
    raise OcrError::Image("image size must be positive")
  }
  if limit < 32 {
    raise OcrError::Image("limit_side_len must be at least 32")
  }
  let longer = if width > height { width } else { height }
  let ratio = if longer > limit {
    limit.to_double() / longer.to_double()
  } else {
    1.0
  }
  let resized_w = trunc_int(width.to_double() * ratio)
  let resized_h = trunc_int(height.to_double() * ratio)
  let safe_w = if resized_w < 1 { 1 } else { resized_w }
  let safe_h = if resized_h < 1 { 1 } else { resized_h }
  (align32(safe_w), align32(safe_h))
}

///|
fn resize_rgba(
  image : Rgba,
  width : Int32,
  height : Int32,
) -> Rgba raise OcrError {
  let resized = @codec.resize(
    { width: image.width, height: image.height, data: image.pixels, },
    width,
    height,
    @codec.Bilinear,
  ) catch {
    error => raise OcrError::Image(error.to_string())
  }
  Rgba::from_rgba(resized.width, resized.height, resized.data)
}

///|
fn make_lut(mean : Double, std : Double) -> FixedArray[Float] {
  let lut : FixedArray[Float] = FixedArray::make(256, 0.0)
  for index in 0..<256 {
    lut[index] = Float::from_double((index.to_double() / 255.0 - mean) / std)
  }
  lut
}

///|
fn normalize_rgb(image : Rgba, norm : Norm) -> ChwTensor raise OcrError {
  if norm.sr == 0.0 || norm.sg == 0.0 || norm.sb == 0.0 {
    raise OcrError::Image("normalization std is zero")
  }
  // `Norm` stores the ImageNet RGB means; PP-OCR applies them in BGR order.
  let lut_blue = make_lut(norm.r, norm.sr)
  let lut_green = make_lut(norm.g, norm.sg)
  let lut_red = make_lut(norm.b, norm.sb)
  let plane = image.width * image.height
  let values : Array[Float] = Array::make(plane * 3, 0.0)
  for y in 0..<image.height {
    for x in 0..<image.width {
      let source = (y * image.width + x) * 4
      let offset = y * image.width + x
      // PP-OCR feeds OpenCV BGR into NormalizeImage, so channel 0 is blue.
      values[offset] = lut_blue[image.pixels[source + 2].to_int()]
      values[plane + offset] = lut_green[image.pixels[source + 1].to_int()]
      values[plane * 2 + offset] = lut_red[image.pixels[source].to_int()]
    }
  }
  { height: image.height, width: image.width, values, }
}

///|
/// Build the PP-OCR detection tensor. ImageNet mean and std, NCHW BGR.
pub fn prepare_det(
  image : Rgba,
  limit_side_len~ : Int32 = 960,
) -> DetTensor raise OcrError {
  let (width, height) = limit_side_size(
    image.width,
    image.height,
    limit=limit_side_len,
  )
  let resized = resize_rgba(image, width, height)
  {
    tensor: normalize_rgb(resized, det_norm),
    ratio_w: width.to_double() / image.width.to_double(),
    ratio_h: height.to_double() / image.height.to_double(),
  }
}

///|
fn blit_pad(source : ChwTensor, width : Int32) -> ChwTensor {
  if source.width == width {
    return source
  }
  let plane = width * source.height
  let values : Array[Float] = Array::make(plane * 3, 0.0)
  for channel in 0..<3 {
    for y in 0..<source.height {
      for x in 0..<source.width {
        values[channel * plane + y * width + x] = source.values[channel *
          source.width *
          source.height +
          y * source.width +
          x]
      }
    }
  }
  { height: source.height, width, values, }
}

///|
/// Build the PP-OCR recognition tensor. Height defaults to 48. A missing
/// `fixed_width` keeps the aspect width, capped by `max_width`. A fixed width
/// pads the normalized tensor on the right with zeros.
pub fn prepare_rec(
  image : Rgba,
  height~ : Int32 = 48,
  max_width~ : Int32 = 320,
  fixed_width? : Int32,
) -> ChwTensor raise OcrError {
  if image.width <= 0 || image.height <= 0 {
    raise OcrError::Image("image size must be positive")
  }
  if height < 1 || max_width < 1 {
    raise OcrError::Image("recognition size must be positive")
  }
  let cap = match fixed_width {
    Some(width) =>
      if width < 1 {
        raise OcrError::Image("recognition width must be positive")
      } else {
        width
      }
    None => max_width
  }
  let aspect = image.width.to_double() / image.height.to_double()
  let mut resized_w = (height.to_double() * aspect).ceil().to_int()
  if resized_w > cap {
    resized_w = cap
  }
  if resized_w < 1 {
    resized_w = 1
  }
  let normalized = normalize_rgb(
    resize_rgba(image, resized_w, height),
    rec_norm,
  )
  match fixed_width {
    Some(_) => blit_pad(normalized, cap)
    None => normalized
  }
}

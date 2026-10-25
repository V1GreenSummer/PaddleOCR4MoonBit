///|
/// Raster container recognized by the decoder.
pub enum RasterKind {
  Png
  Jpeg
  Bmp
} derive(Eq, Debug)

///|
pub extend RasterKind with Eq::{not_equal, equal}

///|
pub extend RasterKind with @debug.Debug::{to_repr}

///|
/// Identify PNG, JPEG, or BMP bytes.
///
/// # Example
/// ```mbt check
/// test {
///   debug_inspect(
///     @paddleocr.sniff_raster([b'\xff', b'\xd8', b'\xff']),
///     content="Jpeg",
///   )
/// }
/// ```
pub fn sniff_raster(bytes : Bytes) -> RasterKind raise OcrError {
  if bytes.length() >= 8 &&
    bytes[0] == b'\x89' &&
    bytes[1] == b'\x50' &&
    bytes[2] == b'\x4e' &&
    bytes[3] == b'\x47' &&
    bytes[4] == b'\x0d' &&
    bytes[5] == b'\x0a' &&
    bytes[6] == b'\x1a' &&
    bytes[7] == b'\x0a' {
    Png
  } else if bytes.length() >= 3 &&
    bytes[0] == b'\xff' &&
    bytes[1] == b'\xd8' &&
    bytes[2] == b'\xff' {
    Jpeg
  } else if bytes.length() >= 2 && bytes[0] == b'\x42' && bytes[1] == b'\x4d' {
    Bmp
  } else {
    raise OcrError::Image("unsupported image: expected PNG, JPEG, or BMP")
  }
}

///|
/// Decode a PNG, baseline JPEG, or BMP image into RGBA.
pub fn decode_raster(bytes : Bytes) -> Rgba raise OcrError {
  let decoded = match sniff_raster(bytes) {
    Png =>
      @codec.decode_png(bytes) catch {
        error => raise OcrError::Image(error.to_string())
      }
    Jpeg =>
      @codec.decode_jpeg(bytes) catch {
        error => raise OcrError::Image(error.to_string())
      }
    Bmp =>
      @codec.decode_bmp(bytes) catch {
        error => raise OcrError::Image(error.to_string())
      }
  }
  Rgba::from_rgba(decoded.width, decoded.height, decoded.data)
}

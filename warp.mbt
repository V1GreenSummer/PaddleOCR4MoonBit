///|
fn solve8(matrix : Array[Double], rhs : Array[Double]) -> Array[Double]? {
  for column in 0..<8 {
    let mut pivot = column
    let mut best = matrix[column * 8 + column]
    if best < 0.0 {
      best = -best
    }
    for row in (column + 1)..<8 {
      let mut value = matrix[row * 8 + column]
      if value < 0.0 {
        value = -value
      }
      if value > best {
        best = value
        pivot = row
      }
    }
    if best < 0.0000000001 {
      return None
    }
    if pivot != column {
      for index in 0..<8 {
        let saved = matrix[column * 8 + index]
        matrix[column * 8 + index] = matrix[pivot * 8 + index]
        matrix[pivot * 8 + index] = saved
      }
      let saved = rhs[column]
      rhs[column] = rhs[pivot]
      rhs[pivot] = saved
    }
    let diagonal = matrix[column * 8 + column]
    for row in (column + 1)..<8 {
      let factor = matrix[row * 8 + column] / diagonal
      for index in column..<8 {
        matrix[row * 8 + index] = matrix[row * 8 + index] -
          factor * matrix[column * 8 + index]
      }
      rhs[row] = rhs[row] - factor * rhs[column]
    }
  }
  let solved = Array::make(8, 0.0)
  for step in 0..<8 {
    let row = 7 - step
    let mut value = rhs[row]
    for column in (row + 1)..<8 {
      value = value - matrix[row * 8 + column] * solved[column]
    }
    let diagonal = matrix[row * 8 + row]
    let scale = if diagonal < 0.0 { -diagonal } else { diagonal }
    if scale < 0.0000000001 {
      return None
    }
    solved[row] = value / diagonal
  }
  Some(solved)
}

///|
fn homography(
  quad : DetQuad,
  width : Double,
  height : Double,
) -> Array[Double]? {
  let source = [
    quad.top_left,
    quad.top_right,
    quad.bottom_right,
    quad.bottom_left,
  ]
  let dest_x = [0.0, width, width, 0.0]
  let dest_y = [0.0, 0.0, height, height]
  let matrix = Array::make(64, 0.0)
  let rhs = Array::make(8, 0.0)
  for index in 0..<4 {
    let x = dest_x[index]
    let y = dest_y[index]
    let sx = source[index].x
    let sy = source[index].y
    let row = index * 2
    matrix[row * 8] = x
    matrix[row * 8 + 1] = y
    matrix[row * 8 + 2] = 1.0
    matrix[row * 8 + 6] = -x * sx
    matrix[row * 8 + 7] = -y * sx
    rhs[row] = sx
    let next = row + 1
    matrix[next * 8 + 3] = x
    matrix[next * 8 + 4] = y
    matrix[next * 8 + 5] = 1.0
    matrix[next * 8 + 6] = -x * sy
    matrix[next * 8 + 7] = -y * sy
    rhs[next] = sy
  }
  solve8(matrix, rhs)
}

///|
fn clamp_index(value : Int32, limit : Int32) -> Int32 {
  if value < 0 {
    0
  } else if value >= limit {
    limit - 1
  } else {
    value
  }
}

///|
fn sample_channel(
  image : Rgba,
  x : Double,
  y : Double,
  channel : Int32,
) -> Byte {
  let column = x.floor().to_int()
  let row = y.floor().to_int()
  let raw_tx = x - column.to_double()
  let raw_ty = y - row.to_double()
  let tx = if raw_tx < 0.0 { 0.0 } else { raw_tx }
  let ty = if raw_ty < 0.0 { 0.0 } else { raw_ty }
  let x0 = clamp_index(column, image.width)
  let y0 = clamp_index(row, image.height)
  let x1 = clamp_index(column + 1, image.width)
  let y1 = clamp_index(row + 1, image.height)
  fn at(px : Int32, py : Int32) -> Double {
    image.pixels[(py * image.width + px) * 4 + channel].to_int().to_double()
  }

  let mixed = (1.0 - tx) * (1.0 - ty) * at(x0, y0) +
    tx * (1.0 - ty) * at(x1, y0) +
    (1.0 - tx) * ty * at(x0, y1) +
    tx * ty * at(x1, y1)
  let rounded = mixed.round().to_int()
  let byte = if rounded <= 0 {
    0
  } else if rounded >= 255 {
    255
  } else {
    rounded
  }
  byte.to_byte()
}

///|
fn project(coeffs : Array[Double], x : Double, y : Double) -> Point {
  let denom = coeffs[6] * x + coeffs[7] * y + 1.0
  let scale = if denom == 0.0 { 1.0 } else { denom }
  {
    x: (coeffs[0] * x + coeffs[1] * y + coeffs[2]) / scale,
    y: (coeffs[3] * x + coeffs[4] * y + coeffs[5]) / scale,
  }
}

///|
fn rotate_ccw(image : Rgba) -> Rgba {
  let width = image.height
  let height = image.width
  let pixels = Bytes::makei(width * height * 4, fn(index) {
    let pixel = index / 4
    let channel = index % 4
    let column = pixel % width
    let row = pixel / width
    let source_x = image.width - 1 - row
    let source_y = column
    image.pixels[(source_y * image.width + source_x) * 4 + channel]
  })
  { width, height, pixels, }
}

///|
/// Perspective-crop `quad` into a horizontal strip.
///
/// A strip at least 1.5 times taller than it is wide is rotated a quarter turn
/// counter-clockwise, which is how PP-OCR turns vertical text sideways.
pub fn Rgba::warp(self : Rgba, quad : DetQuad) -> Rgba raise OcrError {
  let top = point_dist(quad.top_left, quad.top_right)
  let bottom = point_dist(quad.bottom_left, quad.bottom_right)
  let left = point_dist(quad.top_left, quad.bottom_left)
  let right = point_dist(quad.top_right, quad.bottom_right)
  let mut width = (if top > bottom { top } else { bottom }).trunc().to_int()
  let mut height = (if left > right { left } else { right }).trunc().to_int()
  if width < 1 {
    width = 1
  }
  if height < 1 {
    height = 1
  }
  if width > 8192 || height > 8192 {
    raise OcrError::Image("warped text is too large")
  }
  let coeffs = match homography(quad, width.to_double(), height.to_double()) {
    Some(coeffs) => coeffs
    None => raise OcrError::Image("text quad is degenerate")
  }
  let pixels = Bytes::makei(width * height * 4, fn(index) {
    let pixel = index / 4
    let channel = index % 4
    let column = pixel % width
    let row = pixel / width
    let source = project(coeffs, column.to_double(), row.to_double())
    sample_channel(self, source.x, source.y, channel)
  })
  let warped : Rgba = { width, height, pixels, }
  if height.to_double() / width.to_double() >= 1.5 {
    rotate_ccw(warped)
  } else {
    warped
  }
}

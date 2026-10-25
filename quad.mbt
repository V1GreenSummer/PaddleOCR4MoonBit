///|
/// A point in image coordinates. Y grows downward.
pub(all) struct Point {
  x : Double
  y : Double
} derive(Debug, Eq, ToJson)

///|
pub extend Point with Eq::{not_equal, equal}

///|
pub extend Point with ToJson::{to_json}

///|
pub extend Point with @debug.Debug::{to_repr}

///|
/// Text region as an ordered quadrilateral: top-left, top-right, bottom-right,
/// bottom-left. `score` is the mean detection probability of the component.
pub(all) struct DetQuad {
  top_left : Point
  top_right : Point
  bottom_right : Point
  bottom_left : Point
  score : Double
} derive(Debug, Eq, ToJson)

///|
pub extend DetQuad with Eq::{not_equal, equal}

///|
pub extend DetQuad with ToJson::{to_json}

///|
pub extend DetQuad with @debug.Debug::{to_repr}

///|
/// A quadrilateral placed on the source image, plus its pixel bounds.
pub(all) struct PlacedText {
  quad : DetQuad
  bounds : GlyphBox
} derive(Debug, Eq, ToJson)

///|
pub extend PlacedText with Eq::{not_equal, equal}

///|
pub extend PlacedText with ToJson::{to_json}

///|
pub extend PlacedText with @debug.Debug::{to_repr}

///|
fn point_dist(left : Point, right : Point) -> Double {
  let dx = left.x - right.x
  let dy = left.y - right.y
  (dx * dx + dy * dy).sqrt()
}

///|
fn point_cross(origin : Point, left : Point, right : Point) -> Double {
  (left.x - origin.x) * (right.y - origin.y) -
  (left.y - origin.y) * (right.x - origin.x)
}

///|
/// Order four corners as top-left, top-right, bottom-right, bottom-left.
pub fn order_corners(
  corners : Array[Point],
  score~ : Double = 0.0,
) -> DetQuad raise OcrError {
  if corners.length() != 4 {
    raise OcrError::Model("a text quad needs four corners")
  }
  let mut center_x = 0.0
  let mut center_y = 0.0
  for corner in corners {
    center_x = center_x + corner.x
    center_y = center_y + corner.y
  }
  center_x = center_x / 4.0
  center_y = center_y / 4.0
  let ordered : Array[Point] = []
  for corner in corners {
    ordered.push(corner)
  }
  ordered.sort_by((left, right) => {
    let left_angle = @math.atan2(left.y - center_y, left.x - center_x)
    let right_angle = @math.atan2(right.y - center_y, right.x - center_x)
    if left_angle < right_angle {
      -1
    } else if left_angle > right_angle {
      1
    } else {
      0
    }
  })
  {
    top_left: ordered[0],
    top_right: ordered[1],
    bottom_right: ordered[2],
    bottom_left: ordered[3],
    score,
  }
}

///|
fn push_hull(hull : Array[Point], count : Int32, point : Point) -> Int32 {
  let mut count = count
  while count >= 2 &&
        point_cross(hull[count - 2], hull[count - 1], point) <= 0.0 {
    count = count - 1
  }
  if count < hull.length() {
    hull[count] = point
  } else {
    hull.push(point)
  }
  count + 1
}

///|
fn convex_hull(points : Array[Point]) -> Array[Point] {
  let sorted : Array[Point] = []
  for point in points {
    sorted.push(point)
  }
  sorted.sort_by((left, right) => {
    if left.x < right.x {
      -1
    } else if left.x > right.x {
      1
    } else if left.y < right.y {
      -1
    } else if left.y > right.y {
      1
    } else {
      0
    }
  })
  let unique : Array[Point] = []
  for point in sorted {
    let count = unique.length()
    if count == 0 ||
      unique[count - 1].x != point.x ||
      unique[count - 1].y != point.y {
      unique.push(point)
    }
  }
  if unique.length() <= 1 {
    return unique
  }
  let hull : Array[Point] = []
  let mut count = 0
  for point in unique {
    count = push_hull(hull, count, point)
  }
  let lower = count
  let mut index = unique.length() - 2
  while index >= 0 {
    count = push_hull(hull, count, unique[index])
    index = index - 1
  }
  let result : Array[Point] = []
  let end = if count > lower { count - 1 } else { count }
  for cursor in 0..<end {
    result.push(hull[cursor])
  }
  result
}

///|
fn corners_from_axes(
  ux : Double,
  uy : Double,
  vx : Double,
  vy : Double,
  min_u : Double,
  max_u : Double,
  min_v : Double,
  max_v : Double,
) -> Array[Point] {
  fn at(u : Double, v : Double) -> Point {
    { x: u * ux + v * vx, y: u * uy + v * vy, }
  }

  [at(min_u, min_v), at(max_u, min_v), at(max_u, max_v), at(min_u, max_v)]
}

///|
/// Smallest-area rectangle around `points`, ordered clockwise from the top-left
/// in image coordinates.
///
/// # Example
/// ```mbt check
/// test {
///   let quad = @paddleocr.min_area_rect([
///     { x: 0.0, y: 0.0, },
///     { x: 2.0, y: 0.0, },
///     { x: 2.0, y: 1.0, },
///     { x: 0.0, y: 1.0, },
///   ])
///   inspect(quad.top_left.x, content="0")
///   inspect(quad.top_right.x, content="2")
///   inspect(quad.bottom_left.y, content="1")
/// }
/// ```
pub fn min_area_rect(points : Array[Point]) -> DetQuad raise OcrError {
  if points.length() == 0 {
    raise OcrError::Model("min-area rect needs at least one point")
  }
  let hull = convex_hull(points)
  if hull.length() == 1 {
    let point = hull[0]
    return order_corners([
      { x: point.x, y: point.y, },
      { x: point.x + 1.0, y: point.y, },
      { x: point.x + 1.0, y: point.y + 1.0, },
      { x: point.x, y: point.y + 1.0, },
    ])
  }
  let mut best = 1.0e300
  let mut corners = corners_from_axes(1.0, 0.0, 0.0, 1.0, 0.0, 1.0, 0.0, 1.0)
  let count = hull.length()
  for index in 0..<count {
    let start = hull[index]
    let end = hull[if index + 1 == count { 0 } else { index + 1 }]
    let dx = end.x - start.x
    let dy = end.y - start.y
    let length = (dx * dx + dy * dy).sqrt()
    if length == 0.0 {
      continue
    }
    let ux = dx / length
    let uy = dy / length
    let vx = -uy
    let vy = ux
    let mut min_u = hull[0].x * ux + hull[0].y * uy
    let mut max_u = min_u
    let mut min_v = hull[0].x * vx + hull[0].y * vy
    let mut max_v = min_v
    for point in hull {
      let along = point.x * ux + point.y * uy
      let across = point.x * vx + point.y * vy
      if along < min_u {
        min_u = along
      }
      if along > max_u {
        max_u = along
      }
      if across < min_v {
        min_v = across
      }
      if across > max_v {
        max_v = across
      }
    }
    let area = (max_u - min_u) * (max_v - min_v)
    if area < best {
      best = area
      corners = corners_from_axes(ux, uy, vx, vy, min_u, max_u, min_v, max_v)
    }
  }
  order_corners(corners)
}

///|
fn quad_perimeter(quad : DetQuad) -> Double {
  point_dist(quad.top_left, quad.top_right) +
  point_dist(quad.top_right, quad.bottom_right) +
  point_dist(quad.bottom_right, quad.bottom_left) +
  point_dist(quad.bottom_left, quad.top_left)
}

///|
fn quad_area(quad : DetQuad) -> Double {
  let sum = quad.top_left.x * quad.top_right.y -
    quad.top_right.x * quad.top_left.y +
    quad.top_right.x * quad.bottom_right.y -
    quad.bottom_right.x * quad.top_right.y +
    quad.bottom_right.x * quad.bottom_left.y -
    quad.bottom_left.x * quad.bottom_right.y +
    quad.bottom_left.x * quad.top_left.y -
    quad.top_left.x * quad.bottom_left.y
  let area = sum / 2.0
  if area < 0.0 {
    -area
  } else {
    area
  }
}

///|
fn line_hit(
  origin : Point,
  direction : Point,
  other : Point,
  other_direction : Point,
) -> Point? {
  let det = direction.x * other_direction.y - direction.y * other_direction.x
  let gap = if det < 0.0 { -det } else { det }
  if gap < 0.000000000001 {
    None
  } else {
    let dx = other.x - origin.x
    let dy = other.y - origin.y
    let step = (dx * other_direction.y - dy * other_direction.x) / det
    Some({ x: origin.x + step * direction.x, y: origin.y + step * direction.y, })
  }
}

///|
/// Expand a convex quadrilateral by the DB distance `area * ratio / perimeter`.
pub fn unclip_quad(quad : DetQuad, ratio~ : Double) -> DetQuad raise OcrError {
  let perimeter = quad_perimeter(quad)
  if perimeter == 0.0 || ratio == 0.0 {
    return quad
  }
  let distance = quad_area(quad) * ratio / perimeter
  let corners = [
    quad.top_left,
    quad.top_right,
    quad.bottom_right,
    quad.bottom_left,
  ]
  let expanded : Array[Point] = []
  for index in 0..<4 {
    let start = corners[index]
    let end = corners[if index == 3 { 0 } else { index + 1 }]
    let previous = corners[if index == 0 { 3 } else { index - 1 }]
    let dx = end.x - start.x
    let dy = end.y - start.y
    let length = (dx * dx + dy * dy).sqrt()
    let prev_dx = start.x - previous.x
    let prev_dy = start.y - previous.y
    let prev_length = (prev_dx * prev_dx + prev_dy * prev_dy).sqrt()
    if length == 0.0 || prev_length == 0.0 {
      expanded.push(start)
    } else {
      let nx = dy / length
      let ny = -dx / length
      let px = prev_dy / prev_length
      let py = -prev_dx / prev_length
      match
        line_hit(
          { x: start.x + nx * distance, y: start.y + ny * distance, },
          { x: dx, y: dy, },
          { x: start.x + px * distance, y: start.y + py * distance, },
          { x: prev_dx, y: prev_dy, },
        ) {
        Some(point) => expanded.push(point)
        None => expanded.push(start)
      }
    }
  }
  order_corners(expanded, score=quad.score)
}

///|
fn quad_short_side(quad : DetQuad) -> Double {
  let width = point_dist(quad.top_left, quad.top_right)
  let height = point_dist(quad.top_left, quad.bottom_left)
  if width < height {
    width
  } else {
    height
  }
}

///|
/// Multiply both axes. Used to map detection-map coordinates onto the source.
pub fn DetQuad::scale(
  self : DetQuad,
  scale_x : Double,
  scale_y : Double,
) -> DetQuad {
  fn map(point : Point) -> Point {
    { x: point.x * scale_x, y: point.y * scale_y, }
  }

  {
    top_left: map(self.top_left),
    top_right: map(self.top_right),
    bottom_right: map(self.bottom_right),
    bottom_left: map(self.bottom_left),
    score: self.score,
  }
}

///|
/// Pixel bounds of the quadrilateral, clamped to the image.
pub fn DetQuad::bounds(
  self : DetQuad,
  width : Int32,
  height : Int32,
) -> GlyphBox? {
  if width <= 0 || height <= 0 {
    return None
  }
  let points = [
    self.top_left,
    self.top_right,
    self.bottom_right,
    self.bottom_left,
  ]
  let mut min_x = points[0].x
  let mut max_x = points[0].x
  let mut min_y = points[0].y
  let mut max_y = points[0].y
  for point in points {
    if point.x < min_x {
      min_x = point.x
    }
    if point.x > max_x {
      max_x = point.x
    }
    if point.y < min_y {
      min_y = point.y
    }
    if point.y > max_y {
      max_y = point.y
    }
  }
  let left = min_x.floor().to_int()
  let top = min_y.floor().to_int()
  let right = max_x.ceil().to_int()
  let bottom = max_y.ceil().to_int()
  let x0 = if left < 0 { 0 } else { left }
  let y0 = if top < 0 { 0 } else { top }
  let x1 = if right > width { width } else { right }
  let y1 = if bottom > height { height } else { bottom }
  if x1 <= x0 || y1 <= y0 {
    None
  } else {
    Some({ x: x0, y: y0, width: x1 - x0, height: y1 - y0, score: self.score, })
  }
}

///|
/// Pair a source-space quadrilateral with its clamped pixel bounds.
pub fn DetQuad::place(
  self : DetQuad,
  width : Int32,
  height : Int32,
) -> PlacedText? {
  match self.bounds(width, height) {
    Some(bounds) => Some({ quad: self, bounds, })
    None => None
  }
}

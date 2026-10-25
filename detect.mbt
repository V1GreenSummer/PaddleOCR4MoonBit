///|
/// One text region on the detection probability map, before it is scaled back
/// to the source image.
pub(all) struct DetBox {
  x : Double
  y : Double
  width : Double
  height : Double
  score : Double
} derive(Debug, Eq, ToJson)

///|
pub extend DetBox with Eq::{not_equal, equal}

///|
pub extend DetBox with ToJson::{to_json}

///|
pub extend DetBox with @debug.Debug::{to_repr}

///|
/// Axis-aligned text region in source pixels.
pub(all) struct GlyphBox {
  x : Int32
  y : Int32
  width : Int32
  height : Int32
  score : Double
} derive(Debug, Eq, ToJson)

///|
pub extend GlyphBox with Eq::{not_equal, equal}

///|
pub extend GlyphBox with ToJson::{to_json}

///|
pub extend GlyphBox with @debug.Debug::{to_repr}

///|
/// Axis-aligned and rotated views of the same probability map, computed in one
/// connected-component pass.
pub(all) struct DetRegions {
  boxes : Array[DetBox]
  quads : Array[DetQuad]
} derive(Debug, Eq, ToJson)

///|
pub extend DetRegions with Eq::{not_equal, equal}

///|
pub extend DetRegions with ToJson::{to_json}

///|
pub extend DetRegions with @debug.Debug::{to_repr}

///|
fn push_stack(stack : Array[Int32], cursor : Int32, value : Int32) -> Int32 {
  if cursor < stack.length() {
    stack[cursor] = value
  } else {
    stack.push(value)
  }
  cursor + 1
}

///|
fn consider(
  stack : Array[Int32],
  cursor : Int32,
  seen : FixedArray[Byte],
  prob : Array[Float],
  thresh : Double,
  x : Int32,
  y : Int32,
  width : Int32,
  height : Int32,
) -> Int32 {
  if x < 0 || y < 0 || x >= width || y >= height {
    return cursor
  }
  let index = y * width + x
  if seen[index] != b'\x00' || prob[index].to_double() < thresh {
    return cursor
  }
  seen[index] = b'\x01'
  push_stack(stack, cursor, index)
}

///|
priv struct DetComponent {
  min_x : Int32
  min_y : Int32
  max_x : Int32
  max_y : Int32
  score : Double
  points : Array[Point]
}

///|
fn scan_components(
  prob : Array[Float],
  height~ : Int32,
  width~ : Int32,
  thresh~ : Double,
  box_thresh~ : Double,
  collect_points~ : Bool,
) -> Array[DetComponent] raise OcrError {
  if width <= 0 || height <= 0 {
    raise OcrError::Model("probability map size must be positive")
  }
  if prob.length() != width * height {
    raise OcrError::Model("probability map length does not match width*height")
  }
  let seen : FixedArray[Byte] = FixedArray::make(width * height, b'\x00')
  let stack : Array[Int32] = []
  let components : Array[DetComponent] = []
  for y in 0..<height {
    for x in 0..<width {
      let seed = y * width + x
      if seen[seed] != b'\x00' || prob[seed].to_double() < thresh {
        continue
      }
      seen[seed] = b'\x01'
      let mut cursor = push_stack(stack, 0, seed)
      let pixels : Array[Int32] = []
      let mut min_x = x
      let mut min_y = y
      let mut max_x = x
      let mut max_y = y
      let mut sum = 0.0
      let mut count = 0
      while cursor > 0 {
        cursor = cursor - 1
        let index = stack[cursor]
        let column = index % width
        let row = index / width
        count = count + 1
        if collect_points {
          pixels.push(index)
        }
        if column < min_x {
          min_x = column
        }
        if row < min_y {
          min_y = row
        }
        if column > max_x {
          max_x = column
        }
        if row > max_y {
          max_y = row
        }
        sum = sum + prob[index].to_double()
        cursor = consider(
          stack,
          cursor,
          seen,
          prob,
          thresh,
          column + 1,
          row,
          width,
          height,
        )
        cursor = consider(
          stack,
          cursor,
          seen,
          prob,
          thresh,
          column - 1,
          row,
          width,
          height,
        )
        cursor = consider(
          stack,
          cursor,
          seen,
          prob,
          thresh,
          column,
          row + 1,
          width,
          height,
        )
        cursor = consider(
          stack,
          cursor,
          seen,
          prob,
          thresh,
          column,
          row - 1,
          width,
          height,
        )
      }
      if count == 0 {
        continue
      }
      let score = sum / count.to_double()
      if score < box_thresh {
        continue
      }
      let points : Array[Point] = []
      if collect_points {
        for index in pixels {
          let column = index % width
          let row = index / width
          let boundary = column == 0 ||
            column + 1 >= width ||
            row == 0 ||
            row + 1 >= height ||
            seen[index - 1] == b'\x00' ||
            seen[index + 1] == b'\x00' ||
            seen[index - width] == b'\x00' ||
            seen[index + width] == b'\x00'
          if boundary {
            let left = column.to_double()
            let top = row.to_double()
            points.push({ x: left, y: top, })
            points.push({ x: left + 1.0, y: top, })
            points.push({ x: left + 1.0, y: top + 1.0, })
            points.push({ x: left, y: top + 1.0, })
          }
        }
      }
      components.push({ min_x, min_y, max_x, max_y, score, points, })
    }
  }
  components
}

///|
fn box_from_component(
  component : DetComponent,
  map_width~ : Int32,
  map_height~ : Int32,
  unclip_ratio~ : Double,
  min_size~ : Int32,
) -> DetBox? {
  let box_w = component.max_x - component.min_x + 1
  let box_h = component.max_y - component.min_y + 1
  if box_w < min_size || box_h < min_size {
    return None
  }
  let region_w = box_w.to_double()
  let region_h = box_h.to_double()
  let perimeter = 2.0 * (region_w + region_h)
  let distance = if perimeter == 0.0 {
    0.0
  } else {
    region_w * region_h * unclip_ratio / perimeter
  }
  let left = component.min_x.to_double() - distance
  let top = component.min_y.to_double() - distance
  let right = left + region_w + distance * 2.0
  let bottom = top + region_h + distance * 2.0
  let x0 = if left < 0.0 { 0.0 } else { left }
  let y0 = if top < 0.0 { 0.0 } else { top }
  let map_w = map_width.to_double()
  let map_h = map_height.to_double()
  let x1 = if right > map_w { map_w } else { right }
  let y1 = if bottom > map_h { map_h } else { bottom }
  if x1 - x0 < 1.0 || y1 - y0 < 1.0 {
    None
  } else {
    Some({
      x: x0,
      y: y0,
      width: x1 - x0,
      height: y1 - y0,
      score: component.score,
    })
  }
}

///|
fn quad_from_component(
  component : DetComponent,
  unclip_ratio~ : Double,
  min_size~ : Int32,
) -> DetQuad? raise OcrError {
  let fitted = min_area_rect(component.points)
  if quad_short_side(fitted) < min_size.to_double() {
    None
  } else {
    Some(unclip_quad({ ..fitted, score: component.score, }, ratio=unclip_ratio))
  }
}

///|
/// Connected-component boxes for a DBNet probability map.
///
/// The map is row-major. Components below `min_size` or `box_thresh` are
/// dropped. The remaining rectangle is expanded by the DB unclip distance
/// `area * unclip_ratio / perimeter` and clipped to the map.
pub fn db_boxes(
  prob : Array[Float],
  height~ : Int32,
  width~ : Int32,
  thresh~ : Double = 0.3,
  box_thresh~ : Double = 0.6,
  unclip_ratio~ : Double = 1.5,
  min_size~ : Int32 = 3,
) -> Array[DetBox] raise OcrError {
  let components = scan_components(
    prob,
    height~,
    width~,
    thresh~,
    box_thresh~,
    collect_points=false,
  )
  let boxes : Array[DetBox] = []
  for component in components {
    match
      box_from_component(
        component,
        map_width=width,
        map_height=height,
        unclip_ratio~,
        min_size~,
      ) {
      Some(box) => boxes.push(box)
      None => ()
    }
  }
  boxes
}

///|
/// Connected components as minimum-area rectangles, expanded by the DB unclip
/// distance. Short sides below `min_size` and means below `box_thresh` are
/// dropped. Corners are ordered from the top-left.
pub fn db_quads(
  prob : Array[Float],
  height~ : Int32,
  width~ : Int32,
  thresh~ : Double = 0.3,
  box_thresh~ : Double = 0.6,
  unclip_ratio~ : Double = 1.5,
  min_size~ : Int32 = 3,
) -> Array[DetQuad] raise OcrError {
  let components = scan_components(
    prob,
    height~,
    width~,
    thresh~,
    box_thresh~,
    collect_points=true,
  )
  let quads : Array[DetQuad] = []
  for component in components {
    match quad_from_component(component, unclip_ratio~, min_size~) {
      Some(quad) => quads.push(quad)
      None => ()
    }
  }
  quads
}

///|
/// Compute axis-aligned boxes and minimum-area quads in one pass.
///
/// The two arrays use the same component scan, but each keeps its own
/// `min_size` rule: boxes check the bounding rectangle, quads check the fitted
/// rectangle.
pub fn db_regions(
  prob : Array[Float],
  height~ : Int32,
  width~ : Int32,
  thresh~ : Double = 0.3,
  box_thresh~ : Double = 0.6,
  unclip_ratio~ : Double = 1.5,
  min_size~ : Int32 = 3,
) -> DetRegions raise OcrError {
  let components = scan_components(
    prob,
    height~,
    width~,
    thresh~,
    box_thresh~,
    collect_points=true,
  )
  let boxes : Array[DetBox] = []
  let quads : Array[DetQuad] = []
  for component in components {
    match
      box_from_component(
        component,
        map_width=width,
        map_height=height,
        unclip_ratio~,
        min_size~,
      ) {
      Some(box) => boxes.push(box)
      None => ()
    }
    match quad_from_component(component, unclip_ratio~, min_size~) {
      Some(quad) => quads.push(quad)
      None => ()
    }
  }
  { boxes, quads, }
}

///|
/// Scale a detection box back to source pixels.
pub fn map_det_box(
  box : DetBox,
  ratio_w~ : Double,
  ratio_h~ : Double,
  width~ : Int32,
  height~ : Int32,
) -> GlyphBox? {
  if ratio_w == 0.0 || ratio_h == 0.0 || width <= 0 || height <= 0 {
    return None
  }
  let left = (box.x / ratio_w).floor().to_int()
  let top = (box.y / ratio_h).floor().to_int()
  let right = ((box.x + box.width) / ratio_w).ceil().to_int()
  let bottom = ((box.y + box.height) / ratio_h).ceil().to_int()
  let x0 = if left < 0 { 0 } else { left }
  let y0 = if top < 0 { 0 } else { top }
  let x1 = if right > width { width } else { right }
  let y1 = if bottom > height { height } else { bottom }
  if x1 <= x0 || y1 <= y0 {
    None
  } else {
    Some({ x: x0, y: y0, width: x1 - x0, height: y1 - y0, score: box.score, })
  }
}

///|
fn cmp_int(left : Int32, right : Int32) -> Int32 {
  if left < right {
    -1
  } else if left > right {
    1
  } else {
    0
  }
}

///|
fn same_line(line : Array[GlyphBox], box : GlyphBox) -> Bool {
  if line.length() == 0 {
    return false
  }
  let mut top = line[0].y
  let mut bottom = line[0].y + line[0].height
  for item in line {
    if item.y < top {
      top = item.y
    }
    let item_bottom = item.y + item.height
    if item_bottom > bottom {
      bottom = item_bottom
    }
  }
  let overlap_top = if top > box.y { top } else { box.y }
  let overlap_bottom = if bottom < box.y + box.height {
    bottom
  } else {
    box.y + box.height
  }
  let overlap = overlap_bottom - overlap_top
  if overlap <= 0 {
    return false
  }
  let line_height = bottom - top
  let shorter = if line_height < box.height { line_height } else { box.height }
  shorter > 0 && overlap * 2 >= shorter
}

///|
/// Group boxes into reading lines. Lines run top to bottom, and boxes inside a
/// line run left to right.
pub fn group_lines(boxes : Array[GlyphBox]) -> Array[Array[GlyphBox]] {
  let ordered : Array[GlyphBox] = []
  for box in boxes {
    ordered.push(box)
  }
  ordered.sort_by((left, right) => {
    let by_y = cmp_int(left.y, right.y)
    if by_y != 0 {
      by_y
    } else {
      cmp_int(left.x, right.x)
    }
  })
  let lines : Array[Array[GlyphBox]] = []
  for box in ordered {
    if lines.length() == 0 || !same_line(lines[lines.length() - 1], box) {
      lines.push([box])
    } else {
      lines[lines.length() - 1].push(box)
    }
  }
  for line in lines {
    line.sort_by((left, right) => cmp_int(left.x, right.x))
  }
  lines
}

///|
/// Group placed quadrilaterals with the same reading-order rule as `group_lines`.
pub fn group_placed(items : Array[PlacedText]) -> Array[Array[PlacedText]] {
  let ordered : Array[PlacedText] = []
  for item in items {
    ordered.push(item)
  }
  ordered.sort_by((left, right) => {
    let by_y = cmp_int(left.bounds.y, right.bounds.y)
    if by_y != 0 {
      by_y
    } else {
      cmp_int(left.bounds.x, right.bounds.x)
    }
  })
  let lines : Array[Array[PlacedText]] = []
  for item in ordered {
    if lines.length() == 0 {
      lines.push([item])
    } else {
      let current : Array[GlyphBox] = []
      for placed in lines[lines.length() - 1] {
        current.push(placed.bounds)
      }
      if same_line(current, item.bounds) {
        lines[lines.length() - 1].push(item)
      } else {
        lines.push([item])
      }
    }
  }
  for line in lines {
    line.sort_by((left, right) => cmp_int(left.bounds.x, right.bounds.x))
  }
  lines
}

///|
test "min-area rect of a diamond is smaller than its bounding box" {
  let quad = @paddleocr.min_area_rect([
    { x: 0.0, y: 1.0, },
    { x: 1.0, y: 0.0, },
    { x: 2.0, y: 1.0, },
    { x: 1.0, y: 2.0, },
  ])
  let dx = quad.top_right.x - quad.top_left.x
  let dy = quad.top_right.y - quad.top_left.y
  let abs_dx = if dx < 0.0 { -dx } else { dx }
  let abs_dy = if dy < 0.0 { -dy } else { dy }
  assert_true(abs_dx > 0.5 && abs_dy > 0.5)
  let width = (dx * dx + dy * dy).sqrt()
  let ex = quad.bottom_left.x - quad.top_left.x
  let ey = quad.bottom_left.y - quad.top_left.y
  let height = (ex * ex + ey * ey).sqrt()
  assert_true(near_double(width * height, 2.0))
}

///|
test "unclip expands an axis-aligned square by the db distance" {
  let quad = @paddleocr.unclip_quad(
    {
      top_left: { x: 0.0, y: 0.0, },
      top_right: { x: 2.0, y: 0.0, },
      bottom_right: { x: 2.0, y: 2.0, },
      bottom_left: { x: 0.0, y: 2.0, },
      score: 0.5,
    },
    ratio=1.5,
  )
  assert_true(near_double(quad.top_left.x, -0.75))
  assert_true(near_double(quad.top_left.y, -0.75))
  assert_true(near_double(quad.bottom_right.x, 2.75))
  assert_true(near_double(quad.bottom_right.y, 2.75))
  assert_true(near_double(quad.score, 0.5))
}

///|
test "db quads expand a component and drop a one-pixel blip" {
  let prob : Array[Float] = Array::make(64, 0.0)
  for y in 2..<5 {
    for x in 2..<5 {
      prob[y * 8 + x] = 0.9
    }
  }
  prob[0] = 0.95
  let quads = @paddleocr.db_quads(prob, height=8, width=8)
  assert_eq(quads.length(), 1)
  let quad = quads[0]
  assert_true(near_double(quad.top_left.x, 0.875))
  assert_true(near_double(quad.top_left.y, 0.875))
  assert_true(near_double(quad.bottom_right.x, 6.125))
  assert_true(near_double(quad.bottom_right.y, 6.125))
  assert_true(near_double(quad.score, 0.9))
}

///|
test "warp keeps corner colors and turns a tall strip sideways" {
  let image = @paddleocr.Rgba::from_rgba(2, 2, [
    b'\xff', b'\x00', b'\x00', b'\xff', b'\x00', b'\xff', b'\x00', b'\xff', b'\x00',
    b'\x00', b'\xff', b'\xff', b'\xff', b'\xff', b'\xff', b'\xff',
  ])
  let quad : @paddleocr.DetQuad = {
    top_left: { x: 0.0, y: 0.0, },
    top_right: { x: 2.0, y: 0.0, },
    bottom_right: { x: 2.0, y: 2.0, },
    bottom_left: { x: 0.0, y: 2.0, },
    score: 1.0,
  }
  let warped = image.warp(quad)
  assert_eq(warped.width, 2)
  assert_eq(warped.height, 2)
  assert_eq(warped.pixels[0], b'\xff')
  assert_eq(warped.pixels[1], b'\x00')
  assert_eq(warped.pixels[4], b'\x00')
  assert_eq(warped.pixels[5], b'\xff')
  assert_eq(warped.pixels[12], b'\xff')
  let tall = Bytes::make(2 * 4 * 4, b'\x00')
  let painted = Bytes::makei(tall.length(), fn(index) {
    let pixel = index / 4
    let channel = index % 4
    if pixel == 0 && channel == 0 {
      b'\xff'
    } else if pixel == 1 && channel == 1 {
      b'\xff'
    } else if channel == 3 {
      b'\xff'
    } else {
      b'\x00'
    }
  })
  let strip = @paddleocr.Rgba::from_rgba(2, 4, painted)
  let upright = strip.warp({
    top_left: { x: 0.0, y: 0.0, },
    top_right: { x: 2.0, y: 0.0, },
    bottom_right: { x: 2.0, y: 4.0, },
    bottom_left: { x: 0.0, y: 4.0, },
    score: 1.0,
  })
  assert_eq(upright.width, 4)
  assert_eq(upright.height, 2)
  assert_eq(upright.pixels[1], b'\xff')
  assert_eq(upright.pixels[4 * 4], b'\xff')
}

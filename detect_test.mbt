///|
fn near_double(actual : Double, expected : Double) -> Bool {
  let delta = if actual > expected {
    actual - expected
  } else {
    expected - actual
  }
  delta < 0.0000001
}

///|
test "db boxes expand a component and drop a weak one" {
  let prob : Array[Float] = Array::make(64, 0.0)
  for y in 2..<5 {
    for x in 2..<5 {
      prob[y * 8 + x] = 0.9
    }
  }
  prob[0] = 0.95
  let boxes = @paddleocr.db_boxes(prob, height=8, width=8)
  assert_eq(boxes.length(), 1)
  let box = boxes[0]
  assert_true(near_double(box.x, 0.875))
  assert_true(near_double(box.y, 0.875))
  assert_true(near_double(box.width, 5.25))
  assert_true(near_double(box.height, 5.25))
  assert_true(near_double(box.score, 0.9))
}

///|
test "boxes are grouped into reading lines" {
  let boxes : Array[@paddleocr.GlyphBox] = [
    { x: 20, y: 0, width: 10, height: 10, score: 0.8, },
    { x: 0, y: 1, width: 10, height: 10, score: 0.7, },
    { x: 0, y: 40, width: 8, height: 8, score: 0.6, },
  ]
  let lines = @paddleocr.group_lines(boxes)
  assert_eq(lines.length(), 2)
  assert_eq(lines[0][0].x, 0)
  assert_eq(lines[0][1].x, 20)
  assert_eq(lines[1][0].y, 40)
}

///|
test "map_det_box scales into source pixels" {
  let box : @paddleocr.DetBox = {
    x: 16.0,
    y: 8.0,
    width: 16.0,
    height: 8.0,
    score: 0.8,
  }
  let mapped = @paddleocr.map_det_box(
    box,
    ratio_w=0.5,
    ratio_h=0.5,
    width=100,
    height=80,
  )
  match mapped {
    Some(glyph) => {
      inspect(glyph.x, content="32")
      inspect(glyph.y, content="16")
      inspect(glyph.width, content="32")
      inspect(glyph.height, content="16")
    }
    None => fail("expected a mapped box")
  }
}

///|
test "db_regions computes boxes and quads in one pass" {
  let prob : Array[Float] = Array::make(64, 0.0)
  for y in 2..<5 {
    for x in 2..<5 {
      prob[y * 8 + x] = 0.9
    }
  }
  let regions = @paddleocr.db_regions(prob, height=8, width=8)
  assert_eq(regions.boxes.length(), 1)
  assert_eq(regions.quads.length(), 1)
  assert_true(near_double(regions.boxes[0].score, 0.9))
  assert_true(near_double(regions.quads[0].score, 0.9))
}

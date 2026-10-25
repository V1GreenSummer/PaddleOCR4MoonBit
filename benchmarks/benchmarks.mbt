///|
fn make_prob(width : Int32, height : Int32) -> Array[Float] {
  let prob : Array[Float] = Array::make(width * height, 0.0)
  for index in 0..<20 {
    let left = 20 + index % 4 * 230
    let top = 20 + index / 4 * 180
    for y in top..<(top + 50) {
      for x in left..<(left + 200) {
        prob[y * width + x] = 0.9
      }
    }
  }
  prob
}

///|
fn make_image(width : Int32, height : Int32) -> @paddleocr.Rgba {
  @paddleocr.Rgba::from_rgba(
    width,
    height,
    Bytes::make(width * height * 4, b'\x80'),
  ) catch {
    _ => abort("failed to build benchmark image")
  }
}

///|
test "bench db postprocess" (b : @bench.T) {
  let prob = make_prob(960, 960)
  b.bench(name="db_boxes", fn() {
    b.keep(try! @paddleocr.db_boxes(prob, height=960, width=960).length())
  })
  b.bench(name="db_quads", fn() {
    b.keep(try! @paddleocr.db_quads(prob, height=960, width=960).length())
  })
  b.bench(name="db_regions", fn() {
    b.keep(
      try! @paddleocr.db_regions(prob, height=960, width=960).quads.length(),
    )
  })
}

///|
test "bench detection preprocessing" (b : @bench.T) {
  let image = make_image(780, 300)
  b.bench(name="prepare_det_780x300", fn() {
    b.keep(
      try! @paddleocr.prepare_det(image, limit_side_len=960).tensor.values.length(),
    )
  })
}

///|
test "bench CTC decode" (b : @bench.T) {
  let text = StringBuilder()
  for index in 0..<100 {
    text.write_string("c\{index}\n")
  }
  let charset = @paddleocr.Charset::from_text(text.to_string())
  let logits : Array[Float] = Array::make(80 * 100, 0.0)
  b.bench(name="ctc_decode_80x100", fn() {
    b.keep(
      try! @paddleocr.ctc_decode(logits, time=80, classes=100, charset~).text.length(),
    )
  })
}

///|
test "bench perspective warp" (b : @bench.T) {
  let image = make_image(800, 600)
  let quad : @paddleocr.DetQuad = {
    top_left: { x: 40.0, y: 40.0, },
    top_right: { x: 640.0, y: 50.0, },
    bottom_right: { x: 640.0, y: 90.0, },
    bottom_left: { x: 40.0, y: 80.0, },
    score: 0.9,
  }
  b.bench(name="warp_600x50", fn() { b.keep(try! image.warp(quad).width) })
}

///|
test "options builders keep the other PP-OCR defaults" {
  let options = @paddleocr.RecognizeOptions::standard()
    .with_limit(640)
    .with_det_thresh(0.2)
    .with_box_thresh(0.7)
    .with_unclip_ratio(1.8)
    .with_min_size(5)
    .with_rec_max_width(480)
    .with_rec_thresh(0.6)
  inspect(options.limit_side_len, content="640")
  inspect(options.det_thresh, content="0.2")
  inspect(options.box_thresh, content="0.7")
  inspect(options.unclip_ratio, content="1.8")
  inspect(options.min_size, content="5")
  inspect(options.rec_max_width, content="480")
  inspect(options.rec_thresh, content="0.6")
}

///|
test "options default is the standard preset" {
  let options : @paddleocr.RecognizeOptions = Default::default()
  inspect(options.limit_side_len, content="960")
  inspect(options.min_size, content="3")
  inspect(options.rec_thresh, content="0.5")
}

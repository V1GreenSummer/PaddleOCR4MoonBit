///|
/// Single native entry point. Import `V1GreenSummer/paddleocr/ocr` to get the
/// `Engine` plus the result, option, geometry, and decoding types without
/// importing the root and `engine` packages separately.
pub using @engine {
  type Engine,
  type EngineOptions,
  type GraphOptimizationLevel,
  type ExecutionMode,
  type Backend,
  type DetectFn,
  type RecognizeFn,
  with_engine,
  recognize_with,
  recognize_quads_with,
}

///|
pub using @paddleocr {
  type OcrError,
  type Page,
  type TextLine,
  type TextSpan,
  type CtcText,
  type Charset,
  type Rgba,
  type RasterKind,
  type ChwTensor,
  type DetTensor,
  type DetBox,
  type DetQuad,
  type DetRegions,
  type GlyphBox,
  type PlacedText,
  type Point,
  type RecognizeOptions,
  sniff_raster,
  decode_raster,
  limit_side_size,
  prepare_det,
  prepare_rec,
  db_boxes,
  db_quads,
  db_regions,
  map_det_box,
  min_area_rect,
  unclip_quad,
  order_corners,
  group_lines,
  group_placed,
  ctc_decode,
  ctc_greedy,
}

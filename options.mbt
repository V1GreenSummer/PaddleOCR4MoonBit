///|
/// Detection size and DB thresholds for one call. `standard` matches PP-OCRv4.
pub(all) struct RecognizeOptions {
  limit_side_len : Int32
  det_thresh : Double
  box_thresh : Double
  unclip_ratio : Double
  min_size : Int32
  rec_max_width : Int32
  rec_thresh : Double
} derive(Debug, Eq, ToJson)

///|
pub extend RecognizeOptions with Eq::{not_equal, equal}

///|
pub extend RecognizeOptions with ToJson::{to_json}

///|
pub extend RecognizeOptions with @debug.Debug::{to_repr}

///|
/// PP-OCRv4 defaults: long side 960, threshold 0.3, box threshold 0.6,
/// unclip 1.5, minimum component side 3, recognition width 320, recognition
/// confidence 0.5.
///
/// # Example
/// ```mbt check
/// test {
///   let options = @paddleocr.RecognizeOptions::standard().with_limit(640)
///   inspect(options.limit_side_len, content="640")
///   inspect(options.box_thresh, content="0.6")
///   inspect(options.min_size, content="3")
/// }
/// ```
pub fn RecognizeOptions::standard() -> RecognizeOptions {
  {
    limit_side_len: 960,
    det_thresh: 0.3,
    box_thresh: 0.6,
    unclip_ratio: 1.5,
    min_size: 3,
    rec_max_width: 320,
    rec_thresh: 0.5,
  }
}

///|
pub impl Default for RecognizeOptions with fn default() {
  RecognizeOptions::standard()
}

///|
pub extend RecognizeOptions with Default::{default}

///|
/// Same options with a different detection long-side limit.
pub fn RecognizeOptions::with_limit(
  self : RecognizeOptions,
  limit_side_len : Int32,
) -> RecognizeOptions {
  { ..self, limit_side_len, }
}

///|
/// Same options with a different DB foreground threshold.
pub fn RecognizeOptions::with_det_thresh(
  self : RecognizeOptions,
  det_thresh : Double,
) -> RecognizeOptions {
  { ..self, det_thresh, }
}

///|
/// Same options with a different DB box threshold.
pub fn RecognizeOptions::with_box_thresh(
  self : RecognizeOptions,
  box_thresh : Double,
) -> RecognizeOptions {
  { ..self, box_thresh, }
}

///|
/// Same options with a different DB unclip ratio.
pub fn RecognizeOptions::with_unclip_ratio(
  self : RecognizeOptions,
  unclip_ratio : Double,
) -> RecognizeOptions {
  { ..self, unclip_ratio, }
}

///|
/// Same options with a different minimum component side.
pub fn RecognizeOptions::with_min_size(
  self : RecognizeOptions,
  min_size : Int32,
) -> RecognizeOptions {
  { ..self, min_size, }
}

///|
/// Same options with a different recognition width cap.
pub fn RecognizeOptions::with_rec_max_width(
  self : RecognizeOptions,
  rec_max_width : Int32,
) -> RecognizeOptions {
  { ..self, rec_max_width, }
}

///|
/// Same options with a different recognition confidence threshold.
pub fn RecognizeOptions::with_rec_thresh(
  self : RecognizeOptions,
  rec_thresh : Double,
) -> RecognizeOptions {
  { ..self, rec_thresh, }
}

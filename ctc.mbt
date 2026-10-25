///|
/// PP-OCR character dictionary. Class 0 is the CTC blank and is not stored.
/// Class `k` is line `k - 1`.
pub struct Charset {
  chars : Array[String]
} derive(Debug, Eq)

///|
pub extend Charset with Eq::{not_equal, equal}

///|
pub extend Charset with @debug.Debug::{to_repr}

///|
fn strip_cr(line : String) -> String {
  if line.length() > 0 && line[line.length() - 1] == '\r' {
    line[:line.length() - 1].to_owned()
  } else {
    line
  }
}

///|
/// Parse a dictionary file. A trailing newline does not add an empty class.
pub fn Charset::from_text(text : String) -> Charset {
  let collected : Array[String] = []
  for part in text.split("\n") {
    collected.push(strip_cr(part.to_owned()))
  }
  let mut limit = collected.length()
  if limit > 0 && collected[limit - 1].length() == 0 {
    limit = limit - 1
  }
  let chars : Array[String] = []
  for index in 0..<limit {
    chars.push(collected[index])
  }
  { chars, }
}

///|
/// Dictionary plus the trailing space class used by PP-OCR (`use_space_char`).
///
/// A trailing newline still does not add an empty class. A dictionary that
/// already ends with a space is left unchanged.
///
/// # Example
/// ```mbt check
/// test {
///   let charset = @paddleocr.Charset::ppocr("你\n好\n")
///   debug_inspect(charset.glyph(3), content="Some(\" \")")
/// }
/// ```
pub fn Charset::ppocr(text : String) -> Charset {
  let parsed = Charset::from_text(text)
  let count = parsed.chars.length()
  if count > 0 && parsed.chars[count - 1] == " " {
    parsed
  } else {
    parsed.chars.push(" ")
    parsed
  }
}

///|
/// Map a CTC class to its character. Blank and out-of-range classes are `None`.
pub fn Charset::glyph(self : Charset, class : Int32) -> String? {
  if class <= 0 {
    None
  } else {
    let index = class - 1
    if index >= self.chars.length() {
      None
    } else {
      Some(self.chars[index])
    }
  }
}

///|
/// Greedy CTC text and the mean probability of the kept characters.
pub(all) struct CtcText {
  text : String
  confidence : Double
} derive(Debug, Eq, ToJson)

///|
pub extend CtcText with Eq::{not_equal, equal}

///|
pub extend CtcText with ToJson::{to_json}

///|
pub extend CtcText with @debug.Debug::{to_repr}

///|
fn step_confidence(
  logits : ArrayView[Float],
  offset : Int32,
  classes : Int32,
  best : Int32,
) -> Double {
  let mut sum = 0.0
  let mut negative = false
  let mut peak = logits[offset].to_double()
  for class in 0..<classes {
    let value = logits[offset + class].to_double()
    if value < 0.0 {
      negative = true
    }
    if value > peak {
      peak = value
    }
    sum = sum + value
  }
  let chosen = logits[offset + best].to_double()
  if !negative && (if sum > 1.0 { sum - 1.0 } else { 1.0 - sum }) <= 0.05 {
    chosen
  } else {
    let mut denom = 0.0
    for class in 0..<classes {
      denom = denom + @math.exp(logits[offset + class].to_double() - peak)
    }
    if denom == 0.0 {
      0.0
    } else {
      @math.exp(chosen - peak) / denom
    }
  }
}

///|
/// Greedy CTC decode. `logits` is row-major `[time, classes]`.
///
/// Confidence is the mean score of the emitted characters. A row that already
/// sums to one is treated as probabilities; otherwise the score is a softmax.
///
/// # Example
/// ```mbt check
/// test {
///   let charset = @paddleocr.Charset::from_text("a\nb\n")
///   let logits : Array[Float] = [
///     0.0, 1.0, 0.0, 0.0, 1.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0,
///   ]
///   inspect(
///     @paddleocr.ctc_greedy(logits, time=4, classes=3, charset~),
///     content="ab",
///   )
/// }
/// ```
pub fn ctc_greedy(
  logits : ArrayView[Float],
  time~ : Int32,
  classes~ : Int32,
  charset~ : Charset,
) -> String raise OcrError {
  ctc_decode(logits, time~, classes~, charset~).text
}

///|
/// Greedy CTC decode with a confidence in `0.0..=1.0` when the row is a
/// probability distribution or a softmax of logits.
pub fn ctc_decode(
  logits : ArrayView[Float],
  time~ : Int32,
  classes~ : Int32,
  charset~ : Charset,
) -> CtcText raise OcrError {
  if time < 0 || classes <= 0 {
    raise OcrError::Model("ctc shape is invalid")
  }
  if logits.length() != time * classes {
    raise OcrError::Model("ctc logits length does not match time*classes")
  }
  let builder = StringBuilder()
  let mut previous = -1
  let mut score_sum = 0.0
  let mut score_count = 0
  for step in 0..<time {
    let offset = step * classes
    let mut best = 0
    let mut best_value = logits[offset]
    for class in 1..<classes {
      let value = logits[offset + class]
      if value > best_value {
        best = class
        best_value = value
      }
    }
    if best != 0 && best != previous {
      match charset.glyph(best) {
        Some(text) => {
          builder.write_string(text)
          score_sum = score_sum + step_confidence(logits, offset, classes, best)
          score_count = score_count + 1
        }
        None => ()
      }
    }
    previous = best
  }
  let confidence = if score_count == 0 {
    0.0
  } else {
    score_sum / score_count.to_double()
  }
  { text: builder.to_string(), confidence, }
}

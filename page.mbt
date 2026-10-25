///|
/// One recognized text region. `quad` keeps the rotated geometry, `bounds` is
/// the axis-aligned rectangle used by `Page::render`, and the two scores keep
/// detection and recognition confidence separate.
pub(all) struct TextSpan {
  quad : DetQuad
  bounds : GlyphBox
  text : String
  det_score : Double
  rec_confidence : Double
} derive(Debug, Eq, ToJson)

///|
pub extend TextSpan with Eq::{not_equal, equal}

///|
pub extend TextSpan with ToJson::{to_json}

///|
pub extend TextSpan with @debug.Debug::{to_repr}

///|
/// Spans that share a reading line, already ordered left to right. `text` is
/// computed from `spans`, so the two cannot disagree.
pub(all) struct TextLine {
  spans : Array[TextSpan]
} derive(Debug, Eq)

///|
pub extend TextLine with Eq::{not_equal, equal}

///|
pub extend TextLine with ToJson::{to_json}

///|
pub extend TextLine with @debug.Debug::{to_repr}

///|
/// Build a line from spans that are already in left-to-right order.
pub fn TextLine::from_spans(spans : Array[TextSpan]) -> TextLine {
  { spans, }
}

///|
/// Concatenate the span texts without inserting separators.
pub fn TextLine::text(self : TextLine) -> String {
  let builder = StringBuilder()
  for span in self.spans {
    builder.write_string(span.text)
  }
  builder.to_string()
}

///|
/// Serialize a line as `{ "text": ..., "spans": [...] }`.
pub impl ToJson for TextLine with fn to_json(self : TextLine) -> Json {
  Json::object({
    "text": Json::string(self.text()),
    "spans": Json::array(self.spans.map(span => Json::Json(span))),
  })
}

///|
/// A page of reading lines.
pub(all) struct Page {
  lines : Array[TextLine]
} derive(Debug, Eq)

///|
pub extend Page with Eq::{not_equal, equal}

///|
pub extend Page with ToJson::{to_json}

///|
pub extend Page with @debug.Debug::{to_repr}

///|
/// Build a page from lines that are already in reading order.
pub fn Page::from_lines(lines : Array[TextLine]) -> Page {
  { lines, }
}

///|
/// All spans in reading order.
pub fn Page::spans(self : Page) -> Array[TextSpan] {
  let spans : Array[TextSpan] = []
  for line in self.lines {
    for span in line.spans {
      spans.push(span)
    }
  }
  spans
}

///|
/// Serialize the page as `{ "lines": [...] }`.
pub impl ToJson for Page with fn to_json(self : Page) -> Json {
  Json::object({
    "lines": Json::array(self.lines.map(line => Json::Json(line))),
  })
}

///|
/// Serialize the page to a compact JSON string.
pub fn Page::to_json_string(self : Page) -> String {
  Json::Json(self).stringify()
}

///|
pub impl Show for Page with fn output(self, logger) {
  for index in 0..<self.lines.length() {
    if index > 0 {
      logger.write_string("\n")
    }
    logger.write_string(self.lines[index].text())
  }
}

///|
pub extend Page with Show::{to_string, output}

///|
/// Text of the page, with one reading line per row.
pub fn Page::text(self : Page) -> String {
  self.to_string()
}

///|
/// `text` when `boxes` is false. Otherwise one span per row:
/// `x,y,width,height<TAB>det_score<TAB>rec_confidence<TAB>text`.
///
/// # Example
/// ```mbt check
/// test {
///   let quad : @paddleocr.DetQuad = {
///     top_left: { x: 1.0, y: 2.0, },
///     top_right: { x: 4.0, y: 2.0, },
///     bottom_right: { x: 4.0, y: 6.0, },
///     bottom_left: { x: 1.0, y: 6.0, },
///     score: 0.5,
///   }
///   let page = @paddleocr.Page::from_lines([
///     @paddleocr.TextLine::from_spans([
///       {
///         quad,
///         bounds: { x: 1, y: 2, width: 3, height: 4, score: 0.5, },
///         text: "你好",
///         det_score: 0.5,
///         rec_confidence: 0.9,
///       },
///     ]),
///   ])
///   inspect(page.render(), content="你好")
///   inspect(page.render(boxes=true), content="1,2,3,4\t0.5\t0.9\t你好")
/// }
/// ```
pub fn Page::render(self : Page, boxes~ : Bool = false) -> String {
  if boxes {
    let builder = StringBuilder()
    let mut started = false
    for line in self.lines {
      for span in line.spans {
        if started {
          builder.write_char('\n')
        }
        started = true
        let bounds = span.bounds
        builder.write_string(
          "\{bounds.x},\{bounds.y},\{bounds.width},\{bounds.height}\t\{span.det_score}\t\{span.rec_confidence}\t\{span.text}",
        )
      }
    }
    builder.to_string()
  } else {
    self.text()
  }
}

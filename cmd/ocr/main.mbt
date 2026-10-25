///|
extern "C" fn host_exit(code : Int32) -> Unit = "exit"

///|
struct Flags {
  image : String
  det : String
  rec : String
  dict : String
  library : String?
  limit : Int32
  boxes : Bool
}

///|
fn usage_text() -> String {
  "usage: moon run cmd/ocr -- <image> --det <det.onnx> --rec <rec.onnx> --dict <ppocr_keys.txt> [--library <libonnxruntime>] [--limit 960] [--boxes]"
}

///|
fn take(
  args : Array[String],
  index : Int32,
  flag : String,
) -> String raise @paddleocr.OcrError {
  if index >= args.length() {
    raise @paddleocr.OcrError::usage(
      "missing value for \{flag}\n\{usage_text()}",
    )
  }
  args[index]
}

///|
fn parse_flags(args : Array[String]) -> Flags raise @paddleocr.OcrError {
  let mut image : String? = None
  let mut det : String? = None
  let mut rec : String? = None
  let mut dict : String? = None
  let mut library : String? = None
  let mut limit = 960
  let mut boxes = false
  let mut index = 1
  while index < args.length() {
    let arg = args[index]
    if arg == "--det" {
      index = index + 1
      det = Some(take(args, index, "--det"))
    } else if arg == "--rec" {
      index = index + 1
      rec = Some(take(args, index, "--rec"))
    } else if arg == "--dict" {
      index = index + 1
      dict = Some(take(args, index, "--dict"))
    } else if arg == "--library" {
      index = index + 1
      library = Some(take(args, index, "--library"))
    } else if arg == "--limit" {
      index = index + 1
      let text = take(args, index, "--limit")
      limit = @string.parse_int(text) catch {
        _ =>
          raise @paddleocr.OcrError::usage(
            "limit_side_len is not an integer\n\{usage_text()}",
          )
      }
    } else if arg == "--boxes" {
      boxes = true
    } else if arg.has_prefix("-") {
      raise @paddleocr.OcrError::usage("unknown flag \{arg}\n\{usage_text()}")
    } else if image is None {
      image = Some(arg)
    } else {
      raise @paddleocr.OcrError::usage(
        "unexpected argument \{arg}\n\{usage_text()}",
      )
    }
    index = index + 1
  }
  match (image, det, rec, dict) {
    (Some(image), Some(det), Some(rec), Some(dict)) =>
      { image, det, rec, dict, library, limit, boxes, }
    _ => raise @paddleocr.OcrError::usage(usage_text())
  }
}

///|
fn run() -> Unit raise @paddleocr.OcrError {
  let flags = parse_flags(@env.args())
  let options = @paddleocr.RecognizeOptions::standard().with_limit(flags.limit)
  let engine = @engine.Engine::load(
    det=flags.det,
    rec=flags.rec,
    dict=flags.dict,
    library?=flags.library,
  )
  errdefer engine.close()
  let text = engine
    .recognize_file(flags.image, options~)
    .render(boxes=flags.boxes)
  if text.length() > 0 {
    println(text)
  }
  engine.close()
}

///|
fn main {
  run() catch {
    error => {
      println(error.to_string())
      host_exit(1)
    }
  }
}

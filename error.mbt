///|
/// Failure from decoding, tensor geometry, configuration, or an ONNX Runtime
/// call.
pub suberror OcrError {
  Image(String)
  Model(String)
  Runtime(String)
  Io(String)
  Config(String)
  Usage(String)
}

///|
pub impl Show for OcrError with fn output(self, logger) {
  match self {
    Image(message) => logger.write_string("image: \{message}")
    Model(message) => logger.write_string("model: \{message}")
    Runtime(message) => logger.write_string("runtime: \{message}")
    Io(message) => logger.write_string("io: \{message}")
    Config(message) => logger.write_string("config: \{message}")
    Usage(message) => logger.write_string(message)
  }
}

///|
pub extend OcrError with Show::{to_string, output}

///|
/// Image decoding or geometry failure.
pub fn OcrError::image(message : String) -> OcrError {
  Image(message)
}

///|
/// Model contract failure.
pub fn OcrError::model(message : String) -> OcrError {
  Model(message)
}

///|
/// Runtime failure.
pub fn OcrError::runtime(message : String) -> OcrError {
  Runtime(message)
}

///|
/// File or stream failure.
pub fn OcrError::io(message : String) -> OcrError {
  Io(message)
}

///|
/// Invalid options or missing model files.
pub fn OcrError::config(message : String) -> OcrError {
  Config(message)
}

///|
/// Command-line failure.
pub fn OcrError::usage(message : String) -> OcrError {
  Usage(message)
}

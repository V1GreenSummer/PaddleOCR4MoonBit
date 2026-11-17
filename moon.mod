name = "V1GreenSummer/paddleocr"

version = "0.1.1"

readme = "README.mbt.md"

repository = "https://github.com/V1GreenSummer/PaddleOCR4MoonBit"

license = "Apache-2.0"

keywords = [ "ocr", "paddleocr", "onnx", "image" ]

preferred_target = "wasm"

description = "PaddleOCR glue for MoonBit: JPEG/PNG/BMP decode, DBNet boxes, CTC decode, and native ONNX Runtime inference."

// image@0.5.0 pins zlib 0.4.10, which still drags in async 0.22.4. The direct
// zlib 0.4.12 dependency drops async from the graph; it is the version this
// module actually resolves.
import {
  "mizchi/zlib@0.4.12",
  "mizchi/image@0.5.0",
  "HuLunTunTao/moon-ort@0.1.1",
  "moonbitlang/x@0.5.7",
}

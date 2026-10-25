name = "V1GreenSummer/paddleocr"

version = "0.1.0"

readme = "README.mbt.md"

repository = "https://github.com/V1GreenSummer/PaddleOCR4MoonBit"

license = "Apache-2.0"

keywords = [ "ocr", "paddleocr", "onnx", "image" ]

preferred_target = "wasm"

description = "PaddleOCR glue for MoonBit: JPEG/PNG/BMP decode, DBNet boxes, CTC decode, and native ONNX Runtime inference."

// image@0.4.3 pins zlib 0.4.8, which still depends on async 0.16.6 and a
// moon.mod.json manifest this toolchain rejects. The direct zlib 0.4.10
// dependency is what the module actually resolves.
import {
  "mizchi/zlib@0.4.10",
  "mizchi/image@0.4.3",
  "HuLunTunTao/moon-ort@0.1.1",
  "moonbitlang/x@0.5.5",
}

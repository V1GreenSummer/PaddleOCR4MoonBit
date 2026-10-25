///|
fn main raise {
  let charset = @paddleocr.Charset::from_text("你\n好\n")
  let logits : Array[Float] = [0.0, 1.0, 0.0, 0.0, 0.0, 1.0]
  println(@paddleocr.ctc_greedy(logits, time=2, classes=3, charset~))
}

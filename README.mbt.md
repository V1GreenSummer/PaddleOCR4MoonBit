# paddleocr

[![CI](https://github.com/V1GreenSummer/PaddleOCR4MoonBit/actions/workflows/ci.yml/badge.svg)](https://github.com/V1GreenSummer/PaddleOCR4MoonBit/actions/workflows/ci.yml)

`V1GreenSummer/paddleocr` 0.1.0，Apache-2.0。把 PaddleOCR 的检测模型和识别模型接到 MoonBit：`mizchi/image` 解码图片，纯 MoonBit 做预处理和后处理，`HuLunTunTao/moon-ort` 在本机 CPU 上调用 ONNX Runtime。

`CXREN/moonocr` 是零依赖的纯 MoonBit 引擎，字符表只有数字和英文字母。这个包走另一条路：字符表、检测和识别都由外部 ONNX 模型决定，所以可以读中文。包本身不内置权重。

在一张 780×300 的 PNG 上（Noto Sans CJK SC 写的三行字），PP-OCRv4 中文检测 / 识别模型读出：

```
中国人民共和国
你好，世界。
MoonBit OCR 2026
```

对应检测框的分数是 0.994、0.994、0.990。第三行原文就是 `MoonBit OCR 2026`。空格来自识别模型多出来的那一个空格类，`Engine::load` 会把它补进字典。

## 安装

```sh
moon add V1GreenSummer/paddleocr@0.1.0
```

根包用于 wasm 侧的解码、预处理和后处理：

```mbt nocheck
///|
import {
  "V1GreenSummer/paddleocr",
}
```

native 侧推荐只 import 单入口包：

```mbt nocheck
///|
import {
  "V1GreenSummer/paddleocr/ocr",
}
```

## 最小可运行示例

不需要 ONNX Runtime 或模型：

```sh
moon run examples/ctc
```

输出：

```text
你好
```

它用 `Charset` + `ctc_greedy` 走一遍 CTC 解码。完整图片 OCR 见“命令行”。

## 流水线

```
JPEG / PNG / BMP
        │  mizchi/image
        ▼
      RGBA
        │
        ├─ 检测：长边 ≤ 960，两边对齐 32，NCHW BGR，ImageNet 归一化
        │        moon-ort → DB 概率图
        │        四连通域 → 最小面积矩形 → unclip → 透视裁正
        │
        └─ 裁正后的横条，高度 48，均值和标准差都是 0.5
                 moon-ort → CTC 贪心解码
                 ▼
               文本行
```

1. `sniff_raster` 看文件头，`decode_raster` 解成 RGBA8。JPEG 只接受 baseline。
2. 检测输入把长边限制在 `limit_side_len`（默认 960），短边按比例缩放，再把两边舍入到 32 的倍数，最小 32。双线性插值。像素先除以 255，再按 OpenCV 的 BGR 顺序做 ImageNet 归一化：通道 0 是蓝，均值 `(0.485, 0.456, 0.406)`，标准差 `(0.229, 0.224, 0.225)`。
3. 检测模型的第 0 个输出当成单通道概率图。`db_quads` 做四连通域，用像素块的凸包求最小面积矩形。短边小于 `min_size`（3）或平均分低于 `box_thresh`（0.6）的块丢掉。剩下的矩形按 `area * unclip_ratio / perimeter` 沿边外扩（`unclip_ratio` 默认 1.5，前景阈值 0.3）。`db_regions` 用一次连通域同时给出两种框；`db_boxes` 仍保留轴对齐外接矩形，给只需要正框的调用方。
4. 四边形按检测图到原图的比例映回去。`Rgba::warp` 做透视裁切，把四条边拉成横条。高宽比至少 1.5 的竖条再逆时针转 90°。外接矩形用来分行：后一个框与当前行在竖直方向的重叠不少于较短高度的一半时并进同一行，行内按 x 排序。同一行的文字直接拼接，中间不插入空格。
5. 识别输入把裁块缩到高度 48（模型若把高度轴标成定长，就用那个高度）。宽度按宽高比向上取整，默认不超过 320。模型的宽度轴若是定长，右侧用归一化后的 0 补齐。识别归一化是 `(x - 0.5) / 0.5`，三个通道相同，因此 RGB 与 BGR 在这一步等价。
6. CTC 类别 0 是 blank，不出现在字典里。类别 `k` 对应字典第 `k - 1` 行。连续相同的类别折成一个字。`Charset::from_text` 按文件原样解析；`Charset::ppocr` 在末尾没有空格时补上一行，对应官方 `use_space_char`。字典里没有的类别被丢掉。`ctc_decode` 把保留下来的字符的概率取平均，低于 `rec_thresh`（默认 0.5）的框不进入结果。

```mbt check
///|
test {
  let (width, height) = @paddleocr.limit_side_size(1000, 500, limit=960)
  inspect(width, content="960")
  inspect(height, content="480")
  let charset = @paddleocr.Charset::from_text("你\n好\n")
  let logits : Array[Float] = [0.0, 1.0, 0.0, 0.0, 0.0, 1.0]
  inspect(
    @paddleocr.ctc_greedy(logits, time=2, classes=3, charset~),
    content="你好",
  )
}
```

`1000×500` 的长边被收到 960，短边成 480，两边都是 32 的倍数。字典文件末尾的换行不会多出一个空类别。

## 目标平台

| 代码 | wasm | native |
| --- | --- | --- |
| 解码、缩放、归一化、连通域、分行、CTC | 可以单独测 | 可以 |
| `engine` 里的 ONNX 会话、`ocr` 单入口包，以及 `cmd/ocr` | 不编译 | Linux x86_64 CPU |

`moon-ort` 0.1.1 用 `dlopen` 加载 ONNX Runtime，要求 API 正好是 1.30.0。没有 WASM、JavaScript 或 GPU 后端。模块的 `preferred_target` 仍是 wasm，因为根包的前后处理可以在 wasm 上复用；真正认字要 `moon run --target native`。

## 仓库

```
moon.mod                         模块 V1GreenSummer/paddleocr
decode.mbt / rgba.mbt            PNG、JPEG、BMP → RGBA
preprocess.mbt                   检测 / 识别张量
detect.mbt                       概率图 → 框 → 行
ctc.mbt / page.mbt               字典、CTC、Page
error.mbt                        OcrError
engine/                          native：Engine、EngineOptions、Backend 和批处理
ocr/                             native 单入口：重导出 Engine 与结果/几何类型
examples/ctc/                    不依赖模型的 CTC 最小示例
cmd/ocr/                         native 可执行文件
```

GitHub: <https://github.com/V1GreenSummer/PaddleOCR4MoonBit>

依赖：`mizchi/image@0.4.3`、`mizchi/zlib@0.4.10`、`HuLunTunTao/moon-ort@0.1.1`、`moonbitlang/x@0.5.5`。直接写上 zlib 0.4.10，是因为 image 0.4.3 钉住的 zlib 0.4.8 还依赖一份当前工具链拒绝的 `moon.mod.json`。

## 第三方依赖与许可证

本项目代码以 Apache-2.0 发布（见根目录 `LICENSE`）。主要依赖和数据处理如下：

| 组件 | 许可证 | 说明 |
| --- | --- | --- |
| `mizchi/image` 0.4.3 | Apache-2.0 | PNG/JPEG/BMP 解码与缩放 |
| `mizchi/zlib` 0.4.10 | Apache-2.0 | `mizchi/image` 的 zlib 依赖 |
| `HuLunTunTao/moon-ort` 0.1.1 | MIT | ONNX Runtime 的 MoonBit 绑定 |
| `moonbitlang/x` 0.5.5 | Apache-2.0 | 文件读写 |
| ONNX Runtime 1.30.0 | MIT | 运行时共享库，不随仓库分发 |
| PaddleOCR / RapidOCR 模型 | Apache-2.0 | 上游模型权重，不随仓库分发 |

检测/识别模型来自 [PaddleOCR](https://github.com/PaddlePaddle/PaddleOCR)，ONNX 转换和模型列表由 [RapidOCR](https://github.com/RapidAI/RapidOCR) 提供。`samples/page.png` 是本项目生成的测试图，随项目以 Apache-2.0 发布。

## 准备运行时和模型

推理需要三样东西，它们都不进仓库（`models/` 和 `runtime/` 已忽略）：

- `libonnxruntime.so.1.30.0`。版本必须是 1.30.0，否则 moon-ort 报 API 不匹配。推荐从官方 release 下载 Linux x64 包：

  <https://github.com/microsoft/onnxruntime/releases/download/v1.30.0/onnxruntime-linux-x64-1.30.0.tgz>

  该 tarball 的 SHA256 是 `a5ed5a3cac51fbb2e90da632ae43d19212faaa20e76484e62bcb7c23ddb3b3fd`（与 `moon-ort` CI 使用的一致）。解压后使用 `lib/libonnxruntime.so.1.30.0`。也可以从 Python 包 `onnxruntime==1.30.0` 的 manylinux wheel 提取；本项目验证时使用的文件 SHA256 是 `c902c70b3003c0e99fada202f37478c515ae9bba7944c2b2abd0017bae0c82ed`。
- PP-OCRv4 中文检测、识别 ONNX。模型来自 PaddleOCR，RapidOCR 提供 ONNX 转换和[模型列表](https://rapidai.github.io/RapidOCRDocs/main/model_list/)。验证用的是：

  | 文件 | SHA256 |
  | --- | --- |
  | `ch_PP-OCRv4_det_infer.onnx` | `d2a7720d45a54257208b1e13e36a8479894cb74155a5efe29462512d42f49da9` |
  | `ch_PP-OCRv4_rec_infer.onnx` | `48fc40f24f6d2a207a2b1091d3437eb3cc3eb6b676dc3ef9c37384005483683b` |

- `ppocr_keys_v1.txt`：一行一个字符。文件本身通常不含空格。`Engine::load` 用 `Charset::ppocr` 读它，并在末尾补上 PP-OCR 的空格类。已经以空格结尾的字典不会再补第二次。验证时使用的字典 SHA256 是 `28b2362ad4ab2dc38769aa72feb535e3a9ddb3fd2a7585a05920e6393b1dc7f7`。

用环境变量或 `--library` 指出共享库：

```sh
export MOON_ORT_LIBRARY=/path/to/libonnxruntime.so.1.30.0
```

加载时 ONNX Runtime 会向 stderr 打印一批更高 API 版本不可用的探测信息。会话仍然建立在 1.30.0 上。

## 命令行

```sh
moon run --target native cmd/ocr -- page.png \
  --det ch_PP-OCRv4_det_infer.onnx \
  --rec ch_PP-OCRv4_rec_infer.onnx \
  --dict ppocr_keys_v1.txt \
  --boxes
```

| 参数 | 作用 |
| --- | --- |
| 位置参数 | 待识别的 JPEG、PNG 或 BMP |
| `--det` `--rec` `--dict` | 检测模型、识别模型、字典，三者都要 |
| `--library` | ONNX Runtime 共享库；缺省时读 `MOON_ORT_LIBRARY` |
| `--limit` | 检测长边上限，默认 960 |
| `--boxes` | 每个框一行：`x,y,width,height<TAB>检测分<TAB>识别置信度<TAB>text` |

不加 `--boxes` 时，`Page` 的每一行阅读顺序文本用换行接起来。坐标是四边形的外接矩形。上面那张样图在 `--boxes` 下是：

```
63,59,352,46	0.9941148446743899	0.9998255542346409	中国人民共和国
57,134,280,53	0.9936801729464608	0.9986610412597656	你好，世界。
60,219,444,41	0.989933144244093	0.9717656522989273	MoonBit OCR 2026
```

## 在代码里调用

native 侧推荐只 import 单入口包：

```mbt nocheck
///|
import {
  "V1GreenSummer/paddleocr/ocr",
}
```

应用侧保持一个 `Engine`，换图片时不必重新读字典或再加载 ONNX Runtime。`with_engine` 在成功和报错时都会关闭引擎；需要手动管理时用 `load` + `close`。`load` 读字典、补空格类，并在没传 `library` 时使用 `MOON_ORT_LIBRARY`。`recognize_file` 负责读图和解码。`RecognizeOptions::standard` 是 PP-OCRv4 的阈值；`with_*` 可以改检测长边、DB 阈值、`min_size`、识别宽度和置信度。`EngineOptions::standard` 控制 ONNX Runtime 线程数、图优化和识别批大小。

```mbt nocheck
let page = @ocr.with_engine(
  det=det_path,
  rec=rec_path,
  dict=dict_path,
  engine => {
    engine.recognize_file(image_path)
  },
)
println(page.render())
```

`with_engine` 返回回调的值；出错时同样会关闭引擎。线程数和批大小用 `EngineOptions` 设置：

```mbt nocheck
///|
let settings = @ocr.EngineOptions::standard()
  .with_intra_op_threads(4)
  .with_rec_batch_size(8)

///|
let engine = @ocr.Engine::load(
  det=det_path,
  rec=rec_path,
  dict=dict_path,
  options=settings,
)
```

需要分步控制时：

```mbt nocheck
let engine = @ocr.Engine::load(det=det_path, rec=rec_path, dict=dict_path)
let quads = engine.detect(image)                 // 只检测
let page = engine.recognize_quads(image, quads)  // 改框后识别
let raw = engine.recognize_regions(crops)        // 只识别已有裁块
engine.close()
```

`recognize_regions` 返回原始 `CtcText`，不会按 `rec_thresh` 过滤；`recognize_quads` 和 `recognize` 会过滤空文本和低置信度 span。`Engine::detect` 返回原图坐标下的旋转四边形。`recognize_quads` 会按阅读顺序分组、透视裁正，并在模型 batch 维可动态时把同宽 crop 合并推理。固定 batch 维为 1 的模型逐条识别；固定 batch > 1 的模型不在当前批处理路径内。

`Page` 保留每个 span 的 `quad`、`bounds`、`det_score`、`rec_confidence`；`Page::spans()` 展平所有 span，`Page::to_json_string()` 输出 JSON。内存里已有像素时用 `recognize` 或 `recognize_bytes`。省略 `options` 时用 `standard`。底层的 `Engine::open` 仍接受已经解析好的 `Charset`，不改字典内容。

native 包读每个模型的第 0 个输入和第 0 个输出，并要求它们是 float32。检测图的秩至少为 2，前面各维的乘积必须是 1，因此 `[1,1,H,W]`、`[1,H,W]`、`[H,W]` 都可以。识别输出是 `[T,C]` 或 `[1,T,C]`；动态 batch 模型可以是 `[N,T,C]`。

根包可以单独使用：

| 函数 | 作用 |
| --- | --- |
| `sniff_raster` / `decode_raster` | 识别容器并解成 `Rgba` |
| `Rgba::from_rgba` / `Rgba::crop` / `Rgba::warp` | 校验、裁剪，或把四边形透视成横条 |
| `limit_side_size` / `prepare_det` / `prepare_rec` | 检测缩放与两路归一化张量 |
| `RecognizeOptions::standard` / `with_*` | 检测长边、DB 阈值、`min_size`、识别宽度和置信度 |
| `db_quads` / `min_area_rect` / `unclip_quad` | 概率图上的旋转矩形 |
| `db_regions` / `db_boxes` / `map_det_box` / `group_lines` | 一次连通域给出两种框，或轴对齐框与阅读顺序 |
| `Charset::from_text` / `Charset::ppocr` / `ctc_decode` | 字典、CTC 和置信度 |
| `Page::text` / `Page::render` / `Page::spans` / `Page::to_json_string` | 阅读顺序文本、带框表格、展平 span 或 JSON |

native 侧额外提供：

| 函数 | 作用 |
| --- | --- |
| `Engine::detect` / `Engine::recognize_quads` / `Engine::recognize_regions` | 分步检测、改框后识别、只识别裁块 |
| `EngineOptions::standard` / `with_*` | 线程数、图优化、执行模式和识别批大小 |
| `Engine::with_scope` / `with_engine` | 成功或报错时自动 `close` |
| `Backend` / `recognize_with` / `recognize_quads_with` | 用自定义检测/识别函数替换 ONNX 后端，便于测试 |

错误是 `OcrError`，构造器是 `image`、`model`、`runtime`、`io`、`config`、`usage`。子错误变体在包外是只读的，调用方用这些构造器。

## 边界

- 识别用的是最小面积矩形外扩后的四边形，再透视裁正。`--boxes` 打印的是这个四边形的外接矩形。弯曲的一行仍会被收成一个矩形，邻行贴得很近时也会粘在一起。
- 竖排文字会转成横条。整行倒转 180° 时还没有方向分类模型，识别会按倒着的顺序读。
- 识别是每步取最大类别的 CTC，没有词典束搜索。同宽 crop 在动态 batch 模型上会合并成一次 session 调用。置信度低于 `rec_thresh`（默认 0.5）的框被丢掉；`recognize_regions` 不做这一步过滤。
- 能认哪些字取决于加载的识别模型和字典。`load` 只为 PP-OCR 补末尾空格类；别的模型继续用 `Engine::open` 和 `Charset::from_text`。
- 同一行里的多个框直接拼接，框与框之间不另插空格。空格只来自模型预测到的空格类。
- 识别批处理只在模型 batch 维是动态时启用；固定 batch 维为 1 的模型逐条识别。
- JPEG 只支持 baseline。自然场景的效果取决于检测模型；阈值沿用 Paddle 的默认值。
- `riantr/tesseract` 是一个 JSON 数据库，和 OCR 无关。

## 测试

```sh
moon test
moon test --target native
```

wasm 测试覆盖解码、预处理、连通域、最小面积矩形、透视裁切、CTC、空格类、`Page::render`、`Page` JSON 和 Options builders。native 另外检查：不存在的运行时库返回 `OcrError::Runtime`，缺字典时在打开运行时之前返回 `OcrError::Io`，无效 `EngineOptions` 返回 `OcrError::Config`，并用 fake `Backend` 检查分步流水线。

CI 配置在 `.github/workflows/ci.yml`，运行 `moon fmt --check`、`moon check --target all --deny-warn`、`moon test --deny-warn`、`moon test --target native --deny-warn` 和 `moon build --target native --deny-warn`。真实 ONNX Runtime 推理需要外部模型和共享库，不在 CI 中下载。

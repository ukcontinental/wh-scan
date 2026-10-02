# Benchmark

## 內容

| 檔案 | 用途 |
|---|---|
| `generate_dataset.py` + `cardgen/` + `render_cards.js` | 產生模擬「手機拍名片」的資料集（HTML 版型 → Chromium 渲染 → 傾斜、陰影、背景、模糊、JPEG） |
| `dataset/` | 預設資料集：45 人、63 張照片（其中 18 人有正反面），含標準答案 `ground_truth.json` |
| `make_inputs.py` | 建立一次跑分的輸入：選取順序、模擬 EXIF 拍攝時間（或不給）、顏色特徵、預先存在的通訊錄（含誘餌） |
| `score.py` | 計算規格第 22 節的指標 |
| `analyze_reviews.py` | 分析每個待確認欄位其實對或錯，以及是哪個訊號造成的 |
| `calibrate.py` | 信心分數與正確率的對照，並模擬不同門檻 |
| `run_all.sh` | 重跑所有可離線重現的設定 |
| `runs/proxy/` | AI 代理辨識結果與複核答案，可重播（見下方「代理測試」） |

所有跑分都呼叫與 App **同一套** Swift 核心（`cardcore-cli`），只替換兩個元件：
- Apple Vision OCR 換成 tesseract（Linux 沒有 Vision）。
- iPhone 通訊錄換成記憶體版本。

## 代理測試（沒有 API 金鑰時）

這次開發環境沒有 Anthropic API 金鑰，所以 AI 辨識用「代理」方式完成：
1. 由 Claude Opus 5.5 子代理依照與 App **相同的系統提示詞與 JSON Schema**，逐張讀圖並輸出 JSON（`runs/proxy/extractions/`）。
2. 流程發出的「第二意見」複核請求，也由子代理依照正式的複核提示詞作答（`runs/proxy/verify2/`）。
3. CLI 以 `--extractor replay:` 與 `--verifier replay:` 重播這些結果，其餘全部是正式程式碼。

這與正式 API 呼叫有幾個差異：
- 沒有結構化輸出的強制格式。
- 代理沒有拿到 OCR 文字。
- 複核由同等級模型完成。
- 時間與成本無法測量。

**準確度數字是估計值，有 API 金鑰後必須用正式模式重測。**

## 用正式 API 跑分

```bash
export ANTHROPIC_API_KEY=...
python3 make_inputs.py --out runs/claude-ts --scenario timestamps
../Packages/CardCore/.build/release/cardcore-cli run --photos runs/claude-ts/photos.json --extractor claude --verify \
  --save-extractions runs/claude-ts/extractions --existing runs/claude-ts/existing_contacts.json --out runs/claude-ts/run.json
python3 score.py runs/claude-ts/run.json --expectations runs/claude-ts/expectations.json
```

這會量到實際的每張時間與 API 成本，摘要中會有 `cost_usd`。

## 用你的真實名片驗收

最快的方式（不需要準備標準答案）：

```bash
export ANTHROPIC_API_KEY=...
python3 run_folder.py ~/my-card-photos --out runs/my-cards
```

會產生 `runs/my-cards/report.md`：每位聯絡人的每個欄位、信心值、是否自動寫入，以及待確認的問題。對照名片逐一核對即可。

要計算正式指標時，再照以下步驟準備標準答案：

1. 把名片照片（正反面照實際拍法）放進 `real/images/`。
2. 複製 `dataset/ground_truth.json` 的格式，為每個人填寫正確答案。不用填 `printed` 等額外欄位。
3. 參考 `make_inputs.py` 產生 `photos.json`。若要測正反面配對，請保留原始 EXIF：從 iPhone 用 AirDrop「選項 → 所有照片資料」傳出。
4. 用上面的正式 API 指令跑分，評分時加上 `--dataset real`。

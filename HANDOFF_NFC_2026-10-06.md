# 交接日誌：NFC 名片批次匯入 iPhone 聯絡人

- 日期：2026-10-06
- 分支：`claude/zealous-thompson-5f6q83`（儲存庫 `ukcontinental/wh-scan`，未開 PR）
- 工作期間：2026-10-01 ～ 2026-10-06
- 主要目錄：`CardImport/`

## 1. 做了什麼

### 需求
使用者在手機上用 NFC 貼紙觸發，批次把名片照片轉成 iPhone 聯絡人。
優先順序：辨識正確率 ＞ 少人工 ＞ 少步驟 ＞ 速度 ＞ 成本。
真正的指標是「完全不用人碰就正確建立的聯絡人數」。

### 已完成的成果

| 項目 | 位置 | 狀態 |
|---|---|---|
| 技術分析與架構決策（iOS 限制、UX、方案比較、JSON Schema、信心度與審核規則、正反面配對、去重、批次架構） | `CardImport/docs/01-technical-analysis.md` | 完成 |
| 辨識核心 CardCore（Swift 套件） | `CardImport/Packages/CardCore/` | 完成；71 個單元測試在 Linux 與 macOS CI 通過 |
| iOS App（SwiftUI）＋照片分享延伸 | `CardImport/App/` | 完成；GitHub Actions 的 Mac 上以 Xcode 26.3 編譯成功並在模擬器截圖 |
| NFC 入口 | App Intent「匯入名片」＋捷徑自動化 | 完成（未在實機測試） |
| 一鍵設定與免費 Apple ID 版 | `CardImport/App/setup.sh`、`project-free.yml` | 完成；CI 編譯通過 |
| 擷取 API 的 JSON Schema | `CardImport/schema/` | 完成 |
| 基準測試工具與合成資料集 | `CardImport/benchmark/` | 完成 |
| 基準測試的完整執行結果 | `CardImport/benchmark/runs/` | 已收錄（含各次 `run.json`、批次狀態、分數） |
| 驗收報告（規格第 33 節指標） | `CardImport/docs/02-acceptance-report.md` | 完成 |
| App 截圖 | `CardImport/docs/screenshots/` | CI 自動更新 |
| 安裝說明 | `CardImport/App/README.md` | 已改為免費帳號也能照做 |
| 開發用暫存腳本 | `CardImport/benchmark/session-scratch/` | 已收錄，供追溯 |
| CI | `.github/workflows/cardimport-ios.yml` | 核心測試、App 編譯、截圖、免費版編譯 |

### 架構（選定方案 D：手機 OCR ＋ Claude 視覺擷取 ＋ 第二意見複核）
1. **入口：** NFC 捷徑或 App 內選照片；付費帳號版另有「照片 → 分享」。
2. **前處理：** Apple Vision 偵測名片邊緣、校正透視、OCR。
3. **擷取：** Claude（預設 `claude-opus-5-5`）以結構化輸出回傳每個欄位與信心度。
4. **驗證：** 格式驗證器加上 OCR 交叉比對，算出每個欄位的信心度。
5. **複核：** 有疑問的欄位交給第二個模型；仍有疑問才進待確認清單，而且只問那一個欄位。
6. **配對與去重：** 依內容與拍攝時間配對正反面，再與 iPhone 通訊錄比對。
7. **批次：** 單張失敗不影響整批；當機後可續跑且不會重複建立；保留處理紀錄。

### 修正紀錄重點
- 獨立程式碼審查找到 14 個問題，全部修正並補上回歸測試。例如連點兩下會建兩個聯絡人、當機續跑會重複建立、改正電話時被誤加 +1。
- CI 的截圖提交步驟原本會在兩次執行互搶時失敗，已改為自動重試。

## 2. 目前結論

### 準確度（合成資料集，模擬手機拍攝）
保留集從未拿來調整參數，最能代表真實表現。

| 指標 | 開發集（45 人／63 張） | 保留集（30 人／42 張） |
|---|---|---|
| 免人工即完全正確 | 93.3% | 86.7% |
| 人工介入率 | 6.7% | 6.7% |
| 錯誤自動存檔率 | 0% | 3.3% |
| 正反面配對 | 18/18 | 12/12 |
| 去重判斷 | 6/6 | 6/6 |

- 保留集第一次跑的結果是 76.7% 全對、10% 錯存，修正後才是上表數字。
- 剩下的一個錯存：把 Logo 上的「HEBANG BANK」當成英文公司名。
- 沒有拍攝時間時配對率下降，但不會配錯。
- 只用手機 OCR 加規則的免費模式，約一半會存錯。所以這個模式改用嚴格門檻，幾乎全部送人工確認。

### 成本與速度（估計，未實測）
- 每張照片約 US$0.05–0.12，20 張約 US$1–2.5。
- 4 張並行時，20 張約 1–2 分鐘。

### 帳號限制
- 免費 Apple ID 不能可靠地使用 App Group，所以免費版沒有「照片 → 分享」入口。NFC 與 App 內選照片照常可用。
- 免費帳號安裝的 App 每 7 天要用 Mac 重新安裝一次。
- 寫入聯絡人「備註」欄位需要 Apple 核准的特殊權限，要付費帳號申請；在那之前語音備註存在 App 內。

### 關於 QB 財務檔
本工作階段沒有任何 QuickBooks（QB）匯出檔：使用者沒有上傳，程式也沒有產生或下載。
已搜尋整個容器（含上傳資料夾與暫存區），沒有 `.qbo`、`.qbw`、`.iif`、`.ofx` 等檔案。
因此沒有檔案需要排除或另外提供下載。

## 3. 未結事項

| 事項 | 說明 |
|---|---|
| 真實名片未測 | 所有數字都來自合成資料集 |
| 正式 Claude API 未呼叫 | 環境沒有 API 金鑰；擷取與複核由子代理代為判讀（`runs/proxy`、`runs/holdout_proxy`） |
| iPhone 實機未測 | Apple Vision OCR、通訊錄寫入、NFC、分享延伸都只在模擬器或程式層測過 |
| 處理時間與 API 成本未實測 | 目前只有估計值 |
| Logo 文字被當公司名 | 保留集唯一的錯存案例，尚未修正 |
| 使用者安裝進度 | 已給第 1 步（下載程式碼並執行 `setup.sh`），等待使用者回報結果 |

## 4. 下一步

1. **完成安裝。** 照 `CardImport/App/README.md` 第 1～4 步做。目前停在第 1 步：在 Mac 終端機執行下面兩組指令，然後回報 Xcode 是否打開。
   ```bash
   cd ~/Desktop
   git clone -b claude/zealous-thompson-5f6q83 https://github.com/ukcontinental/wh-scan.git
   cd ~/Desktop/wh-scan/CardImport/App
   ./setup.sh
   ```
2. **Xcode 簽署並裝到 iPhone。** 登入 Apple ID、選 Personal Team、開啟 iPhone 開發者模式、信任開發者憑證。
3. **第一次開 App。** 貼上 Anthropic API 金鑰、允許完整取用聯絡人、在「捷徑」設定 NFC 自動化。
4. **實測真實名片。** 拍 20～30 張不同類型的名片，在 App 匯入，記下錯誤與待確認項目。
5. **用真 API 跑基準。** 在雲端環境設定加入 `ANTHROPIC_API_KEY` 後開新工作階段，執行：
   ```bash
   cd CardImport/Packages/CardCore && swift build -c release && cd ../../benchmark
   python3 run_folder.py ~/my-card-photos --out runs/my-cards
   ```
   結果在 `runs/my-cards/report.md`。與目前的代理結果比較，並實測時間與成本。
6. **依實測結果調整。** 優先處理錯存案例（例如 Logo 文字），再降低人工介入。
7. **（選用）長期使用。** 若要免除每 7 天重裝並使用分享入口，需付費開發者帳號，改用 `setup.sh` 的付費選項。

## 5. 重現方式

| 目的 | 指令 |
|---|---|
| 核心單元測試（需 Swift 5.9+） | `cd CardImport/Packages/CardCore && swift test` |
| 重新產生開發集 | `python3 CardImport/benchmark/generate_dataset.py` |
| 重新產生保留集 | `python3 CardImport/benchmark/generate_dataset.py --people 30 --seed 4242 --out CardImport/benchmark/dataset_holdout` |
| 重跑全部基準與評分 | `CardImport/benchmark/run_all.sh` |
| 對一個照片資料夾跑完整流程 | `python3 CardImport/benchmark/run_folder.py <資料夾> --out <輸出資料夾>`（需先 `swift build -c release`） |

未收錄的檔案都可以重新產生：
- 編譯快取（`.build/`、`__pycache__/`）
- 名片的乾淨渲染圖（`dataset*/clean/`）
- 約 90MB 的除錯裁切截圖

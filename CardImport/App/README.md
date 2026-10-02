# 名片匯入 iOS App：安裝到你的 iPhone

需要：一台 Mac（Xcode 16 以上，建議 Xcode 26）、你的 iPhone（iOS 17 以上）、Apple ID。

## 1. 產生 Xcode 專案

```bash
brew install xcodegen
cd CardImport/App
xcodegen
open CardImport.xcodeproj
```

## 2. 改成你自己的識別碼（一次）

打開 `project.yml`，改這三個值後重新執行 `xcodegen`：

| 設定 | 範例 |
|---|---|
| `bundleIdPrefix` 與兩個 `PRODUCT_BUNDLE_IDENTIFIER` | `com.yourname` |
| `APP_GROUP_ID` | `group.com.yourname.cardimport` |
| `DEVELOPMENT_TEAM` | 你的 Team ID（Xcode → Settings → Accounts 可看到） |

在 Xcode 的 **Signing & Capabilities**，確認兩個 target（CardImport、CardImportShare）都勾了同一個 App Group。

## 3. 裝到 iPhone

1. iPhone 用線接上 Mac，或在同一個 Wi-Fi 下配對。
2. 選擇 CardImport scheme 和你的 iPhone，按 ▶︎。
3. 第一次執行時，在 iPhone 的「設定 → 一般 → VPN 與裝置管理」信任你的開發者憑證。

使用免費 Apple ID 安裝的 App，7 天後需要重新安裝。付費開發者帳號（US$99/年）可以用 TestFlight 長期使用。

## 4. 第一次打開 App

1. 貼上 Anthropic API 金鑰：到 console.anthropic.com → API Keys 建立。
2. 允許「聯絡人」，請選完整取用，才能檢查重複聯絡人。
3. 設定 NFC（選用）：
   1. 打開「捷徑」→「自動化」→「＋」→「NFC」→ 掃描貼紙。
   2. 動作選「匯入名片」。
   3. 選「立即執行」，並關閉「執行時通知」。

## 5. 使用

- **NFC**：碰貼紙 → 勾選名片照片 → 按「加入」→ 等完成畫面。
- **照片 App**：選取多張 → 分享 → 名片匯入。
- **App 內**：按「選擇名片照片」。

## 選用：寫入聯絡人「備註」

Apple 規定寫入 `note` 欄位需要特殊權限 `com.apple.developer.contacts.notes`，需付費開發者帳號向 Apple 申請。

1. 取得核准後，在 entitlements 加入該權限。
2. 在 App「設定」打開「可寫入備註欄位」。

在那之前，語音備註會存在 App 內。

## 疑難排解

| 狀況 | 處理 |
|---|---|
| 「需要 API 金鑰」 | 到設定貼上金鑰；金鑰無效時完成畫面會顯示紅字 |
| 斷網 | 批次會暫停，恢復網路後打開 App 自動繼續，不會重複建立 |
| 分享延伸沒有聯絡人權限 | 延伸只會先辨識，下次打開 App 時自動寫入 |

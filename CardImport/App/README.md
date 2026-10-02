# 名片匯入 iOS App：安裝到你的 iPhone

需要：一台 Mac（Xcode 16 以上，建議 Xcode 26）、你的 iPhone（iOS 17 以上）、Apple ID（免費的也可以）。

## 1. 下載程式碼

打開 Mac 的「終端機」，貼上：

```bash
cd ~/Desktop
git clone -b claude/zealous-thompson-5f6q83 https://github.com/ukcontinental/wh-scan.git
```

## 2. 產生 Xcode 專案

```bash
cd ~/Desktop/wh-scan/CardImport/App
./setup.sh
```

腳本會問兩件事，然後自動打開 Xcode：

1. 一個英文暱稱，用來組成 App 的唯一識別碼。
2. 有沒有付費開發者帳號。

| 帳號 | 包含的功能 |
|---|---|
| 免費 Apple ID | App 本體、NFC 捷徑、App 內選照片 |
| 付費開發者帳號 | 以上全部，再加上「照片 → 分享 → 名片匯入」 |

免費帳號不能可靠地使用 App Group，所以免費版不含分享延伸。

## 3. 裝到 iPhone

1. 在 Xcode 選 **Settings → Accounts**，按左下角「＋」登入你的 Apple ID。
2. 在左側點最上面的 **CardImport** 專案，選 target **CardImport** → **Signing & Capabilities**。
3. **Team** 選你的名字（Personal Team）。
4. iPhone 用線接上 Mac，在 iPhone 上按「信任這部電腦」。
5. 在 iPhone 打開「設定 → 隱私權與安全性 → 開發者模式」，開啟後重新開機。
6. Xcode 上方的裝置選單選你的 iPhone，按 ▶︎。
7. 第一次會顯示「未受信任的開發者」。到 iPhone「設定 → 一般 → VPN 與裝置管理」，點你的 Apple ID → 信任。
8. 再按一次 ▶︎。

用免費 Apple ID 安裝的 App，7 天後會打不開。到時候接上 Mac 再按一次 ▶︎ 即可，資料會保留。

## 4. 第一次打開 App

1. 貼上 Anthropic API 金鑰：到 console.anthropic.com → API Keys 建立。
2. 允許「聯絡人」，請選完整取用，才能檢查重複聯絡人。
3. 設定 NFC（選用）：
   1. 打開「捷徑」→「自動化」→「＋」→「NFC」→ 掃描貼紙。
   2. 動作選「匯入名片」。
   3. 選「立即執行」，並關閉「執行時通知」。

## 5. 使用

- **NFC**：碰貼紙 → 勾選名片照片 → 按「加入」→ 等完成畫面。
- **照片 App**（付費帳號版）：選取多張 → 分享 → 名片匯入。
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

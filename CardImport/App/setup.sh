#!/bin/bash
# 一次性設定：產生 Xcode 專案（填入你自己的識別碼）並打開它。
# 用法：在「終端機」執行  ./setup.sh
set -e
cd "$(dirname "$0")"

echo "== 名片匯入：產生 Xcode 專案 =="
echo
echo "1) 請輸入一個英文暱稱，用來組成這個 App 的唯一識別碼。"
echo "   只能用小寫英文字母和數字，例如 amy2026。"
while true; do
  read -r -p "   暱稱：" NICK
  if [[ "$NICK" =~ ^[a-z][a-z0-9]{2,30}$ ]]; then break; fi
  echo "   格式不對：請用 3 個字以上、小寫英文字母開頭，只含英文字母和數字。"
done
echo
read -r -p "2) 你有付費的 Apple 開發者帳號（每年 US\$99）嗎？[y/N] " PAID
echo

if ! command -v xcodegen >/dev/null 2>&1; then
  if ! command -v brew >/dev/null 2>&1; then
    echo "需要先安裝 Homebrew。請到 https://brew.sh 複製那一行安裝指令，貼到終端機執行，"
    echo "完成後關掉終端機再開一次，然後重新執行 ./setup.sh"
    exit 1
  fi
  echo "安裝 XcodeGen（只需一次）…"
  brew install xcodegen
fi

if [[ "$PAID" =~ ^[Yy] ]]; then
  SPEC=project.yml
  echo "使用完整版（含「照片 → 分享 → 名片匯入」）。"
else
  SPEC=project-free.yml
  echo "使用免費 Apple ID 版（App 本體 + NFC 捷徑；不含「照片 → 分享」）。"
fi

sed "s/com\.example/com.$NICK/g" "$SPEC" > project.local.yml
xcodegen generate --spec project.local.yml --project . --quiet
echo
echo "完成！App 識別碼：com.$NICK.cardimport"
echo "正在打開 Xcode…"
open CardImport.xcodeproj

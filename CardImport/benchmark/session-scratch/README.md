# 工作階段暫存腳本（2026-10-01 ～ 10-06）

這些是開發時用過的一次性腳本和紀錄，保留下來以便追溯 `runs/` 裡的結果是怎麼產生的。
正式流程不需要它們；重跑基準測試請用上一層的 `run_all.sh`。

| 檔案 | 用途 |
|---|---|
| `gen.py`、`cardjson.py`、`h.py` | 開發集「代理擷取」：沒有 API 金鑰時，由子代理看圖後用這些輔助函式寫出 `runs/proxy/extractions/*.json`（格式同 Claude 擷取 API 的 JSON Schema） |
| `proxy-dev-agentB/`、`proxy-dev-agent_b3/` | 同上，另外兩個子代理分批寫的開發集擷取 |
| `holdout-proxy/` | 保留集代理擷取的輔助腳本，輸出到 `runs/holdout_proxy/extractions/` |
| `t.js` | 測試 Chromium 能否正確渲染中文與直書文字 |
| `gen.log`、`gen2.log`、`gen3.log` | 產生合成名片資料集時的輸出紀錄 |
| `a.md5`、`b.md5` | 兩次產生資料集的圖片雜湊，用來確認資料集可重現 |

腳本裡的輸出路徑是開發環境的絕對路徑（`/home/user/wh-scan/...`），在別處執行前請先修改。
除錯用的裁切截圖（約 90MB）沒有收錄；它們只是資料集圖片的局部放大，可隨時重新產生。

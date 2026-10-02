#!/usr/bin/env python3
"""Run the real pipeline on a folder of your own card photos and get a readable report — no ground truth needed.

  export ANTHROPIC_API_KEY=...
  python3 run_folder.py ~/cards-test --out runs/my-cards

Produces runs/my-cards/report.md: one section per detected person with every field, its confidence, what was written
automatically, and what would be asked. Check it against the cards by eye; mark anything wrong. EXIF capture times are
read from the files (AirDrop with "All Photos Data" keeps them).
"""
import argparse, json, os, subprocess, sys
from datetime import datetime
from PIL import Image, ExifTags
sys.path.insert(0, os.path.dirname(__file__))
from make_inputs import histogram

def capture_time(path):
    try:
        exif = Image.open(path)._getexif() or {}
        tags = {ExifTags.TAGS.get(k, k): v for k, v in exif.items()}
        s = tags.get("DateTimeOriginal") or tags.get("DateTime")
        return datetime.strptime(s, "%Y:%m:%d %H:%M:%S").timestamp() if s else None
    except Exception:
        return None

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("folder")
    ap.add_argument("--out", required=True)
    ap.add_argument("--cli", default=os.path.join(os.path.dirname(__file__), "../Packages/CardCore/.build/release/cardcore-cli"))
    ap.add_argument("--region", default="CA")
    ap.add_argument("--no-verify", action="store_true")
    ap.add_argument("--extractor", default="claude", help="claude (default) or heuristic (offline smoke test)")
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    files = sorted(f for f in os.listdir(a.folder) if f.lower().endswith((".jpg", ".jpeg", ".png", ".heic")))
    photos = []
    for i, f in enumerate(files):
        p = os.path.abspath(os.path.join(a.folder, f))
        if f.lower().endswith(".heic"):
            jpg = os.path.join(a.out, os.path.splitext(f)[0] + ".jpg")
            subprocess.run(["convert", p, jpg], check=True)   # ImageMagick with HEIC support, or convert on the Mac first
            p = jpg
        photos.append({"id": os.path.splitext(f)[0], "file": p, "captureTime": capture_time(p), "colorHistogram": histogram(p)})
    json.dump(photos, open(os.path.join(a.out, "photos.json"), "w"), indent=1)
    cmd = [a.cli, "run", "--photos", os.path.join(a.out, "photos.json"), "--extractor", a.extractor, "--region", a.region,
           "--ocr", "tesseract", "--save-extractions", os.path.join(a.out, "extractions"), "--out", os.path.join(a.out, "run.json"),
           "--state-dir", os.path.join(a.out, "state")]
    if not a.no_verify and a.extractor == "claude":
        cmd.append("--verify")
    subprocess.run(cmd, check=True)
    run = json.load(open(os.path.join(a.out, "run.json")))
    s = run["summary"]
    lines = [f"# 名片匯入結果：{len(files)} 張照片", "",
             f"偵測到 {s['peopleDetected']} 人；新建 {s['created']}、更新 {s['updated']}、已存在 {s['alreadyExisted']}；"
             f"待確認 {s['openReviewItems']} 項；失敗照片 {s['failedPhotos']}；成本 US${s['costUSD']:.3f}；耗時 {run['wallSeconds']:.0f} 秒", ""]
    review = {}
    for r in run["review"]:
        review.setdefault(r["personID"], []).append(r)
    for p in run["people"]:
        if p["status"] == "ignored":
            continue
        d = p.get("fullDraft") or {}
        lines += [f"## {', '.join(p['photoIDs'])} — {p['status']}", "", "| 欄位 | 值 | 信心 | 自動寫入 |", "|---|---|---|---|"]
        written = json.dumps(p.get("draft") or {}, ensure_ascii=False)
        def row(label, v, c, key=None):
            probe = json.dumps(key or v, ensure_ascii=False)[1:-1]
            lines.append(f"| {label} | {v} | {c:.2f} | {'是' if probe in written else '否'} |")
        for k, label in [("givenName", "名"), ("familyName", "姓"), ("cjkName", "中文姓名"), ("company", "公司"), ("companyCJK", "公司（中）"),
                         ("jobTitle", "職稱"), ("jobTitleCJK", "職稱（中）"), ("department", "部門"), ("departmentCJK", "部門（中）")]:
            if d.get(k): row(label, d[k]["value"], d[k]["confidence"])
        for ph in d.get("phones", []): row(f"電話 {ph['kind']}", ph["e164"] + (f" ext {ph['extensionNumber']}" if ph.get("extensionNumber") else ""), ph["confidence"], key=ph["e164"])
        for e in d.get("emails", []): row("Email", e["value"], e["confidence"])
        for w in d.get("websites", []): row("網站", w["value"], w["confidence"])
        for ad in d.get("addresses", []): row("地址", ad.get("formatted") or ad.get("street") or "", ad["confidence"])
        for it in review.get(p["id"], []):
            lines.append(f"\n- 待確認：{it['question']} 候選：{' / '.join(it['candidates'])}")
        lines.append("")
    open(os.path.join(a.out, "report.md"), "w").write("\n".join(lines))
    print("report:", os.path.join(a.out, "report.md"))

if __name__ == "__main__":
    main()

#!/bin/bash
# Re-runs every offline-reproducible benchmark configuration and prints the headline metrics.
set -e
cd "$(dirname "$0")"
CLI=${CARDCORE_CLI:-../Packages/CardCore/.build/release/cardcore-cli}
run() { # name extractor scenario [verifier]
  d=runs/$1; python3 make_inputs.py --out $d --scenario $3 >/dev/null 2>&1
  rm -rf $d/state
  $CLI run --photos $d/photos.json --extractor $2 ${4:+--verifier $4} --ocr tesseract --ocr-cache runs/ocr-cache \
       --existing $d/existing_contacts.json --out $d/run.json --state-dir $d/state 2>/dev/null
  python3 score.py $d/run.json --expectations $d/expectations.json --json-out $d/score.json > /dev/null
  python3 - "$d/score.json" <<'PY'
import json,sys
r=json.load(open(sys.argv[1])); c=r["contacts"]; p=r["pairing"]
fa=r["field_accuracy"]
auto=sum(v["correct"] for v in fa.values()); wrong=sum(v["wrong"] for v in fa.values())
print(f'{sys.argv[1].split("/")[1]:<24} people={r["pipeline_people"]:>2}/{r["gt_people"]} perfect={c["perfect_without_human_%"]:>5}% '
      f'intervention={c["human_intervention_rate_%"]:>5}% wrongAuto={c["wrong_auto_save_rate_%"]:>5}% '
      f'fieldAutoAcc={100*auto/max(1,auto+wrong):.1f}% pairing={p["correctly_grouped"]}/{p["two_sided_people"]} merges={p["wrong_merges"]} '
      f'reviews={c["open_review_items"]} dedup={r["dedup_ok"]} leaks={c["distractor_leaks"]}')
PY
}
python3 - <<'PY'
import json,glob
a={}
for f in sorted(glob.glob('runs/proxy/verify[2-9]/answers_*.json')): a.update(json.load(open(f)))
json.dump(a,open('runs/proxy/answers_final.json','w'),ensure_ascii=False,indent=1)
PY
run heuristic-ts heuristic timestamps
run proxy-noverify-ts replay:runs/proxy/extractions timestamps
run proxy-timestamps replay:runs/proxy/extractions timestamps replay:runs/proxy/answers_final.json
run proxy-no-timestamps replay:runs/proxy/extractions no-timestamps replay:runs/proxy/answers_final.json

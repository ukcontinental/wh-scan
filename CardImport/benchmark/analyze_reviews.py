#!/usr/bin/env python3
"""Why did fields go to review? For each held field: was the first candidate actually correct, and which signals fired."""
import json, sys, re, unicodedata
from collections import Counter
sys.path.insert(0, ".")
from score import norm, cjk_norm, host, gt_fields

run = json.load(open(sys.argv[1]))
gt = json.load(open("dataset/ground_truth.json"))
pp = {p["id"]: p["person_id"] for p in gt["photos"]}
people = {p["id"]: p for p in gt["people"]}
recs = {r["id"]: r for r in run["people"]}

def is_correct(field, value, person):
    f = gt_fields(person)
    vals = set().union(*f.values()) if f else set()
    cands = {norm(value), cjk_norm(value), host(value), value.lower()}
    digits = re.sub(r"\D", "", value)
    if field.startswith("phone"):
        return any(digits and v.lstrip("+").split("x")[0].endswith(digits[-9:]) for v in vals if v.startswith("+"))
    if field.startswith("address"):
        d = "".join(sorted(set(re.findall(r"\d+", unicodedata.normalize("NFKC", value)))))
        return any(d and d == v for v in vals)
    return bool(cands & vals) or any(norm(value) and norm(value) in v for v in vals)

stats = Counter(); sig = Counter(); examples = []
for it in run["review"]:
    if it["resolved"] or it["kind"] != "field":
        continue
    r = recs[it["personID"]]
    gids = {pp[i] for i in r["photoIDs"]}
    if len(gids) != 1:
        stats["mixed_person"] += 1; continue
    person = people[gids.pop()]
    value = it["candidates"][0]
    ok = is_correct(it["field"], value, person)
    stats["correct" if ok else "wrong"] += 1
    # find signals in fullDraft
    d = r.get("fullDraft") or {}
    s = []
    for key in ["givenName","familyName","cjkName","company","companyCJK","jobTitle","jobTitleCJK","department"]:
        v = d.get(key)
        if v and v["value"] == value: s = v["signals"]; conf = v["confidence"]
    for lst in ["phones","emails","websites"]:
        for v in d.get(lst, []):
            if v.get("printed", v.get("value")) == value: s = v["signals"]; conf = v["confidence"]
    for a in d.get("addresses", []):
        if (a.get("formatted") or a.get("street")) == value: s = a["signals"]; conf = a["confidence"]
    for x in s:
        sig[(ok, re.sub(r"[:].*", "", x) if x.startswith(("model", "repaired_from", "kind_from")) else x)] += 1
    if len(examples) < 400:
        examples.append((ok, it["field"].split(":")[0], value[:50], s))
print(stats)
print("signals among CORRECT held values:")
for (ok, k), n in sorted(sig.items(), key=lambda x: -x[1]):
    if ok: print(f"  {n:3d} {k}")
print("signals among WRONG held values:")
for (ok, k), n in sorted(sig.items(), key=lambda x: -x[1]):
    if not ok: print(f"  {n:3d} {k}")
print("\nWRONG held examples:")
for e in examples:
    if not e[0]: print("  ", e[1], "|", e[2], "|", e[3])
print("\nfirst correct-held examples:")
for e in [e for e in examples if e[0]][:25]: print("  ", e[1], "|", e[2], "|", e[3])

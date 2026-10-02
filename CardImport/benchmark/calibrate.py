#!/usr/bin/env python3
"""Confidence calibration: for every field in every (pure) person's pre-policy draft, final confidence vs correctness.
Simulates auto-accept thresholds → human-intervention rate and wrong-auto-save rate (person level)."""
import json, sys, re, unicodedata
from collections import defaultdict
sys.path.insert(0, ".")
from score import norm, cjk_norm, host, gt_fields

run = json.load(open(sys.argv[1]))
gt = json.load(open("dataset/ground_truth.json"))
pp = {p["id"]: p["person_id"] for p in gt["photos"]}
people = {p["id"]: p for p in gt["people"]}

CRIT = {"name", "phone", "email"}
def fields(d):
    out = []
    for k, grp in [("givenName", "name"), ("familyName", "name"), ("cjkName", "name"), ("company", "company"), ("companyCJK", "company"),
                   ("jobTitle", "title"), ("jobTitleCJK", "title"), ("department", "dept"), ("departmentCJK", "dept")]:
        v = d.get(k)
        if v: out.append((grp, k, v["value"], v["confidence"]))
    for p in d.get("phones", []): out.append(("phone", "phone", p["e164"] + ("x" + p["extensionNumber"] if p.get("extensionNumber") else ""), p["confidence"]))
    for e in d.get("emails", []): out.append(("email", "email", e["value"], e["confidence"]))
    for w in d.get("websites", []): out.append(("website", "website", w["value"], w["confidence"]))
    for a in d.get("addresses", []): out.append(("address", "address", a.get("formatted") or a.get("street") or "", a["confidence"]))
    return out

def correct(grp, k, value, person):
    g = gt_fields(person)
    n = person["name"]
    if k == "givenName": return bool(n["given"]) and norm(value) == norm(n["given"])
    if k == "familyName": return bool(n["family"]) and norm(value) == norm(n["family"])
    if k == "cjkName": return bool(n["cjk_full"]) and cjk_norm(value) == cjk_norm(n["cjk_full"])
    if grp == "company": return cjk_norm(value) in {cjk_norm(x) for x in [person["company"], person["company_cjk"]] if x}
    if grp == "title": return cjk_norm(value) in {cjk_norm(x) for x in [person["job_title"], person["job_title_cjk"]] if x}
    if grp == "dept": return cjk_norm(value) in {cjk_norm(x) for x in [person.get("department"), person.get("department_cjk")] if x}
    if grp == "phone": return any(value.split("x")[0] == p["number"] for p in person["phones"])
    if grp == "email": return value.lower() in {e["address"].lower() for e in person["emails"]}
    if grp == "website": return host(value) in {host(w["url"]) for w in person["websites"]}
    if grp == "address":
        d = "".join(sorted(set(re.findall(r"\d+", unicodedata.normalize("NFKC", value)))))
        keys = set()
        for a in person["addresses"]:
            for t in [a.get("formatted"), (a.get("alt") or {}).get("formatted") if isinstance(a.get("alt"), dict) else a.get("alt")]:
                if t: keys.add("".join(sorted(set(re.findall(r"\d+", unicodedata.normalize("NFKC", t))))))
        return d in keys
    return False

rows = []  # (person, grp, conf, ok)
for r in run["people"]:
    if r["status"] == "ignored": continue
    g = {pp[i] for i in r["photoIDs"]}
    if len(g) != 1: continue
    person = people[g.pop()]
    for grp, k, v, c in fields(r.get("fullDraft") or {}):
        rows.append((r["id"], grp, c, correct(grp, k, v, person)))

print(f"{len(rows)} fields; overall correct {sum(x[3] for x in rows)}")
bins = [0, .5, .7, .8, .85, .9, .95, .98, 1.01]
print("confidence bin   n   correct%")
for lo, hi in zip(bins, bins[1:]):
    b = [x for x in rows if lo <= x[2] < hi]
    if b: print(f"  {lo:.2f}-{min(hi,1):.2f}  {len(b):4d}   {100*sum(x[3] for x in b)/len(b):5.1f}")
persons = sorted({x[0] for x in rows})
print("\nthreshold sim (crit, other) → intervention% , wrongAuto% (person level, before second opinion)")
for crit in [0.80, 0.85, 0.88, 0.90, 0.93]:
    for other in [0.70, 0.75, 0.80, 0.85]:
        inter = wrong = 0
        for p in persons:
            fs = [x for x in rows if x[0] == p]
            held = [x for x in fs if x[2] < (crit if x[1] in CRIT else other)]
            auto = [x for x in fs if x not in held]
            inter += bool(held); wrong += any(not x[3] for x in auto)
        print(f"  {crit:.2f} {other:.2f} → {100*inter/len(persons):5.1f}%  {100*wrong/len(persons):5.1f}%")

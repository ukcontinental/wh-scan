#!/usr/bin/env python3
"""Scores a cardcore-cli run against the dataset ground truth (spec §22 metrics).

What counts:
  * Only values the system WROTE WITHOUT ASKING are judged for correctness (auto-saved).
    Held fields (in the review queue) are "needs review", not errors.
  * correct-after-review assumes the user picks the right candidate when it is offered.
  * A contact built from photos of two different people is a wrong merge (always a wrong auto-save).
"""
import argparse, json, os, re, sys, unicodedata
from collections import Counter, defaultdict

def norm(s):
    if s is None:
        return ""
    s = unicodedata.normalize("NFKC", s).casefold()
    return re.sub(r"[\W_]+", "", s)

def host(u):
    if not u:
        return ""
    u = unicodedata.normalize("NFKC", u).lower().strip()
    u = re.sub(r"^https?://", "", u)
    u = re.sub(r"^www\.", "", u)
    return u.split("/")[0].rstrip(".")

T2S = str.maketrans("陳張黃吳劉楊許鄭謝趙羅孫葉蕭鄧呂蘇盧蔣鍾賴簡顏陸錢嚴韓馬馮歐陽業經總監長專員務際國華東門區號樓廣廈",
                    "陈张黄吴刘杨许郑谢赵罗孙叶萧邓吕苏卢蒋钟赖简颜陆钱严韩马冯欧阳业经总监长专员务际国华东门区号楼广厦")

def cjk_norm(s):
    return norm(s).translate(T2S)

def addr_key(a):
    """Digits of street + postal code: robust to punctuation / language variants."""
    text = " ".join(x for x in [a.get("formatted"), a.get("street"), a.get("postal_code") or a.get("postalCode")] if x)
    digits = re.findall(r"\d+", unicodedata.normalize("NFKC", text))
    return "".join(sorted(set(digits)))

def gt_fields(p):
    """Flatten a GT person into comparable field → set-of-acceptable-values."""
    n = p["name"]
    f = {}
    latin = " ".join(x for x in [n["given"], n["family"]] if x)
    if latin:
        f["name_latin"] = {norm(latin)}
    if n["cjk_full"]:
        f["name_cjk"] = {cjk_norm(n["cjk_full"])}
    if p["company"]:
        f["company"] = {norm(p["company"])}
    if p["company_cjk"]:
        f["company_cjk"] = {cjk_norm(p["company_cjk"])}
    if p["job_title"]:
        f["job_title"] = {norm(p["job_title"])}
    if p["job_title_cjk"]:
        f["job_title_cjk"] = {cjk_norm(p["job_title_cjk"])}
    deps = {norm(x) for x in [p.get("department"), p.get("department_cjk")] if x} | {cjk_norm(x) for x in [p.get("department_cjk")] if x}
    if deps:
        f["department"] = deps
    for ph in p["phones"]:
        f["phone:" + ph["number"]] = {ph["number"] + ("x" + ph["extension"] if ph.get("extension") else "")}
    for e in p["emails"]:
        f["email:" + e["address"].lower()] = {e["address"].lower()}
    for w in p["websites"]:
        f["web:" + host(w["url"])] = {host(w["url"])}
    for i, a in enumerate(p["addresses"]):
        keys = {addr_key(a)}
        if a.get("alt"):
            keys.add(addr_key(a["alt"]) if isinstance(a["alt"], dict) else addr_key({"formatted": a["alt"]}))
        f[f"address:{i}"] = keys
    return f

def written_fields(d):
    """Flatten a ContactDraft (what was written) the same way."""
    out = defaultdict(set)
    if not d:
        return out
    def v(k):
        x = d.get(k)
        return x["value"] if x else None
    latin = " ".join(x for x in [v("givenName"), v("familyName")] if x)
    if latin:
        out["name_latin"].add(norm(latin))
    if v("cjkName"):
        out["name_cjk"].add(cjk_norm(v("cjkName")))
    if v("company"):
        out["company"].add(norm(v("company")))
    if v("companyCJK"):
        out["company_cjk"].add(cjk_norm(v("companyCJK")))
    if v("jobTitle"):
        out["job_title"].add(norm(v("jobTitle")))
    if v("jobTitleCJK"):
        out["job_title_cjk"].add(cjk_norm(v("jobTitleCJK")))
    for k in ("department", "departmentCJK"):
        if v(k):
            out["department"].add(norm(v(k)))
            out["department"].add(cjk_norm(v(k)))
    for ph in d.get("phones", []):
        out["phones"].add(ph["e164"] + ("x" + ph["extensionNumber"] if ph.get("extensionNumber") else ""))
    for e in d.get("emails", []):
        out["emails"].add(e["value"].lower())
    for w in d.get("websites", []):
        out["webs"].add(host(w["value"]))
    for a in d.get("addresses", []):
        out["addresses"].add(addr_key({"formatted": a.get("formatted"), "street": a.get("street"), "postal_code": a.get("postalCode")}))
    return out

SINGLE = ["name_latin", "name_cjk", "company", "company_cjk", "job_title", "job_title_cjk", "department"]
GROUP = {"name": ["name_latin", "name_cjk"], "company": ["company", "company_cjk"], "job_title": ["job_title", "job_title_cjk"],
         "department": ["department"], "phone": [], "email": [], "website": [], "address": []}

def compare(gt, w, held_refs, review_candidates):
    """Returns per-field outcome list: (group, outcome) with outcome in correct/wrong/held/missed/extra."""
    res = []
    for k in SINGLE:
        g = gt.get(k)
        got = w.get(k, set())
        grp = next(x for x, ks in GROUP.items() if k in ks)
        if g:
            if got & g if k != "department" else got & g:
                res.append((grp, "correct"))
            elif got:
                res.append((grp, "wrong"))
            else:
                res.append((grp, "held" if held_refs.get(grp) else "missed"))
        elif got:
            # A value the card does not print (or a CJK/Latin slot swap the scorer can't credit).
            other = [x for x in GROUP[grp] if x != k]
            if any(gt.get(o) and (got & gt[o]) for o in other):
                res.append((grp, "correct"))
            else:
                res.append((grp, "extra"))
    for kind, wk, grp in [("phone:", "phones", "phone"), ("email:", "emails", "email"), ("web:", "webs", "website"), ("address:", "addresses", "address")]:
        gts = {k: v for k, v in gt.items() if k.startswith(kind)}
        used = set()
        for k, acceptable in gts.items():
            hit = w.get(wk, set()) & acceptable
            if not hit and kind == "phone:":
                # Extension written differently / without: count base number.
                base = {x.split("x")[0] for x in acceptable}
                hit = {x for x in w.get(wk, set()) if x.split("x")[0] in base}
            if hit:
                used |= hit
                res.append((grp, "correct"))
            else:
                res.append((grp, "held" if held_refs.get(grp) else "missed"))
        for x in w.get(wk, set()) - used:
            if kind == "address:" and x == "":
                continue
            res.append((grp, "wrong"))
    return res

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("run")
    ap.add_argument("--dataset", default="dataset")
    ap.add_argument("--expectations")
    ap.add_argument("--json-out")
    a = ap.parse_args()
    gt = json.load(open(os.path.join(a.dataset, "ground_truth.json")))
    run = json.load(open(a.run))
    photo_person = {p["id"]: p["person_id"] for p in gt["photos"]}
    photo_meta = {p["id"]: p for p in gt["photos"]}
    gt_people = {p["id"]: p for p in gt["people"]}
    book = {c["identifier"]: c for c in run["addressBook"]}
    open_review = [r for r in run["review"] if not r["resolved"]]
    review_by_person = defaultdict(list)
    for r in open_review:
        review_by_person[r["personID"]].append(r)

    # Map pipeline people → GT people.
    gt_to_pipeline = defaultdict(list)
    wrong_merges = 0
    for p in run["people"]:
        gids = {photo_person[i] for i in p["photoIDs"]}
        if len(gids) > 1:
            wrong_merges += 1
        for g in gids:
            gt_to_pipeline[g].append(p)

    # Pairing.
    pairs_total = pairs_ok = 0
    empty = set((run.get("grouping") or {}).get("empty", []))
    for pid, person in gt_people.items():
        photos = [p for p in gt["photos"] if p["person_id"] == pid]
        if len(photos) < 2:
            continue
        data_photos = [p for p in photos if p["id"] not in empty]
        pairs_total += 1
        groups = [set(pp["photoIDs"]) for pp in run["people"] if set(pp["photoIDs"]) & {p["id"] for p in photos}]
        if len(data_photos) <= 1 or any({p["id"] for p in data_photos} <= g for g in groups):
            # Correct when all data-bearing sides ended up in one person (decorative backs may be ignored).
            if all(len(g - {p["id"] for p in photos}) == 0 for g in groups):
                pairs_ok += 1
    decorative = [p for p in gt["photos"] if p.get("back_type") in ("decorative", "d")]
    deco_ignored = sum(1 for p in decorative if p["id"] in empty)

    rows = []
    field_counts = defaultdict(Counter)
    for pid, person in gt_people.items():
        recs = gt_to_pipeline.get(pid, [])
        gtf = gt_fields(person)
        merged_wrong = any(len({photo_person[i] for i in r["photoIDs"]}) > 1 for r in recs)
        # What was written for this person: union of writable drafts of its pipeline records that were written.
        written = defaultdict(set)
        statuses = [r["status"] for r in recs]
        for r in recs:
            if r["status"] in ("created", "updated", "alreadyExists"):
                for k, v in written_fields(r.get("draft")).items():
                    written[k] |= v
        reviews = [it for r in recs for it in review_by_person.get(r["id"], [])]
        held_groups = defaultdict(bool)
        for it in reviews:
            f = (it.get("field") or "")
            for grp, keys in [("name", ["name"]), ("company", ["company"]), ("job_title", ["job_title"]), ("department", ["department"]),
                              ("phone", ["phone"]), ("email", ["email"]), ("website", ["website"]), ("address", ["address"])]:
                if any(f.startswith(k) or k in f for k in keys):
                    held_groups[grp] = True
            if it["kind"] in ("grouping", "duplicate"):
                for g in GROUP:
                    held_groups[g] = True
        outcomes = compare(gtf, written, held_groups, None)
        for grp, o in outcomes:
            field_counts[grp][o] += 1
        n_wrong = sum(1 for _, o in outcomes if o in ("wrong", "extra"))
        n_missed = sum(1 for _, o in outcomes if o == "missed")
        n_held = sum(1 for _, o in outcomes if o == "held")
        needs_human = bool(reviews)
        auto_saved = any(s in ("created", "updated", "alreadyExists") for s in statuses)
        # Distractor leakage.
        leaks = []
        all_written_text = " ".join(" ".join(v) for v in written.values())
        for dtext in person.get("distractors", []):
            if len(norm(dtext)) >= 6 and norm(dtext) in all_written_text:
                leaks.append(dtext)
        rows.append({
            "person": pid, "statuses": statuses, "needs_human": needs_human, "auto_saved": auto_saved,
            "wrong": n_wrong, "missed": n_missed, "held": n_held, "wrong_merge": merged_wrong,
            "perfect_auto": auto_saved and not needs_human and n_wrong == 0 and n_missed == 0 and not merged_wrong,
            "wrong_auto_save": auto_saved and (n_wrong > 0 or merged_wrong),
            "leaks": leaks, "outcomes": outcomes, "reviews": [(it["kind"], it.get("field")) for it in reviews],
        })

    n = len(rows)
    def pct(x, d):
        return round(100.0 * x / d, 1) if d else None
    acc = {}
    for grp, c in field_counts.items():
        judged = c["correct"] + c["wrong"] + c["missed"] + c["held"] + c["extra"]
        acc[grp] = {"correct": c["correct"], "wrong": c["wrong"] + c["extra"], "held_for_review": c["held"], "missed": c["missed"],
                    "auto_accuracy_%": pct(c["correct"], c["correct"] + c["wrong"] + c["extra"]),
                    "coverage_%": pct(c["correct"], judged)}
    photos = run["photos"]
    secs = [p["seconds"] for p in photos if p["status"] == "recognized" and p["seconds"] > 0]
    dedup = []
    if a.expectations and os.path.exists(a.expectations):
        exp = json.load(open(a.expectations))
        for e in exp["dedup"]:
            recs = gt_to_pipeline.get(e["person_id"], [])
            got = []
            for r in recs:
                dup = r.get("duplicate") or {}
                match = (dup.get("match") or {}).get("identifier")
                got.append({"status": r["status"], "verdict": dup.get("verdict"), "matched": match})
            ok = False
            if e["expected"].startswith("update"):
                ok = any(g["matched"] == e["existing_id"] and g["status"] in ("updated", "alreadyExists") for g in got)
                if e["expected"] == "update+conflict":
                    ok = ok and any(it["kind"] == "conflict" for r in recs for it in review_by_person.get(r["id"], []))
            elif e["expected"] == "new":
                ok = all(g["matched"] != e["existing_id"] for g in got) and any(g["status"] == "created" for g in got)
            else:
                ok = all(not (g["matched"] == e["existing_id"] and g["status"] in ("updated", "alreadyExists")) for g in got)
            dedup.append({**e, "got": got, "ok": ok})
    report = {
        "run": a.run,
        "config": run["config"],
        "photos": len(photos),
        "gt_people": n,
        "pipeline_people": len([p for p in run["people"] if p["status"] != "ignored"]),
        "pairing": {"two_sided_people": pairs_total, "correctly_grouped": pairs_ok, "accuracy_%": pct(pairs_ok, pairs_total),
                    "wrong_merges": wrong_merges, "decorative_backs_ignored": f"{deco_ignored}/{len(decorative)}"},
        "contacts": {
            "auto_saved": sum(r["auto_saved"] for r in rows),
            "perfect_without_human_%": pct(sum(r["perfect_auto"] for r in rows), n),
            "human_intervention_rate_%": pct(sum(r["needs_human"] for r in rows), n),
            "wrong_auto_save_rate_%": pct(sum(r["wrong_auto_save"] for r in rows), n),
            "people_with_missed_fields": sum(1 for r in rows if r["missed"] > 0),
            "distractor_leaks": sum(len(r["leaks"]) for r in rows),
            "open_review_items": len(open_review),
            "review_items_by_kind": dict(Counter(r["kind"] for r in open_review)),
            "review_items_by_field": dict(Counter((r.get("field") or r["kind"]).split(":")[0] for r in open_review)),
        },
        "field_accuracy": acc,
        "duplicates": dedup,
        "dedup_ok": f"{sum(d['ok'] for d in dedup)}/{len(dedup)}" if dedup else None,
        "failed_photos": sum(1 for p in photos if p["status"] == "failed"),
        "avg_seconds_per_photo": round(sum(secs) / len(secs), 2) if secs else None,
        "wall_seconds": round(run.get("wallSeconds", 0), 1),
        "cost_usd": round(run["summary"]["costUSD"], 4),
        "rows": rows,
    }
    out = json.dumps(report, indent=1, ensure_ascii=False)
    if a.json_out:
        open(a.json_out, "w").write(out)
    brief = {k: v for k, v in report.items() if k != "rows"}
    print(json.dumps(brief, indent=1, ensure_ascii=False))

if __name__ == "__main__":
    main()

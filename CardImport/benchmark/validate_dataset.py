#!/usr/bin/env python3
"""Consistency checks for the generated benchmark dataset.

    python3 validate_dataset.py [dataset_dir]

Exits 1 if any error is found; warnings do not fail the run.
"""
import collections
import json
import os
import re
import sys

from PIL import Image

SIDES = {"front", "back"}
LAYOUTS = {"horizontal", "vertical"}
SCRIPTS = {"en", "zh-Hant", "zh-Hans", "mixed"}
PHONE_KINDS = {"mobile", "work", "fax", "main"}
SOCIAL = {"linkedin", "wechat", "line", "whatsapp", "instagram", "facebook", "x", "other"}
FIELDS = {"name", "company", "job_title", "department", "phones", "emails", "websites", "addresses", "social"}
E164 = re.compile(r"^\+[1-9]\d{7,14}$")


def e164_plausible(n):
    if n.startswith("+1"):
        return re.fullmatch(r"\+1(416|905|647|604|212)55501\d\d", n) is not None
    if n.startswith("+886"):
        return re.fullmatch(r"\+886(9\d{8}|[24]2\d{7}|3[34]\d{6})", n) is not None
    if n.startswith("+852"):
        return re.fullmatch(r"\+852[235689]\d{7}", n) is not None
    if n.startswith("+86"):
        return re.fullmatch(r"\+86(1[3-9]\d{9}|(10|20|21)\d{8}|(755|571|512|411)\d{8})", n) is not None
    return False


def main():
    root = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "dataset"))
    errors, warnings = [], []
    err = errors.append
    with open(os.path.join(root, "ground_truth.json"), encoding="utf-8") as fh:
        gt = json.load(fh)
    for k in ("generator_version", "people", "photos"):
        if k not in gt:
            err(f"missing top-level key {k}")
    people = {p["id"]: p for p in gt["people"]}
    photos = gt["photos"]
    if len(people) != len(gt["people"]):
        err("duplicate person ids")
    if len({p["id"] for p in photos}) != len(photos):
        err("duplicate photo ids")

    # ---------------- people
    for pid, p in people.items():
        n = p["name"]
        for k in ("given", "family", "cjk_full", "prefix", "suffix"):
            if k not in n:
                err(f"{pid}: name.{k} missing")
        if not (n["given"] or n["family"] or n["cjk_full"]):
            warnings.append(f"{pid}: no name printed on any photo")
        if n["cjk_full"] and " " in n["cjk_full"]:
            err(f"{pid}: cjk_full contains spaces")
        dom = p["meta"]["email_domain"]
        for e in p["emails"]:
            if not re.fullmatch(r"[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}", e["address"]):
                err(f"{pid}: malformed email {e['address']}")
            if e["address"].split("@")[1] != dom:
                err(f"{pid}: email {e['address']} does not match company domain {dom}")
        for w in p["websites"]:
            if dom not in w["url"]:
                err(f"{pid}: website {w['url']} does not match domain {dom}")
        for ph in p["phones"]:
            if ph["kind"] not in PHONE_KINDS:
                err(f"{pid}: bad phone kind {ph['kind']}")
            if not E164.match(ph["number"]):
                err(f"{pid}: phone {ph['number']} is not E.164")
            elif not e164_plausible(ph["number"]):
                err(f"{pid}: phone {ph['number']} outside the fictional numbering plan")
            if ph["extension"] is not None and not ph["extension"].isdigit():
                err(f"{pid}: bad extension {ph['extension']}")
        if len({ph["number"] for ph in p["phones"]}) != len(p["phones"]):
            err(f"{pid}: duplicate phone numbers")
        for s in p["social"]:
            if s["service"] not in SOCIAL:
                err(f"{pid}: bad social service {s['service']}")
        for a in p["addresses"]:
            for k in ("street", "city", "region", "postal_code", "country"):
                if k not in a:
                    err(f"{pid}: address missing {k}")
            if not a["street"] or not a["city"]:
                err(f"{pid}: address without street/city")
        values = [n["given"], n["family"], n["cjk_full"], p["company"], p["company_cjk"], p["job_title"], p["job_title_cjk"],
                  p["department"], p.get("department_cjk")]
        values = [v for v in values if v]
        for d in p["distractors"]:
            for v in values:
                if d == v:
                    err(f"{pid}: distractor '{d}' equals a field value")
    # phone numbers unique across people
    owner = {}
    for pid, p in people.items():
        for ph in p["phones"]:
            if ph["number"] in owner and owner[ph["number"]] != pid:
                err(f"phone {ph['number']} shared by {owner[ph['number']]} and {pid}")
            owner[ph["number"]] = pid

    # ---------------- photos
    by_person = collections.defaultdict(list)
    union = collections.defaultdict(lambda: collections.defaultdict(set))
    for i, ph in enumerate(photos):
        fid = ph["id"]
        for k in ("file", "person_id", "side", "pair_id", "layout", "script", "degradations", "features", "visible_fields", "width", "height"):
            if k not in ph:
                err(f"{fid}: missing key {k}")
        path = os.path.join(root, ph["file"])
        if not os.path.isfile(path):
            err(f"{fid}: file {ph['file']} missing")
        else:
            with Image.open(path) as im:
                if im.size != (ph["width"], ph["height"]):
                    err(f"{fid}: size {im.size} != ({ph['width']},{ph['height']})")
                if im.format != "JPEG":
                    err(f"{fid}: not a JPEG")
        if ph.get("clean_file") and not os.path.isfile(os.path.join(root, ph["clean_file"])):
            err(f"{fid}: clean file missing")
        if not 900 <= max(ph["width"], ph["height"]) <= 2400:
            err(f"{fid}: long edge {max(ph['width'], ph['height'])} outside 900-2400")
        if ph["person_id"] not in people:
            err(f"{fid}: unknown person {ph['person_id']}")
            continue
        if ph["side"] not in SIDES or ph["layout"] not in LAYOUTS or ph["script"] not in SCRIPTS:
            err(f"{fid}: bad enum side/layout/script {ph['side']}/{ph['layout']}/{ph['script']}")
        if not set(ph["visible_fields"]) <= FIELDS:
            err(f"{fid}: unknown visible field {set(ph['visible_fields']) - FIELDS}")
        if not any(d.startswith("tilt_") for d in ph["degradations"]) or not any(d.startswith("jpeg_q") for d in ph["degradations"]):
            err(f"{fid}: tilt/jpeg degradation tag missing")
        for x, y in ph.get("card_quad", []):
            if not (-2 <= x <= ph["width"] + 2 and -2 <= y <= ph["height"] + 2):
                err(f"{fid}: card corner outside the frame")
        by_person[ph["person_id"]].append((i, ph))
        pr = ph.get("printed")
        if pr:
            vis = set()
            if any(pr["name"].values()):
                vis.add("name")
            if pr["company"] or pr["company_cjk"]:
                vis.add("company")
            if pr["job_title"] or pr["job_title_cjk"]:
                vis.add("job_title")
            if pr["department"] or pr["department_cjk"]:
                vis.add("department")
            vis |= {k for k in ("phones", "emails", "websites", "addresses", "social") if pr[k]}
            if vis != set(ph["visible_fields"]):
                err(f"{fid}: visible_fields {ph['visible_fields']} inconsistent with printed {sorted(vis)}")
            P = people[ph["person_id"]]
            u = union[ph["person_id"]]
            for k, v in pr["name"].items():
                if v:
                    u["name." + k].add(v)
                    if P["name"][k] != v:
                        err(f"{fid}: printed name.{k}={v!r} != person {P['name'][k]!r}")
            for k in ("company", "company_cjk", "job_title", "job_title_cjk", "department", "department_cjk"):
                if pr[k]:
                    u[k].add(pr[k])
                    if P.get(k) != pr[k]:
                        err(f"{fid}: printed {k}={pr[k]!r} != person {P.get(k)!r}")
            nums = {x["number"] for x in P["phones"]}
            for x in pr["phones"]:
                u["phones"].add(x["number"])
                if x["number"] not in nums:
                    err(f"{fid}: printed phone {x['number']} not in person phones")
                digits = re.sub(r"\D", "", x["text"])
                if x["number"][-7:] not in digits:
                    err(f"{fid}: phone text {x['text']!r} does not contain {x['number']}")
            for x in pr["emails"]:
                u["emails"].add(x["address"])
                if x["address"] not in x["text"]:
                    err(f"{fid}: email text mismatch")
            for x in pr["websites"]:
                u["websites"].add(x["url"])
            for x in pr["social"]:
                u["social"].add((x["service"], x["handle"]))
            for x in pr["addresses"]:
                u["addresses"].add(x["formatted"])
            for d in pr["distractors"]:
                if d not in P["distractors"]:
                    err(f"{fid}: printed distractor {d!r} not listed on person")
            if ph["side"] == "back" and ph.get("back_type") == "b" and "name" in ph["visible_fields"]:
                err(f"{fid}: back type b must not show a name")
            if ph.get("back_type") == "d" and set(ph["visible_fields"]) - set():
                err(f"{fid}: decorative back shows fields {ph['visible_fields']}")

    # person values must each be printed somewhere
    for pid, P in people.items():
        u = union[pid]
        for k, v in P["name"].items():
            if v and v not in u["name." + k]:
                err(f"{pid}: name.{k} never printed")
        for k in ("company", "company_cjk", "job_title", "job_title_cjk", "department", "department_cjk"):
            if P.get(k) and P[k] not in u[k]:
                err(f"{pid}: {k} never printed")
        for x in P["phones"]:
            if x["number"] not in u["phones"]:
                err(f"{pid}: phone {x['number']} never printed")
        for x in P["emails"]:
            if x["address"] not in u["emails"]:
                err(f"{pid}: email never printed")
        printed_addr = u["addresses"]
        for a in P["addresses"]:
            if a["formatted"] not in printed_addr:
                err(f"{pid}: address {a['formatted']!r} never printed")

    # pairs
    for pid, lst in by_person.items():
        sides = [ph["side"] for _, ph in lst]
        if "front" not in sides:
            err(f"{pid}: no front photo")
        two = people[pid]["meta"]["two_sided"]
        if two:
            if sorted(sides) != ["back", "front"]:
                err(f"{pid}: two-sided person must have exactly one front and one back, got {sides}")
            for _, ph in lst:
                if ph["pair_id"] != pid:
                    err(f"{ph['id']}: pair_id {ph['pair_id']} != {pid}")
            (i1, a), (i2, b) = lst
            if abs(i1 - i2) == 1:
                err(f"{pid}: pair photos {a['id']} and {b['id']} are adjacent")
            if a["layout"] != b["layout"]:
                warnings.append(f"{pid}: front/back layouts differ")
        else:
            if len(lst) != 1 or lst[0][1]["pair_id"] is not None:
                err(f"{pid}: single-photo person has pair_id or several photos")
    for pid in people:
        if pid not in by_person:
            err(f"{pid}: person has no photo")

    # ---------------- summary
    total_mb = sum(os.path.getsize(os.path.join(dp, f)) for dp, _, fs in os.walk(root) for f in fs) / 1e6
    sc = collections.Counter(p["script"] for p in photos)
    print(f"dataset: {root}")
    print(f"people {len(people)}, photos {len(photos)}, pairs {sum(1 for p in people.values() if p['meta']['two_sided'])}, size {total_mb:.1f} MB")
    print("photo scripts:", dict(sc))
    if total_mb > 60:
        warnings.append(f"dataset is {total_mb:.1f} MB (> 60 MB)")
    for w in warnings:
        print("WARN ", w)
    for e in errors:
        print("ERROR", e)
    print(f"{len(errors)} error(s), {len(warnings)} warning(s)")
    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Builds pipeline inputs for one benchmark scenario from the dataset.

The pipeline itself never reads ground truth. This script only simulates what the phone would know:
  * selection order (dataset order, which is shuffled so pairs are not adjacent)
  * EXIF capture times (scenario "timestamps": the user photographed each card front then back,
    one person after another — the normal way people photograph a stack of cards; scenario
    "no-timestamps": screenshots / forwarded images without EXIF)
  * a colour histogram of the image centre (stand-in for the on-device card signature)
  * an "existing address book" seeded with a few dataset people (some outdated) and decoys,
    to measure duplicate detection. Expected outcomes go to expectations.json for the scorer only.
"""
import argparse, colorsys, json, os, random
from PIL import Image

def histogram(path):
    im = Image.open(path).convert("RGB")
    w, h = im.size
    im = im.crop((int(w * .25), int(h * .25), int(w * .75), int(h * .75))).resize((32, 32))
    hist = [0.0] * 15
    for r, g, b in im.getdata():
        hh, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
        if s < 0.18:
            hist[12 + (0 if v < .33 else 1 if v < .7 else 2)] += 1
        else:
            hist[min(11, int(hh * 12))] += s
    t = sum(hist) or 1
    return [x / t for x in hist]

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dataset", default="dataset")
    ap.add_argument("--scenario", choices=["timestamps", "no-timestamps"], default="timestamps")
    ap.add_argument("--out", required=True)
    ap.add_argument("--seed", type=int, default=7)
    a = ap.parse_args()
    rng = random.Random(a.seed)
    gt = json.load(open(os.path.join(a.dataset, "ground_truth.json")))
    os.makedirs(a.out, exist_ok=True)

    times = {}
    if a.scenario == "timestamps":
        t = 1_790_000_000.0
        people = sorted({p["person_id"] for p in gt["photos"]})
        rng.shuffle(people)
        for pid in people:
            sides = sorted([p for p in gt["photos"] if p["person_id"] == pid], key=lambda p: p["side"] != "front")
            for s in sides:
                times[s["id"]] = t
                t += rng.uniform(5, 14)
            t += rng.uniform(20, 55)

    photos = []
    for p in gt["photos"]:
        path = os.path.abspath(os.path.join(a.dataset, p["file"]))
        photos.append({"id": p["id"], "file": path, "captureTime": times.get(p["id"]), "colorHistogram": histogram(path)})
    json.dump(photos, open(os.path.join(a.out, "photos.json"), "w"), indent=1)

    # Existing address book (dedup test). Deterministic picks.
    people = gt["people"]
    by_id = {p["id"]: p for p in people}
    rng2 = random.Random(11)
    with_email = [p for p in people if p["emails"] and p["name"]["given"]]
    picks = rng2.sample(with_email, 4)
    existing, expect = [], []
    for i, p in enumerate(picks):
        n = p["name"]
        c = {"identifier": f"existing-{i+1}", "givenName": n["given"] or "", "familyName": n["family"] or "",
             "nickname": "", "organization": p["company"] or p["company_cjk"] or "", "jobTitle": "",
             "phones": [], "emails": [p["emails"][0]["address"]], "urls": []}
        if i == 0:
            exp = "update"            # same person, card adds phones/title → additive update
        elif i == 1:
            c["phones"] = [x["number"] for x in p["phones"]]
            c["emails"] = [e["address"] for e in p["emails"]]
            c["urls"] = [w["url"] for w in p["websites"]]
            c["jobTitle"] = p["job_title"] or ""
            exp = "update"            # nearly complete already
        elif i == 2:
            c["organization"] = "Previous Employer Inc."
            exp = "update+conflict"   # changed jobs → company conflict goes to review
        else:
            c["emails"] = []
            mob = [x["number"] for x in p["phones"] if x["kind"] == "mobile"]
            c["phones"] = mob[:1] or [x["number"] for x in p["phones"]][:1]
            exp = "update"            # matched by mobile + name
        existing.append(c)
        expect.append({"existing_id": c["identifier"], "person_id": p["id"], "expected": exp})
    # Decoys: same name as a dataset person, different everything else → must NOT merge.
    decoy_src = [p for p in people if p["name"]["given"] and p not in picks][:2]
    for j, p in enumerate(decoy_src):
        n = p["name"]
        existing.append({"identifier": f"decoy-{j+1}", "givenName": n["given"], "familyName": n["family"], "nickname": "",
                         "organization": "Unrelated Holdings Ltd." if j == 0 else (p["company"] or ""), "jobTitle": "",
                         "phones": ["+14165559999"], "emails": [f"someone{j}@elsewhere.example"], "urls": []})
        expect.append({"existing_id": f"decoy-{j+1}", "person_id": p["id"],
                       "expected": "new" if j == 0 else "new_or_review"})
    json.dump(existing, open(os.path.join(a.out, "existing_contacts.json"), "w"), indent=1, ensure_ascii=False)
    json.dump({"scenario": a.scenario, "dedup": expect}, open(os.path.join(a.out, "expectations.json"), "w"), indent=1)
    print(f"{len(photos)} photos, {len(existing)} existing contacts → {a.out}")

if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Generate the business-card recognition benchmark dataset.

    python3 generate_dataset.py [--people 45] [--seed 20261002] [--out dataset]

Pipeline (fully deterministic for a given --seed / --people):
  1. build fictional people (cardgen/sides.py) and the content of each card face;
  2. write one HTML file per face (cardgen/templates.py) and render all of them to PNG with
     Playwright Chromium in ONE browser session (render_cards.js, deviceScaleFactor 2);
  3. simulate a phone photo of each clean card on a table (cardgen/photo.py);
  4. write dataset/ground_truth.json and dataset/README.md.

Output layout:
  <out>/images/img_NNNN.jpg   simulated phone photos (the benchmark inputs)
  <out>/clean/img_NNNN.png    clean renders (2100x1200 or 1200x2100)
  <out>/html/img_NNNN.html    the HTML source of each card face
  <out>/ground_truth.json
  <out>/README.md
"""
import argparse
import collections
import json
import os
import random
import shutil
import subprocess
import sys

import cv2
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from cardgen import data as D  # noqa: E402
from cardgen.photo import simulate_photo  # noqa: E402
from cardgen.sides import build_people, build_sides, quota  # noqa: E402
from cardgen.templates import render_html  # noqa: E402

GENERATOR_VERSION = "1"
NODE = shutil.which("node") or "/opt/node22/bin/node"


# ---------------------------------------------------------------- ordering

def shuffle_no_adjacent_pairs(items, rng, key):
    items = list(items)
    rng.shuffle(items)
    for _ in range(10000):
        bad = [i for i in range(len(items) - 1) if key(items[i]) == key(items[i + 1])]
        if not bad:
            return items
        i = bad[0] + 1
        j = rng.randrange(len(items))
        items[i], items[j] = items[j], items[i]
    raise RuntimeError("could not separate pairs")


# ---------------------------------------------------------------- ground-truth helpers

def visible_fields(pr):
    v = []
    if any(pr["name"].values()):
        v.append("name")
    if pr["company"] or pr["company_cjk"]:
        v.append("company")
    if pr["job_title"] or pr["job_title_cjk"]:
        v.append("job_title")
    if pr["department"] or pr["department_cjk"]:
        v.append("department")
    for k in ("phones", "emails", "websites", "addresses", "social"):
        if pr[k]:
            v.append(k)
    return v


def features_for(spec, person, fit_scale):
    pr = spec["printed"]
    f = []
    logo = spec.get("logo") or {}
    if logo.get("scale") == "large" or spec["template"] in ("logo_heavy", "back_logo"):
        f.append("logo_large")
    if spec.get("qr"):
        f.append("qr_code")
    if spec.get("avatar"):
        f.append("person_photo")
    if len(pr["phones"]) >= 2:
        f.append("multi_phone")
    if len(pr["emails"]) >= 2:
        f.append("multi_email")
    if len(pr["addresses"]) >= 2:
        f.append("multi_address")
    if spec.get("small_font") or fit_scale <= 0.85:
        f.append("small_font")
    if spec.get("fancy_font") and spec.get("name_main") and spec["template"] not in ("startup", "bilingual_columns"):
        f.append("fancy_font")
    has_name = any(pr["name"].values())
    if person["confusable"] and has_name and (pr["company"] or pr["company_cjk"]):
        f.append("name_company_confusable")
    if spec.get("slogan") or (spec.get("decor") and spec["decor"] in sum(person["slogans"].values(), [])):
        f.append("slogan")
    if spec.get("certs"):
        f.append("certification")
    if spec.get("est"):
        f.append("established_year")
    if pr["social"]:
        f.append("social_handle")
    if any(p["extension"] for p in pr["phones"]):
        f.append("phone_extension")
    if spec["template"] == "vertical_cjk":
        f.append("vertical_text")
    if spec.get("title_main") and spec.get("title_sub"):
        f.append("bilingual_title")
    if pr["department"] or pr["department_cjk"]:
        f.append("department")
    if logo.get("text") and logo["text"] in pr["distractors"]:
        f.append("wordmark_differs_from_company")
    if pr["name"]["prefix"] or pr["name"]["suffix"]:
        f.append("name_prefix_suffix")
    if pr["name"]["cjk_full"] and person["name"]["cjk_spaced"] and spec.get("name_main"):
        f.append("cjk_name_spaced")
    if pr["name"]["given"] and person["name"]["family_first_latin"]:
        f.append("latin_family_name_first")
    if spec["side"] == "back" and not has_name:
        f.append("no_name")
    if spec["template"] == "back_decor":
        f.append("decorative_only")
    if any(p["text"].lstrip("TMFPCel:手機電話傳真 ").startswith("+") for p in pr["phones"]):
        f.append("phone_intl_format")
    if spec.get("qr_payload", "") and spec["qr_payload"].startswith("BEGIN:VCARD"):
        f.append("qr_vcard")
    return f


def structured_address(key, form, country_printed):
    a = D.ADDR[key]
    fields = dict(a[form])
    if not country_printed:
        fields["country"] = None
    return {"street": fields["street"], "city": fields["city"], "region": fields["region"],
            "postal_code": fields["postal_code"], "country": fields["country"], "country_code": a["cc"]}


def build_person_gt(person, specs):
    """Union of everything printed on this person's faces (front first)."""
    specs = sorted(specs, key=lambda s: s["side"] != "front")
    name = {"given": None, "family": None, "cjk_full": None, "prefix": None, "suffix": None}
    scal = {k: None for k in ("company", "company_cjk", "job_title", "job_title_cjk", "department", "department_cjk")}
    phones, emails, webs, social, dis = {}, {}, {}, {}, []
    addrs = collections.OrderedDict()
    for s in specs:
        pr = s["printed"]
        for k, v in pr["name"].items():
            name[k] = name[k] or v
        for k in scal:
            scal[k] = scal[k] or pr[k]
        for p in pr["phones"]:
            q = phones.setdefault(p["number"], {"kind": p["kind"], "number": p["number"], "extension": None})
            q["extension"] = q["extension"] or p["extension"]
        for e_ in pr["emails"]:
            emails.setdefault(e_["address"], {"address": e_["address"]})
        for w in pr["websites"]:
            webs.setdefault(w["url"], {"url": w["url"]})
        for so in pr["social"]:
            social.setdefault((so["service"], so["handle"]), {"service": so["service"], "handle": so["handle"]})
        for a in pr["addresses"]:
            entry = addrs.setdefault(a["key"], {"forms": collections.OrderedDict()})
            entry["forms"].setdefault(a["form"], ", ".join(a["lines"]))
        for d in pr["distractors"]:
            if d not in dis:
                dis.append(d)
    addresses = []
    for key, entry in addrs.items():
        forms = list(entry["forms"].items())
        main_form, main_fmt = forms[0]
        rec = structured_address(key, main_form, person["addr_country"])
        rec["formatted"] = main_fmt
        rec["alt"] = None
        if len(forms) > 1:
            alt_form, alt_fmt = forms[1]
            rec["alt"] = dict(structured_address(key, alt_form, person["addr_country"]), formatted=alt_fmt)
        addresses.append(rec)
    return {
        "id": person["id"], "name": name,
        "company": scal["company"], "company_cjk": scal["company_cjk"],
        "job_title": scal["job_title"], "job_title_cjk": scal["job_title_cjk"],
        "department": scal["department"], "department_cjk": scal["department_cjk"],
        "phones": list(phones.values()), "emails": list(emails.values()), "websites": list(webs.values()),
        "addresses": addresses, "social": list(social.values()), "distractors": dis,
        "meta": {"flavour": person["cc"], "front_script": person["script"], "two_sided": bool(person["back_type"]),
                 "back_type": person["back_type"], "confusable_case": person["special"],
                 "email_domain": person["company"]["domain"]},
    }


# ---------------------------------------------------------------- photo parameters

def photo_plan(n, rng):
    """Balanced, shuffled per-photo degradation decisions."""
    return {
        "bg": quota(n, [("wood", .4), ("white_table", .3), ("dark_fabric", .3)], rng),
        "clutter": quota(n, [(True, .25), (False, .75)], rng),
        "uneven": quota(n, [(True, .45), (False, .55)], rng),
        "shadow": quota(n, [(True, .3), (False, .7)], rng),
        "glare": quota(n, [(True, .12), (False, .88)], rng),
        "blur": quota(n, [("small", .25), ("motion", .06), ("none", .69)], rng),
        "res": quota(n, [("low", .25), ("high", .75)], rng),
    }


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--people", type=int, default=45)
    ap.add_argument("--seed", type=int, default=20261002)
    ap.add_argument("--out", default=os.path.join(HERE, "dataset"))
    ap.add_argument("--keep-build", action="store_true", help="keep the temporary _build directory")
    args = ap.parse_args()

    out = os.path.abspath(args.out)
    for sub in ("images", "clean", "html", "_build"):
        shutil.rmtree(os.path.join(out, sub), ignore_errors=True)
        os.makedirs(os.path.join(out, sub))
    rng = random.Random(args.seed)

    people = build_people(args.people, rng)
    counts = {}
    faces = []
    for p in people:
        for spec in build_sides(p, rng, counts):
            faces.append((p, spec))
    faces = shuffle_no_adjacent_pairs(faces, rng, key=lambda f: f[0]["id"])

    # ---- HTML + render
    jobs, photos = [], []
    for i, (p, spec) in enumerate(faces):
        pid = f"img_{i + 1:04d}"
        html, w, h = render_html(spec, random.Random(args.seed * 7919 + i))
        hp = os.path.join(out, "html", pid + ".html")
        with open(hp, "w", encoding="utf-8") as fh:
            fh.write(html)
        cp = os.path.join(out, "clean", pid + ".png")
        jobs.append({"html": hp, "out": cp, "width": w, "height": h})
        photos.append({"id": pid, "person": p, "spec": spec, "clean": cp})
    jobs_path = os.path.join(out, "_build", "jobs.json")
    fit_path = os.path.join(out, "_build", "fit.json")
    with open(jobs_path, "w") as fh:
        json.dump(jobs, fh)
    print(f"rendering {len(jobs)} card faces with Playwright Chromium ...", flush=True)
    subprocess.run([NODE, os.path.join(HERE, "render_cards.js"), jobs_path, fit_path], check=True)
    with open(fit_path) as fh:
        fit = json.load(fh)

    # ---- photo simulation
    plan = photo_plan(len(photos), rng)
    gt_photos = []
    for i, ph in enumerate(photos):
        spec, person = ph["spec"], ph["person"]
        nrng = np.random.default_rng(args.seed * 1000003 + i)
        fs = fit.get(ph["clean"], 1.0)
        small = spec.get("small_font") or fs <= 0.85
        res = plan["res"][i]
        if res == "low" and not small:
            L = int(nrng.integers(900, 1201))
        else:
            L = int(nrng.integers(1500 if small else 1300, 2401))
        blur = plan["blur"][i]
        if small and blur == "motion":
            blur = "small"
        params = {
            "long_edge": L, "bg": plan["bg"][i], "clutter": plan["clutter"][i],
            "fill": float(nrng.uniform(0.60, 0.85)), "tilt": float(nrng.uniform(2, 8)),
            "rot": float(nrng.uniform(-6, 6)) if nrng.random() < 0.7 else float(nrng.uniform(-1.2, 1.2)),
            "uneven": plan["uneven"][i], "shadow": plan["shadow"][i], "glare": plan["glare"][i],
            "blur_sigma": float(nrng.uniform(0.7, 1.1 if small else 1.5)) if blur == "small" else 0.0,
            "motion_len": int(nrng.integers(4, 8)) if blur == "motion" else 0,
            "noise_sigma": float(nrng.uniform(1.5, 4.5)), "jpeg_q": int(nrng.integers(50, 86)),
            "frame_portrait": (nrng.random() < 0.85) if spec["layout"] == "vertical" else (nrng.random() < 0.12),
        }
        if L <= 1200 or small:  # keep the card large in frame when resolution is already tight
            params["frame_portrait"] = spec["layout"] == "vertical"
        card = cv2.imread(ph["clean"], cv2.IMREAD_COLOR)
        img, quad, clutter = simulate_photo(card, nrng, params)
        ip = os.path.join(out, "images", ph["id"] + ".jpg")
        cv2.imwrite(ip, img, [cv2.IMWRITE_JPEG_QUALITY, params["jpeg_q"], cv2.IMWRITE_JPEG_OPTIMIZE, 1])
        degr = [f"tilt_{round(params['tilt'])}deg"]
        if abs(params["rot"]) >= 1.5:
            degr.append(f"rotate_{round(abs(params['rot']))}deg")
        degr += ["bg_" + params["bg"]]
        if clutter:
            degr.append("busy_background")
        if params["uneven"]:
            degr.append("uneven_light")
        if params["shadow"]:
            degr.append("shadow")
        if params["glare"]:
            degr.append("glare")
        if params["blur_sigma"]:
            degr.append("blur_small")
        if params["motion_len"]:
            degr.append("blur_motion")
        if params["noise_sigma"] >= 3.0:
            degr.append("noise")
        degr.append(f"jpeg_q{params['jpeg_q']}")
        degr.append(f"low_res_{L}px" if L <= 1200 else f"res_{L}px")
        h, w = img.shape[:2]
        pr = spec["printed"]
        printed = {k: v for k, v in pr.items()}
        printed["addresses"] = [{"key": a["key"], "form": a["form"], "label": a["label"], "formatted": ", ".join(a["lines"])} for a in pr["addresses"]]
        gt_photos.append({
            "id": ph["id"], "file": f"images/{ph['id']}.jpg", "clean_file": f"clean/{ph['id']}.png",
            "person_id": person["id"], "side": spec["side"],
            "pair_id": person["id"] if person["back_type"] else None,
            "layout": spec["layout"], "script": spec["script"],
            "template": spec["template"], "back_type": spec.get("back_type"),
            "degradations": degr, "features": features_for(spec, person, fs),
            "visible_fields": visible_fields(pr), "width": w, "height": h,
            "card_quad": [[round(float(x), 1), round(float(y), 1)] for x, y in quad],
            "card_fill": round(params["fill"], 3), "text_fit_scale": fs,
            "qr_payload": spec.get("qr_payload"), "printed": printed,
        })
        print(f"  {ph['id']}  {person['id']}  {spec['side']:5s} {spec['template']:18s} {spec['script']:7s} {w}x{h}", flush=True)

    # ---- ground truth
    by_person = collections.defaultdict(list)
    for ph in photos:
        by_person[ph["person"]["id"]].append(ph["spec"])
    gt_people = [build_person_gt(p, by_person[p["id"]]) for p in people]
    gt = {"generator_version": GENERATOR_VERSION, "seed": args.seed, "people": gt_people, "photos": gt_photos}
    with open(os.path.join(out, "ground_truth.json"), "w", encoding="utf-8") as fh:
        json.dump(gt, fh, ensure_ascii=False, indent=1)
    write_readme(out, gt, args)
    if not args.keep_build:
        shutil.rmtree(os.path.join(out, "_build"), ignore_errors=True)
    print(f"done: {len(gt_people)} people, {len(gt_photos)} photos -> {out}")


# ---------------------------------------------------------------- README

def _table(counter, total, header):
    rows = [f"| {header} | count | share |", "|---|---:|---:|"]
    for k, v in sorted(counter.items(), key=lambda kv: (-kv[1], str(kv[0]))):
        rows.append(f"| {k} | {v} | {100 * v / total:.0f}% |")
    return "\n".join(rows)


def _dir_mb(path):
    return sum(os.path.getsize(os.path.join(dp, f)) for dp, _, fs in os.walk(path) for f in fs) / 1e6


def write_readme(out, gt, args):
    P, F = gt["people"], gt["photos"]
    n = len(F)
    c = collections.Counter
    script = c(p["script"] for p in F)
    front_script = c(p["meta"]["front_script"] for p in P)
    flavour = c(p["meta"]["flavour"] for p in P)
    side = c(p["side"] for p in F)
    layout = c(p["layout"] for p in F)
    tmpl = c(p["template"] for p in F)
    backs = c({"a": "a: other-language full", "b": "b: contact only, no name", "c": "c: logo + website + QR", "d": "d: decorative only"}[p["back_type"]]
              for p in F if p["side"] == "back")
    feats = c(f for p in F for f in p["features"])
    def dnorm(d):
        for pre in ("jpeg_q", "low_res_", "res_", "tilt_", "rotate_"):
            if d.startswith(pre):
                return pre.rstrip("_") if pre != "low_res_" else "low_res (<=1200px)"
        return d
    degr = c(dnorm(d) for p in F for d in p["degradations"])
    vis = c(v for p in F for v in p["visible_fields"])
    two = sum(1 for p in P if p["meta"]["two_sided"])
    longs = [max(p["width"], p["height"]) for p in F]
    qs = [int(d[6:]) for p in F for d in p["degradations"] if d.startswith("jpeg_q")]
    tilts = [int(d[5:-3]) for p in F for d in p["degradations"] if d.startswith("tilt_")]
    txt = f"""# Business-card recognition benchmark (synthetic)

Generated by `../generate_dataset.py` (generator_version {gt['generator_version']}, seed {args.seed}, people {args.people}).
Re-generate with:

```
python3 generate_dataset.py --people {args.people} --seed {args.seed} --out dataset
python3 validate_dataset.py dataset
```

All people, companies, phone numbers, e-mail addresses and street addresses are **fictional**
(North-American numbers use the reserved 555-01xx block).

## Contents

| item | value |
|---|---|
| people | {len(P)} |
| photos | {n} |
| people with two photos (front + back) | {two} ({100 * two / len(P):.0f}%) |
| image long edge | {min(longs)}-{max(longs)} px |
| JPEG quality | {min(qs)}-{max(qs)} |
| perspective tilt | {min(tilts)}-{max(tilts)} deg |
| size on disk | images {_dir_mb(os.path.join(out, 'images')):.1f} MB, clean {_dir_mb(os.path.join(out, 'clean')):.1f} MB, html {_dir_mb(os.path.join(out, 'html')):.1f} MB |

- `images/img_NNNN.jpg` - simulated phone photos (benchmark inputs). Photo order is shuffled so the
  two faces of the same card are never adjacent.
- `clean/img_NNNN.png` - the same card face rendered cleanly (2x device scale).
- `html/img_NNNN.html` - HTML source of the face.
- `ground_truth.json` - people + photos (format below).

## Distribution

### Photo script
{_table(script, n, 'script')}

### Person front-side script
{_table(front_script, len(P), 'script')}

### Person flavour (locale)
{_table(flavour, len(P), 'flavour')}

### Side / layout
{_table(side, n, 'side')}

{_table(layout, n, 'layout')}

### Back-side types
{_table(backs, max(1, sum(backs.values())), 'back type')}

### Templates
{_table(tmpl, n, 'template')}

### Card features (per photo)
{_table(feats, n, 'feature')}

### Photo degradations (per photo)
{_table(degr, n, 'degradation')}

### Visible fields (per photo)
{_table(vis, n, 'field')}

## Ground-truth format

`ground_truth.json` = `{{"generator_version", "seed", "people": [...], "photos": [...]}}`

**person** - the union of everything printed on *any* photo of that person (a value that is never
printed is `null` / absent, never invented):

- `name`: `given`, `family` (Latin script), `cjk_full` (no spaces, even when printed spaced, e.g. `陳 志 豪`),
  `prefix`, `suffix`.
- `company` (Latin) / `company_cjk`, `job_title` / `job_title_cjk`, `department` / `department_cjk`
  (the `*_cjk` department key is an extension of the base format).
- `phones[]`: `kind` (mobile / work / fax / main), `number` in E.164, `extension`.
- `emails[]`, `websites[]` (URL exactly as printed, e.g. `www.example.com`), `social[]` (`service`, `handle`).
- `addresses[]`: `street`, `city`, `region`, `postal_code`, `country` (as printed, `null` when the card
  does not print a country), plus extensions `country_code` (ISO alpha-2, always set), `formatted`
  (printed text, lines joined with ", ") and `alt` (the same address in the other script when another
  face prints it). Structured fields are given in the script of the face that printed it first
  (front preferred). Taiwanese/Chinese addresses: `city` = 台北市 / 上海市 ..., district + street in `street`,
  `region` = province when printed (广东省).
- `distractors[]`: slogans, certifications, "since 19xx", logo word-marks that differ from the
  company name, decorative text - none of these may end up in any contact field.
- `meta`: flavour, front script, back type, confusable-case key, e-mail domain (informational).

**photo**: `id`, `file`, `clean_file`, `person_id`, `side`, `pair_id` (= person id when the person has
two photos, else null), `layout`, `script`, `template`, `back_type`, `degradations[]`, `features[]`,
`visible_fields[]` (person fields printed on THIS photo), `width`, `height`, `card_quad` (card corners
tl,tr,br,bl in image pixels), `card_fill`, `text_fit_scale` (<1 = text was auto-shrunk to fit),
`qr_payload`, and `printed` - the exact values printed on this face (same keys as a person plus the
literal `text` of each phone / e-mail / website / social line). Use `printed` for per-photo scoring and
`people` for merged-contact scoring.

### Back types
- **a** other-language version with full details (e.g. zh-Hant front, English back).
- **b** address / phones / e-mail only, **no name** (sometimes the company); must be matched to its front.
- **c** big logo + website + QR code.
- **d** purely decorative (pattern / slogan / brand mark) - nothing useful to extract.

### Degradation tags
`tilt_Ndeg` (3-D perspective tilt), `rotate_Ndeg` (in-plane rotation >= 1.5 deg), `bg_wood|bg_white_table|bg_dark_fabric`,
`busy_background` (pen / paper / phone / coffee ring in frame), `uneven_light`, `shadow` (soft cast
shadow across the card), `glare`, `blur_small` (gaussian), `blur_motion`, `noise` (sigma >= 3),
`jpeg_qNN`, `low_res_NNNpx` (long edge <= 1200) or `res_NNNNpx`.
All photos also get a contact shadow, vignetting, white-balance cast, paper grain and mild sensor noise.
"""
    with open(os.path.join(out, "README.md"), "w", encoding="utf-8") as fh:
        fh.write(txt)


if __name__ == "__main__":
    main()

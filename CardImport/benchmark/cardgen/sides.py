"""Build people and the content (side specs) of every card face.

Every side spec carries a `printed` record of the exact values printed on that face; the person
ground truth is the union of printed records over all faces of that person.
"""
import base64
import io

import qrcode

from . import data as D
from .people import (address_lines, email_local, make_phone, phone_text, pick_dept, pick_title, slug)

SCRIPT_SHARES = [("en", 0.35), ("zh-Hant", 0.25), ("zh-Hans", 0.15), ("mixed", 0.25)]
BACK_SHARES = [("a", 0.35), ("b", 0.25), ("c", 0.22), ("d", 0.18)]
TWO_SIDED_SHARE = 0.40
VERTICAL_SHARE = 0.22

H_TEMPLATES = {
    "en": ["minimal_white", "navy_gold", "color_band", "logo_heavy", "bank_style", "startup", "japanese_minimal"],
    "zh-Hant": ["minimal_white", "color_band", "logo_heavy", "bank_style", "japanese_minimal", "navy_gold"],
    "zh-Hans": ["minimal_white", "navy_gold", "color_band", "logo_heavy", "bank_style", "startup"],
    "mixed": ["bilingual_columns", "bank_style", "minimal_white", "color_band", "startup", "navy_gold", "bilingual_columns"],
}
V_TEMPLATES = {
    "en": ["portrait_modern", "portrait_classic"],
    "zh-Hant": ["vertical_cjk", "vertical_cjk", "portrait_classic", "portrait_modern"],
    "zh-Hans": ["portrait_modern", "portrait_classic", "vertical_cjk"],
    "mixed": ["portrait_modern", "portrait_classic"],
}
LOGO_MARKS = {"food": ["fish", "leaf", "wave", "circle_initials"], "logistics": ["chevrons", "hexagon", "circle_initials"],
              "trading": ["globe", "diamond", "circle_initials"], "tech": ["bars", "hexagon", "dots"],
              "finance": ["pillars", "diamond", "bars"], "consulting": ["diamond", "circle_initials"],
              "design": ["dots", "leaf"], "tea": ["leaf", "seal"], "packaging": ["hexagon", "box"]}


def quota(n, shares, rng):
    """Largest-remainder allocation of n items over shares, returned as a shuffled list."""
    raw = [(k, n * s) for k, s in shares]
    base = {k: int(v) for k, v in raw}
    rem = n - sum(base.values())
    for k, v in sorted(raw, key=lambda kv: -(kv[1] - int(kv[1])))[:rem]:
        base[k] += 1
    out = [k for k, _ in shares for _ in range(base[k])]
    rng.shuffle(out)
    return out


def qr_data_uri(payload):
    q = qrcode.QRCode(error_correction=qrcode.constants.ERROR_CORRECT_M, box_size=10, border=2)
    q.add_data(payload)
    q.make(fit=True)
    img = q.make_image(fill_color="black", back_color="white")
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode()


# ====================================================================== people

SPECIALS = [  # name/company-confusable people
    {"key": "victoria", "cc": "HK", "script": "en", "name": ("陳慧琳", "Chan", "Victoria"), "company": "Chan & Chan Trading Ltd."},
    {"key": "morgan", "cc": "CA", "script": "en", "name": (None, "Lee", "Morgan"), "company": "Morgan Consulting Group"},
    {"key": "wangdaming", "cc": "TW", "script": "zh-Hant", "name": ("王大明", "Wang", "David"), "company": "Da Ming Food Co., Ltd."},
    {"key": "jordan", "cc": "US", "script": "en", "name": (None, "Taylor", "Jordan"), "company": "Taylor Jordan & Associates LLP"},
]


def _flavour(rng, script):
    if script == "en":
        return rng.choices(["CA", "US", "HK"], [0.6, 0.28, 0.12])[0]
    if script == "zh-Hant":
        return rng.choices(["TW", "HK"], [0.75, 0.25])[0]
    if script == "zh-Hans":
        return "CN"
    return rng.choices(["TW", "CN", "HK", "CA"], [0.35, 0.25, 0.2, 0.2])[0]


class NamePool:
    def __init__(self, rng):
        self.rng = rng
        self.pools = {k: list(v) for k, v in {
            "TW": D.TW_NAMES, "HK": D.HK_NAMES, "CN": D.CN_NAMES, "CA_W": D.CA_WESTERN,
            "CA_C": D.CA_CHINESE, "US_W": D.US_WESTERN, "US_C": D.US_CHINESE}.items()}
        for v in self.pools.values():
            rng.shuffle(v)
        self.used = {k: 0 for k in self.pools}

    def take(self, key):
        pool = self.pools[key]
        i = self.used[key]
        self.used[key] += 1
        item = pool[i % len(pool)]
        if i >= len(pool):  # recombine to keep names unique-ish
            other = pool[(i * 7 + 3) % len(pool)]
            if key in ("CA_W", "US_W"):
                item = (item[0], other[1])
        return item


def build_people(n, rng):
    scripts = quota(n, SCRIPT_SHARES, rng)
    people = [{"idx": i, "script": s, "cc": _flavour(rng, s), "special": None} for i, s in enumerate(scripts)]
    if n >= 12:
        for sp in SPECIALS:
            for p in people:
                if p["special"] is None and p["script"] == sp["script"]:
                    p["special"] = sp
                    p["cc"] = sp["cc"]
                    break
    # ---- two-sided people and back types
    n_two = round(n * TWO_SIDED_SHARE)
    backs = quota(n_two, BACK_SHARES, rng)
    backs.sort(key=lambda b: b != "a")  # place 'a' first: it has eligibility constraints
    order = list(range(n))
    rng.shuffle(order)
    for p in people:
        p["back_type"] = None
    for b in backs:
        for i in order:
            p = people[i]
            if p["back_type"] is not None:
                continue
            if b == "a" and p["script"] == "mixed":
                continue
            if b == "a" and p["special"] and p["special"]["name"][0] is None:
                continue
            p["back_type"] = b
            break
    # ---- layouts
    lay = quota(n, [("vertical", VERTICAL_SHARE), ("horizontal", 1 - VERTICAL_SHARE)], rng)
    for p, l in zip(people, lay):
        p["layout"] = l
    names = NamePool(rng)
    comp_cursor = {cc: 0 for cc in D.COMPANIES}
    comp_lists = {cc: rng.sample(v, len(v)) for cc, v in D.COMPANIES.items()}
    used_phones = set()
    out = []
    for p in people:
        out.append(_flesh_out(p, rng, names, comp_lists, comp_cursor, used_phones))
    return out


def _pick_company(rng, cc, need_cjk, comp_lists, comp_cursor, exclude=()):
    lst = comp_lists[cc]
    for _ in range(len(lst) * 2):
        c = lst[comp_cursor[cc] % len(lst)]
        comp_cursor[cc] += 1
        if need_cjk and not c["cjk"]:
            continue
        if c["en"] in exclude:
            continue
        return c
    return next(c for c in lst if c["cjk"] or not need_cjk)


def _flesh_out(p, rng, names, comp_lists, comp_cursor, used_phones):
    cc, script = p["cc"], p["script"]
    needs_cjk_name = script != "en" or p["back_type"] == "a"
    sp = p["special"]
    specials_companies = {s["company"] for s in SPECIALS}
    # ---- name
    eng_alias = None
    if sp:
        cjk, fam, giv = sp["name"]
    elif cc == "TW":
        cjk, fam, giv = names.take("TW")
    elif cc == "HK":
        cjk, fam, giv = names.take("HK")
    elif cc == "CN":
        cjk, fam, giv, eng_alias = names.take("CN")
    elif cc == "CA":
        if needs_cjk_name or rng.random() < 0.25:
            cjk, fam, giv = names.take("CA_C")
        else:
            (giv, fam), cjk = names.take("CA_W"), None
    else:
        if needs_cjk_name:
            cjk, fam, giv = names.take("US_C")
        else:
            (giv, fam), cjk = names.take("US_W"), None
    pinyin = cc == "CN"
    if pinyin and eng_alias and rng.random() < 0.6:
        giv = eng_alias
        pinyin = False
    # ---- company
    if sp:
        company = next(c for lst in D.COMPANIES.values() for c in lst if c["en"] == sp["company"])
    else:
        need_cjk = needs_cjk_name and (script != "en" or p["back_type"] == "a")
        company = _pick_company(rng, cc, need_cjk, comp_lists, comp_cursor, exclude=specials_companies)
    ind = company["industry"]
    title = pick_title(rng, ind)
    if sp and sp["key"] == "wangdaming":
        title = ("General Manager", "總經理", "总经理")
    flags = {
        "multi_phone": rng.random() < 0.45,
        "multi_email": rng.random() < 0.22,
        "multi_address": len(company["addrs"]) > 1 and rng.random() < 0.25,
        "social": rng.random() < 0.35,
        "qr": rng.random() < 0.22,
        "avatar": rng.random() < 0.16,
        "small_font": rng.random() < 0.15,
        "fancy_font": rng.random() < 0.25,
        "slogan": rng.random() < 0.45,
        "cert": bool(D.CERTS[ind]) and rng.random() < 0.3,
        "est": rng.random() < 0.15,
        "dept": rng.random() < 0.35,
        "extension": rng.random() < 0.3,
        "wordmark_brand": bool(company["wordmark"]) and rng.random() < 0.8,
    }
    # ---- prefix / suffix (latin only)
    prefix = suffix = None
    if script in ("en", "mixed") and not sp and rng.random() < 0.14:
        suffix = {"finance": "CPA", "consulting": "MBA", "tech": "PhD", "logistics": "P.Eng.", "packaging": "P.Eng."}.get(ind, "MBA")
        if suffix == "PhD" and rng.random() < 0.6:
            prefix, suffix = "Dr.", None
    # ---- phones
    addr_keys = list(company["addrs"])
    area = D.ADDR[addr_keys[0]]["area"] or None
    pcc = cc if cc != "CA" or D.ADDR[addr_keys[0]]["cc"] == "CA" else "CA"
    pcc = D.ADDR[addr_keys[0]]["cc"]
    phones = {
        "mobile": make_phone(rng, pcc, "mobile", area if pcc in ("CA",) else None, used_phones),
        "work": make_phone(rng, pcc, "work", area, used_phones),
        "fax": make_phone(rng, pcc, "fax", area, used_phones),
        "main": make_phone(rng, pcc, "main", area, used_phones),
    }
    if flags["extension"]:
        phones["work"]["extension"] = str(rng.choice([rng.randint(100, 899), rng.randint(10, 99), rng.randint(2000, 4999)]))
    if flags["multi_phone"]:
        front_kinds = ["mobile", "work"] + (["fax"] if rng.random() < 0.6 else [])
    else:
        front_kinds = [rng.choice(["mobile", "work", "mobile"])]
    # ---- email / web / social
    if pinyin:
        local = email_local(rng, giv, fam, pinyin=True)
    else:
        local = email_local(rng, giv, fam)
    domain = company["domain"]
    emails = [f"{local}@{domain}"]
    generic = f"{rng.choice(['info', 'sales', 'orders', 'service', 'contact'])}@{domain}"
    website = rng.choice([f"www.{domain}", f"www.{domain}", domain, f"https://www.{domain}"])
    social = []
    if flags["social"]:
        if cc in ("CA", "US"):
            h = rng.choice([f"{slug(giv)}{slug(fam)}", f"{slug(giv)}-{slug(fam)}"])
            social.append({"service": "linkedin", "handle": h,
                           "text": rng.choice([f"in /{h}", f"linkedin.com/in/{h}", f"LinkedIn: {h}"])})
        elif cc == "TW":
            h = rng.choice([f"{slug(giv)}_{slug(company['short'])[:6]}", f"{slug(giv)}{rng.randint(10, 99)}"])
            social.append({"service": "line", "handle": h, "text": rng.choice([f"LINE ID: {h}", f"LINE: {h}"])})
        elif cc == "CN":
            h = f"{slug(fam)}{slug(giv)}{rng.randint(80, 99)}"
            social.append({"service": "wechat", "handle": h, "text": None})
        else:
            h = f"{slug(giv)}{slug(fam)}{rng.randint(10, 99)}"
            social.append({"service": "wechat", "handle": h, "text": None})
        if company["industry"] == "design":
            social.append({"service": "instagram", "handle": domain.replace(".", "."), "text": f"@{domain}"})
    # ---- marketing / distractors
    sl = D.SLOGANS[ind]
    year = rng.choice([1962, 1978, 1985, 1992, 1998, 2003, 2011])
    brand = rng.choice(D.BRAND_COLORS)
    accent = rng.choice([c for c in D.BRAND_COLORS if c != brand])
    mark = rng.choice(LOGO_MARKS[ind])
    if cc in ("TW", "HK", "CN") and rng.random() < 0.25:
        mark = "seal"
    person = {
        "id": f"p{p['idx'] + 1:03d}", "idx": p["idx"], "cc": cc, "script": script, "layout": p["layout"],
        "back_type": p["back_type"], "special": sp["key"] if sp else None,
        "name": {"given": giv, "family": fam, "cjk": cjk, "prefix": prefix, "suffix": suffix,
                 "family_first_latin": pinyin and rng.random() < 0.6, "family_upper": rng.random() < 0.15,
                 "cjk_spaced": rng.random() < 0.25},
        "company": company, "title": title, "dept": pick_dept(rng, ind) if flags["dept"] else None,
        "phones": phones, "front_kinds": front_kinds, "emails": emails, "generic_email": generic,
        "website": website, "social": social, "addr_keys": addr_keys if flags["multi_address"] else addr_keys[:1],
        "all_addr_keys": addr_keys, "addr_country": rng.random() < 0.45,
        "flags": flags, "slogans": sl, "year": year,
        "certs": rng.sample(D.CERTS[ind], k=min(len(D.CERTS[ind]), rng.choice([1, 1, 2]))) if flags["cert"] else [],
        "palette": {"brand": brand, "accent": accent}, "logo_mark": mark,
        "confusable": bool(sp),
    }
    return person


# ====================================================================== sides

def _cjk_variant(script, cc):
    """Which Chinese script a CJK text of this person uses."""
    if script == "zh-Hans" or cc == "CN":
        return "zh-Hans"
    return "zh-Hant"


def latin_name(person):
    n = person["name"]
    fam = n["family"].upper() if n["family_upper"] else n["family"]
    core = f"{fam} {n['given']}" if n["family_first_latin"] else f"{n['given']} {fam}"
    if n["prefix"]:
        core = f"{n['prefix']} {core}"
    if n["suffix"]:
        core = f"{core}, {n['suffix']}"
    return core


def cjk_name(person):
    n = person["name"]
    return " ".join(n["cjk"]) if n["cjk_spaced"] else n["cjk"]


def _title_cjk(person, var):
    t = person["title"]
    return t[2] if var == "zh-Hans" else t[1]


def _dept_cjk(person, var):
    d = person["dept"]
    return None if d is None else (d[2] if var == "zh-Hans" else d[1])


def _company_cjk(person, var):
    c = person["company"]["cjk"]
    if c and var == "zh-Hans" and person["cc"] != "CN":
        return c  # company registered in Traditional script keeps its legal name
    return c


def _social_text(rng, s, lang):
    if s["text"]:
        return s["text"]
    if s["service"] == "wechat":
        return {"en": f"WeChat: {s['handle']}", "zh-Hans": f"微信：{s['handle']}",
                "zh-Hant": f"微信：{s['handle']}", "mixed": f"微信 WeChat: {s['handle']}"}[lang]
    return s["handle"]


def empty_printed():
    return {"name": {"given": None, "family": None, "cjk_full": None, "prefix": None, "suffix": None},
            "company": None, "company_cjk": None, "job_title": None, "job_title_cjk": None,
            "department": None, "department_cjk": None, "phones": [], "emails": [], "websites": [],
            "addresses": [], "social": [], "distractors": []}


def _pick_template(rng, script, layout, counts, avoid=None):
    pool = (V_TEMPLATES if layout == "vertical" else H_TEMPLATES)[script]
    pool = [t for t in pool if t != avoid] or pool
    m = min(counts.get(t, 0) for t in pool)
    cands = [t for t in pool if counts.get(t, 0) == m]
    t = rng.choice(cands)
    counts[t] = counts.get(t, 0) + 1
    return t


CITY_PREFIXES = ("深圳市", "上海", "广州", "北京", "杭州", "苏州", "大连")


def _brand_cjk(c):
    t = c["cjk"] or ""
    for pre in CITY_PREFIXES:
        if t.startswith(pre):
            t = t[len(pre):]
    return t


def _logo(person, rng, scale, text_mode="short"):
    c = person["company"]
    var = _cjk_variant(person["script"], person["cc"])
    wm = None
    if text_mode == "brand" and c["wordmark"]:
        wm = c["wordmark"]
    elif text_mode == "short":
        wm = c["short"]
    elif text_mode == "cjk_short" and c["cjk"]:
        wm = _brand_cjk(c)[:2]
    seal = _brand_cjk(c)[:2] if person["cc"] in ("TW", "HK", "CN") and c["cjk"] else c["short"][:2]
    return {"mark": person["logo_mark"], "text": wm, "initials": "".join(w[0] for w in c["short"].replace("&", " ").split())[:2].upper(),
            "seal": seal, "color": person["palette"]["brand"], "color2": person["palette"]["accent"], "scale": scale}


def build_full_side(person, rng, lang, side, template, layout, counts_ctx=None):
    """A face carrying name + company + title + contacts in language `lang` (en/zh-Hant/zh-Hans/mixed)."""
    pr = empty_printed()
    f = person["flags"]
    cc = person["cc"]
    var = _cjk_variant(lang if lang != "mixed" else person["script"], cc)
    if lang == "mixed":
        var = "zh-Hans" if cc == "CN" else "zh-Hant"
    spec = {"side": side, "template": template, "layout": layout, "script": lang, "var": var,
            "palette": person["palette"], "small_font": f["small_font"] and side == "front",
            "fancy_font": f["fancy_font"], "back_type": None if side == "front" else "a"}
    n = person["name"]
    show_latin = lang in ("en", "mixed")
    show_cjk = lang in ("zh-Hant", "zh-Hans", "mixed")
    # --- name
    if lang == "mixed":
        cjk_first = rng.random() < 0.6
        a, b = cjk_name(person), latin_name(person)
        spec["name_main"], spec["name_sub"] = (a, b) if cjk_first else (b, a)
    elif show_latin:
        spec["name_main"], spec["name_sub"] = latin_name(person), None
    else:
        spec["name_main"], spec["name_sub"] = cjk_name(person), None
    if show_latin:
        pr["name"].update(given=n["given"], family=n["family"], prefix=n["prefix"], suffix=n["suffix"])
    if show_cjk:
        pr["name"]["cjk_full"] = n["cjk"]
    # --- company / title / department
    comp = person["company"]
    ccjk = _company_cjk(person, var)
    if lang == "mixed":
        spec["company_main"], spec["company_sub"] = (ccjk, comp["en"])
        spec["title_main"], spec["title_sub"] = (_title_cjk(person, var), person["title"][0])
        pr["company"], pr["company_cjk"] = comp["en"], ccjk
        pr["job_title"], pr["job_title_cjk"] = person["title"][0], _title_cjk(person, var)
        if person["dept"]:
            spec["dept"] = f"{_dept_cjk(person, var)}  {person['dept'][0]}"
            pr["department"], pr["department_cjk"] = person["dept"][0], _dept_cjk(person, var)
        else:
            spec["dept"] = None
    elif show_latin:
        spec["company_main"], spec["company_sub"] = comp["en"], None
        spec["title_main"], spec["title_sub"] = person["title"][0], None
        pr["company"], pr["job_title"] = comp["en"], person["title"][0]
        spec["dept"] = person["dept"][0] if person["dept"] else None
        pr["department"] = spec["dept"]
    else:
        spec["company_main"], spec["company_sub"] = ccjk, None
        spec["title_main"], spec["title_sub"] = _title_cjk(person, var), None
        pr["company_cjk"], pr["job_title_cjk"] = ccjk, _title_cjk(person, var)
        spec["dept"] = _dept_cjk(person, var)
        pr["department_cjk"] = spec["dept"]
    # --- phones
    plang = lang if lang != "mixed" else "mixed"
    intl = side == "back" and rng.random() < 0.6
    kinds = person["front_kinds"] if side == "front" else (person["front_kinds"] if rng.random() < 0.7 else ["mobile", "work"])
    spec["phones"] = []
    for k in kinds:
        ph = person["phones"][k]
        t = phone_text(rng, ph, plang, intl=intl)
        spec["phones"].append(t)
        pr["phones"].append({"kind": k, "number": ph["e164"], "extension": ph["extension"] if k == "work" else None, "text": t})
    # --- email / web / social
    ems = list(person["emails"]) + ([person["generic_email"]] if f["multi_email"] else [])
    elab = {"en": rng.choice(["", "E ", "E: ", "Email: "]), "zh-Hant": rng.choice(["", "E-mail：", "信箱："]),
            "zh-Hans": rng.choice(["", "邮箱：", "E-mail："]), "mixed": rng.choice(["", "E-mail: ", "電郵 Email: " if var == "zh-Hant" else "邮箱 Email: "])}[lang]
    spec["emails"] = [elab + e for e in ems]
    pr["emails"] = [{"address": e, "text": elab + e} for e in ems]
    wlab = rng.choice(["", "", "W ", "Web: "]) if lang == "en" else rng.choice(["", "", "網址：" if var == "zh-Hant" else "网址："])
    spec["webs"] = [wlab + person["website"]]
    pr["websites"] = [{"url": person["website"], "text": wlab + person["website"]}]
    spec["socials"] = []
    for s in person["social"]:
        t = _social_text(rng, s, lang)
        spec["socials"].append(t)
        pr["social"].append({"service": s["service"], "handle": s["handle"], "text": t})
    # --- addresses
    spec["addresses"] = []
    side_form = "en" if lang == "en" else ("cjk" if lang in ("zh-Hant", "zh-Hans") else ("cjk" if rng.random() < 0.55 else "en"))
    for i, k in enumerate(person["addr_keys"]):
        a = D.ADDR[k]
        form = side_form
        if form == "cjk" and a["cjk"] is None:
            form = "en"
        lines = address_lines(a[form], a["cc"], form, person["addr_country"], rng)
        label = None
        if len(person["addr_keys"]) > 1:
            label = {"en": ["Head Office", "Warehouse"], "cjk": (["總公司", "工廠"] if var == "zh-Hant" else ["总部", "工厂"])}[form][min(i, 1)]
        spec["addresses"].append({"label": label, "lines": lines})
        pr["addresses"].append({"key": k, "form": form, "lines": lines, "label": label})
    # --- distractors / decorations
    spec["slogan"] = spec["est"] = None
    spec["certs"] = []
    dl = "en" if lang == "en" else (var if lang != "mixed" else rng.choice(["en", var]))
    if f["slogan"]:
        spec["slogan"] = rng.choice(person["slogans"][dl])
        pr["distractors"].append(spec["slogan"])
    if f["est"]:
        spec["est"] = rng.choice(D.EST[dl]).format(y=person["year"])
        pr["distractors"].append(spec["est"])
    if person["certs"]:
        spec["certs"] = list(person["certs"])
        pr["distractors"].extend(spec["certs"])
    big = template in ("logo_heavy",) or (template == "color_band" and rng.random() < 0.5)
    if f["wordmark_brand"]:
        spec["logo"] = _logo(person, rng, "large" if big else "small", "brand")
        pr["distractors"].append(spec["logo"]["text"])
    else:
        mode = "cjk_short" if (lang in ("zh-Hant", "zh-Hans") and rng.random() < 0.3) else rng.choice(["short", "short", None])
        spec["logo"] = _logo(person, rng, "large" if big else "small", mode)
    if spec["logo"]["mark"] == "seal" and spec["logo"]["seal"]:
        pass
    # --- qr / avatar
    spec["qr"] = spec["qr_payload"] = None
    if side == "front" and f["qr"]:
        if rng.random() < 0.5 or lang not in ("en", "mixed"):
            payload = f"https://{person['website'].replace('https://', '').rstrip('/')}"
        else:  # vCard restricted to values that are also printed on this face
            nn = person["name"]
            tel = pr["phones"][0]
            payload = ("BEGIN:VCARD\nVERSION:3.0\n" + f"N:{nn['family']};{nn['given']}\nFN:{nn['given']} {nn['family']}\n"
                       + f"ORG:{comp['en']}\nTEL;TYPE={'CELL' if tel['kind'] == 'mobile' else 'WORK'}:{tel['number']}\n"
                       + f"EMAIL:{person['emails'][0]}\nEND:VCARD")
        spec["qr"], spec["qr_payload"] = qr_data_uri(payload), payload
    spec["avatar"] = {"bg": person["palette"]["accent"]} if (side == "front" and f["avatar"]) else None
    spec["decor"] = None
    spec["printed"] = pr
    return spec


def build_back(person, rng, front_spec, counts):
    bt = person["back_type"]
    layout = person["layout"]
    var = front_spec["var"]
    cc = person["cc"]
    if bt == "a":
        lang = "en" if person["script"] in ("zh-Hant", "zh-Hans") else _cjk_variant("zh-Hant", cc)
        tmpl = _pick_template(rng, lang, layout, counts)
        spec = build_full_side(person, rng, lang, "back", tmpl, layout)
        spec["back_type"] = "a"
        return spec
    pr = empty_printed()
    spec = {"side": "back", "layout": layout, "palette": person["palette"], "small_font": False, "fancy_font": False,
            "back_type": bt, "qr": None, "qr_payload": None, "avatar": None, "slogan": None, "certs": [], "est": None,
            "decor": None, "name_main": None, "name_sub": None, "company_main": None, "company_sub": None,
            "title_main": None, "title_sub": None, "dept": None, "phones": [], "emails": [], "webs": [], "socials": [],
            "addresses": [], "var": var}
    comp = person["company"]
    if bt == "b":
        if person["script"] == "mixed":
            lang = rng.choice(["en", var])
        else:
            lang = person["script"] if rng.random() < 0.5 else ("en" if person["script"] != "en" else _cjk_variant("zh-Hant", cc))
        if lang != "en" and not comp["cjk"]:
            lang = "en"
        lvar = "en" if lang == "en" else lang
        spec["template"], spec["script"] = "back_contact", lang
        if rng.random() < 0.5:
            if lang == "en":
                spec["company_main"] = comp["en"]; pr["company"] = comp["en"]
            else:
                spec["company_main"] = comp["cjk"]; pr["company_cjk"] = comp["cjk"]
        keys = person["all_addr_keys"]
        for i, k in enumerate(keys):
            a = D.ADDR[k]
            form = "en" if lang == "en" or a["cjk"] is None else "cjk"
            lines = address_lines(a[form], a["cc"], form, person["addr_country"], rng)
            if len(keys) > 1:
                label = {"en": ["Head Office", "Warehouse & Distribution"], "cjk": (["總公司", "工廠"] if lvar == "zh-Hant" else ["总部", "工厂"])}[form][min(i, 1)]
            else:
                label = {"en": "Office", "cjk": "地址" if True else None}[form] if rng.random() < 0.5 else None
            spec["addresses"].append({"label": label, "lines": lines})
            pr["addresses"].append({"key": k, "form": form, "lines": lines, "label": label})
        for k in ["main", "fax"] + (["work"] if rng.random() < 0.4 else []):
            ph = person["phones"][k]
            t = phone_text(rng, ph, lang, intl=rng.random() < 0.5)
            spec["phones"].append(t)
            pr["phones"].append({"kind": k, "number": ph["e164"], "extension": ph["extension"] if k == "work" else None, "text": t})
        ems = [person["generic_email"]] + ([person["emails"][0]] if rng.random() < 0.4 else [])
        spec["emails"] = ems
        pr["emails"] = [{"address": e, "text": e} for e in ems]
        if rng.random() < 0.6:
            spec["webs"] = [person["website"]]
            pr["websites"] = [{"url": person["website"], "text": person["website"]}]
        spec["logo"] = _logo(person, rng, "small", None)
    elif bt == "c":
        spec["template"], spec["script"] = "back_logo", "en"
        brand = person["flags"]["wordmark_brand"]
        spec["logo"] = _logo(person, rng, "large", "brand" if brand else "short")
        if brand:
            pr["distractors"].append(spec["logo"]["text"])
        spec["webs"] = [person["website"]]
        pr["websites"] = [{"url": person["website"], "text": person["website"]}]
        payload = "https://" + person["website"].replace("https://", "")
        spec["qr"], spec["qr_payload"] = qr_data_uri(payload), payload
        if rng.random() < 0.5:
            if person["script"] in ("zh-Hant", "zh-Hans") and comp["cjk"]:
                spec["company_main"] = comp["cjk"]; pr["company_cjk"] = comp["cjk"]; spec["script"] = "mixed"
            else:
                spec["company_main"] = comp["en"]; pr["company"] = comp["en"]
        if rng.random() < 0.4:
            dl = "en" if person["script"] == "en" else var
            spec["slogan"] = rng.choice(person["slogans"][dl])
            pr["distractors"].append(spec["slogan"])
            if dl != "en":
                spec["script"] = "mixed"
    else:  # d: decorative
        spec["template"] = "back_decor"
        spec["logo"] = _logo(person, rng, "large", "brand" if person["flags"]["wordmark_brand"] else None)
        if spec["logo"]["text"]:
            pr["distractors"].append(spec["logo"]["text"])
        dl = "en" if person["script"] == "en" or rng.random() < 0.4 else var
        r = rng.random()
        if r < 0.45:
            spec["decor"] = rng.choice(D.DECOR_TEXT[dl])
        elif r < 0.8:
            spec["decor"] = rng.choice(person["slogans"][dl])
        if spec["decor"]:
            pr["distractors"].append(spec["decor"])
        spec["script"] = dl if spec["decor"] else ("en" if person["script"] == "en" else var if person["script"] != "mixed" else "mixed")
    spec["printed"] = pr
    return spec


def build_sides(person, rng, counts):
    layout = person["layout"]
    tmpl = _pick_template(rng, person["script"], layout, counts)
    if person["flags"]["avatar"] is False and tmpl == "startup" and rng.random() < 0.5:
        person["flags"]["avatar"] = True
    front = build_full_side(person, rng, person["script"], "front", tmpl, layout)
    sides = [front]
    if person["back_type"]:
        sides.append(build_back(person, rng, front, counts))
    return sides

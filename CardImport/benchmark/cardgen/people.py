"""Person generation: fictional identities with full (potential) contact data.

A Person carries every value that MAY be printed. What actually ends up on a card is decided
in sides.py; the ground truth is the union of what was printed on that person's photos.
"""
import re
from . import data as D

# ---------------------------------------------------------------- phone numbers

def _digits(rng, n, first=None):
    s = "".join(str(rng.randint(0, 9)) for _ in range(n))
    if first is not None:
        s = first + s[1:]
    return s


def make_phone(rng, cc, kind, area=None, used=None):
    """Return a phone dict {kind, cc, area, local, e164, extension}."""
    used = used if used is not None else set()
    for _ in range(100):
        if cc in ("CA", "US"):
            if cc == "US":
                area = "212"
            elif kind == "mobile":
                area = "604" if area == "604" else rng.choice(["647", "416", "905"])
            area = area or "416"
            local = "55501" + "%02d" % rng.randint(0, 99)
            e164 = "+1" + area + local
        elif cc == "TW":
            if kind == "mobile":
                area = ""
                local = "9" + _digits(rng, 8)
                e164 = "+886" + local
            else:
                area = area or "2"
                if area == "3":
                    local = rng.choice("34") + _digits(rng, 6)
                else:
                    local = "2" + _digits(rng, 7)
                e164 = "+886" + area + local
        elif cc == "CN":
            if kind == "mobile":
                area = ""
                local = "1" + rng.choice(["38", "39", "58", "86", "37", "59", "88", "35"]) + _digits(rng, 8)
                e164 = "+86" + local
            else:
                area = area or "21"
                local = rng.choice("5668") + _digits(rng, 7)
                e164 = "+86" + area + local
        elif cc == "HK":
            area = ""
            local = (rng.choice("569") if kind == "mobile" else rng.choice("23")) + _digits(rng, 7)
            e164 = "+852" + local
        else:
            raise ValueError(cc)
        if e164 not in used:
            used.add(e164)
            return {"kind": kind, "cc": cc, "area": area, "local": local, "e164": e164, "extension": None}
    raise RuntimeError("could not allocate phone")


def _grp(s, sizes, sep):
    out, i = [], 0
    for n in sizes:
        out.append(s[i:i + n]); i += n
    return sep.join(out)


def format_number(ph, style):
    """Format the bare number (no label, no extension) in one of several regional styles."""
    cc, area, local = ph["cc"], ph["area"], ph["local"]
    if cc in ("CA", "US"):
        a, b, c = area, local[:3], local[3:]
        return {
            "dots": f"{a}.{b}.{c}", "dash": f"{a}-{b}-{c}", "paren": f"({a}) {b}-{c}",
            "intl": f"+1 {a} {b} {c}", "intl_dash": f"+1-{a}-{b}-{c}", "intl_dot": f"+1.{a}.{b}.{c}",
            "space": f"{a} {b} {c}", "one": f"1-{a}-{b}-{c}",
        }.get(style) or f"{a}-{b}-{c}"
    if cc == "TW":
        if ph["kind"] == "mobile":
            l = local
            return {"dash": f"0{l[:3]}-{l[3:6]}-{l[6:]}", "space": f"0{l[:3]} {l[3:6]} {l[6:]}",
                    "intl": f"+886 {l[:3]} {l[3:6]} {l[6:]}", "intl_dash": f"+886-{l[:3]}-{l[3:6]}-{l[6:]}",
                    "plain": f"0{l}"}.get(style) or f"0{l[:3]}-{l[3:6]}-{l[6:]}"
        l = local
        split = 4 if len(l) == 8 else 3
        h, t = l[:split], l[split:]
        return {"dash": f"0{area}-{h}-{t}", "paren": f"(0{area}) {h}-{t}", "intl_dash": f"+886-{area}-{h}-{t}",
                "intl": f"+886 {area} {h} {t}", "noplus": f"886-{area}-{h}-{t}",
                "compact": f"0{area}-{l}"}.get(style) or f"0{area}-{h}-{t}"
    if cc == "CN":
        if ph["kind"] == "mobile":
            l = local
            return {"space": f"{l[:3]} {l[3:7]} {l[7:]}", "dash": f"{l[:3]}-{l[3:7]}-{l[7:]}", "plain": l,
                    "intl": f"+86 {l[:3]} {l[3:7]} {l[7:]}", "intl_dash": f"+86-{l[:3]}-{l[3:7]}-{l[7:]}"}.get(style) or f"{l[:3]} {l[3:7]} {l[7:]}"
        l = local
        return {"dash": f"0{area}-{l[:4]} {l[4:]}", "paren": f"(0{area}) {l[:4]}-{l[4:]}", "intl": f"+86 {area} {l[:4]} {l[4:]}",
                "intl_dash": f"+86-{area}-{l}", "compact": f"0{area}-{l}"}.get(style) or f"0{area}-{l}"
    if cc == "HK":
        l = local
        return {"space": f"{l[:4]} {l[4:]}", "paren": f"(852) {l[:4]} {l[4:]}", "intl": f"+852 {l[:4]} {l[4:]}",
                "intl_dash": f"+852-{l[:4]}-{l[4:]}"}.get(style) or f"{l[:4]} {l[4:]}"
    raise ValueError(cc)


STYLES = {
    "CA": ["dots", "dash", "paren", "intl", "intl_dash", "intl_dot", "space"],
    "US": ["dots", "dash", "paren", "intl", "one"],
    "TW": ["dash", "paren", "intl_dash", "intl", "noplus", "space", "compact"],
    "CN": ["dash", "space", "paren", "intl", "intl_dash", "compact", "plain"],
    "HK": ["space", "paren", "intl", "intl_dash"],
}
INTL_STYLES = {"CA": ["intl", "intl_dash", "intl_dot"], "US": ["intl"], "TW": ["intl", "intl_dash"],
               "CN": ["intl", "intl_dash"], "HK": ["intl", "paren", "intl_dash"]}

LABELS = {
    "en": {"mobile": ["M", "M:", "Mobile:", "Cell:", "C"], "work": ["T", "T:", "Tel:", "Office:", "Direct:", "P:"],
           "fax": ["F", "F:", "Fax:"], "main": ["Main:", "Main Line:", "Office:"]},
    "en_hk": {"mobile": ["Mobile:", "Mob:", "M:"], "work": ["Tel:", "Direct:", "T:"], "fax": ["Fax:", "F:"], "main": ["General:", "Tel:"]},
    "zh-Hant": {"mobile": ["手機：", "行動電話：", "手機 "], "work": ["電話：", "TEL：", "電話 "], "fax": ["傳真：", "FAX："], "main": ["總機：", "代表號："]},
    "zh-Hant-hk": {"mobile": ["手提：", "手提電話："], "work": ["電話：", "直線："], "fax": ["傳真："], "main": ["總機："]},
    "zh-Hans": {"mobile": ["手机：", "手机 ", "移动电话："], "work": ["电话：", "座机：", "TEL："], "fax": ["传真：", "FAX："], "main": ["总机："]},
    "mixed-Hant": {"mobile": ["手機 Mobile: ", "手機 M: ", "M 手機 "], "work": ["電話 Tel: ", "T 電話 ", "電話 TEL "], "fax": ["傳真 Fax: ", "F 傳真 "], "main": ["總機 Main: "]},
    "mixed-Hans": {"mobile": ["手机 Mob: ", "手机 M: "], "work": ["电话 Tel: ", "T 电话 "], "fax": ["传真 Fax: ", "F 传真 "], "main": ["总机 Main: "]},
}
EXT_FMT = {
    "en": [" ext. {e}", " x{e}", " Ext {e}", " ext {e}"],
    "zh-Hant": [" 分機 {e}", " 轉 {e}", " #{e}", " ext. {e}"],
    "zh-Hans": [" 转 {e}", " 分机 {e}", " ext. {e}"],
}


def phone_text(rng, ph, lang, intl=False, label=True):
    """Full printed phone line: label + number + extension."""
    cc = ph["cc"]
    style = rng.choice(INTL_STYLES[cc] if intl else STYLES[cc])
    if ph["kind"] == "mobile" and cc in ("TW", "CN"):
        style = rng.choice(["intl", "intl_dash"] if intl else ["dash", "space", "plain", "intl", "dash"])
    num = format_number(ph, style)
    if lang == "en":
        lab_set = LABELS["en_hk" if cc == "HK" else "en"]
    elif lang == "zh-Hant":
        lab_set = LABELS["zh-Hant-hk" if cc == "HK" else "zh-Hant"]
    elif lang == "zh-Hans":
        lab_set = LABELS["zh-Hans"]
    else:  # mixed
        lab_set = LABELS["mixed-Hans" if cc == "CN" else "mixed-Hant"]
    lab = rng.choice(lab_set[ph["kind"]]) if label else ""
    if lab and not lab.endswith((" ", "：")):
        lab += " "
    ext = ""
    if ph.get("extension"):
        fam = "en" if lang == "en" else ("zh-Hans" if (lang == "zh-Hans" or (lang == "mixed" and cc == "CN")) else "zh-Hant")
        ext = rng.choice(EXT_FMT[fam]).format(e=ph["extension"])
    return f"{lab}{num}{ext}"


# ---------------------------------------------------------------- address text

def address_lines(addr_form, cc, form, with_country, rng):
    """Return the address as printed lines for form 'en' or 'cjk'."""
    a = addr_form
    if form == "en":
        if cc in ("CA", "US"):
            lines = [a["street"], f"{a['city']}, {a['region']} {a['postal_code']}"]
            if with_country:
                lines.append(a["country"])
        elif cc == "TW":
            lines = [a["street"], f"{a['city']} {a['postal_code']}" + (f", {a['country']}" if with_country else "")]
        elif cc == "CN":
            cr = a["city"] + (f", {a['region']}" if a["region"] else "")
            lines = [a["street"], f"{cr} {a['postal_code']}" + (f", {a['country']}" if with_country else "")]
        else:  # HK
            lines = [a["street"], a["city"] + (f", {a['country']}" if with_country else "")]
        return lines
    # cjk
    if cc == "TW":
        return [(a["country"] + " " if with_country else "") + f"{a['postal_code']} {a['city']}{a['street']}"]
    if cc == "CN":
        line = (a["country"] if with_country else "") + (a["region"] or "") + a["city"] + a["street"]
        return [line, f"邮编：{a['postal_code']}"] if rng.random() < 0.6 else [f"{line}（{a['postal_code']}）"]
    if cc == "HK":
        return [(a["country"] if with_country else "") + a["city"] + a["street"]]
    # CA / US written in Chinese: country, region, city, street
    return [(a["country"] if with_country else "") + (a["region"] or "") + a["city"] + a["street"], f"郵遞區號 {a['postal_code']}"]


# ---------------------------------------------------------------- person

def slug(s):
    return re.sub(r"[^a-z0-9]", "", s.lower())


def email_local(rng, given, family, pinyin=False):
    g, f = slug(given), slug(family)
    if pinyin:
        return rng.choice([f + g, g + "." + f, f + "." + g, f + g[0]])
    return rng.choice([f"{g}.{f}", f"{g[0]}{f}", f"{g}", f"{g}{f[0]}", f"{g}_{f}", f"{g}.{f}"])


def pick_title(rng, industry):
    return rng.choice(D.TITLES[industry])


def pick_dept(rng, industry):
    return rng.choice(D.DEPARTMENTS[industry])

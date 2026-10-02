"""HTML/CSS business-card templates (front templates + three back templates).

Cards are 1050x600 (horizontal) or 600x1050 (vertical) CSS px, i.e. 3.5in x 2in at 300 px/in.
Font sizes use rem with html{font-size: calc(10px*var(--s))} so an in-page fitter can shrink text
that would overflow (window.__fit, called by render_cards.js after fonts load).
Only local system fonts are referenced.
"""
from html import escape

SANS = {
    "en": "'Liberation Sans','DejaVu Sans','Noto Sans CJK TC',sans-serif",
    "zh-Hant": "'Noto Sans CJK TC','WenQuanYi Zen Hei','Liberation Sans',sans-serif",
    "zh-Hans": "'Noto Sans CJK SC','WenQuanYi Zen Hei','Liberation Sans',sans-serif",
}
SERIF = {
    "en": "'Liberation Serif','DejaVu Serif','Noto Serif CJK TC',serif",
    "zh-Hant": "'Noto Serif CJK TC','Liberation Serif',serif",
    "zh-Hans": "'Noto Serif CJK SC','Liberation Serif',serif",
}
FANCY_LATIN = ["'DejaVu Serif'", "'FreeSerif'", "'Liberation Serif'", "'Bitstream Charter'"]
MONO = "'DejaVu Sans Mono','Noto Sans Mono CJK TC',monospace"


def e(s):
    return escape(s or "", quote=True)


def _var(spec):
    if spec["script"] == "en":
        return "en"
    return spec.get("var") or ("zh-Hans" if spec["script"] == "zh-Hans" else "zh-Hant")


def html_lang(spec):
    v = _var(spec)
    return {"en": "en", "zh-Hant": "zh-TW", "zh-Hans": "zh-CN"}[v]


# ---------------------------------------------------------------- SVG pieces

def mark_svg(logo, size, light=False):
    c = "#ffffff" if light else logo["color"]
    c2 = "rgba(255,255,255,.65)" if light else logo["color2"]
    ink = logo["color"] if light else "#ffffff"
    m = logo["mark"]
    ini = e(logo["initials"])
    body = ""
    if m == "circle_initials":
        body = f'<circle cx="50" cy="50" r="47" fill="{c}"/><text x="50" y="64" font-size="40" font-weight="700" text-anchor="middle" fill="{ink}" font-family="Liberation Sans">{ini}</text>'
    elif m == "hexagon":
        body = f'<polygon points="50,3 93,27 93,73 50,97 7,73 7,27" fill="{c}"/><polygon points="50,22 76,37 76,63 50,78 24,63 24,37" fill="none" stroke="{ink}" stroke-width="6"/>'
    elif m == "leaf":
        body = f'<path d="M50 96 C8 70 8 26 50 4 C92 26 92 70 50 96Z" fill="{c}"/><path d="M50 90 L50 18 M50 50 L30 35 M50 65 L70 48" stroke="{ink}" stroke-width="4" fill="none"/>'
    elif m == "wave":
        body = (f'<circle cx="50" cy="50" r="47" fill="{c}"/>'
                + "".join(f'<path d="M12 {y} Q31 {y-12} 50 {y} T88 {y}" stroke="{ink}" stroke-width="6" fill="none"/>' for y in (38, 54, 70)))
    elif m == "fish":
        body = f'<ellipse cx="44" cy="50" rx="34" ry="20" fill="{c}"/><polygon points="72,50 96,30 96,70" fill="{c2}"/><circle cx="26" cy="45" r="4" fill="{ink}"/>'
    elif m == "chevrons":
        body = "".join(f'<polyline points="{10+i*26},15 {38+i*26},50 {10+i*26},85" fill="none" stroke="{c if i!=1 else c2}" stroke-width="12"/>' for i in range(3))
    elif m == "globe":
        body = (f'<circle cx="50" cy="50" r="44" fill="none" stroke="{c}" stroke-width="7"/><ellipse cx="50" cy="50" rx="18" ry="44" fill="none" stroke="{c}" stroke-width="5"/>'
                f'<line x1="6" y1="50" x2="94" y2="50" stroke="{c2}" stroke-width="5"/><line x1="14" y1="30" x2="86" y2="30" stroke="{c}" stroke-width="4"/><line x1="14" y1="70" x2="86" y2="70" stroke="{c}" stroke-width="4"/>')
    elif m == "diamond":
        body = f'<rect x="22" y="22" width="48" height="48" transform="rotate(45 46 46)" fill="{c}"/><rect x="34" y="34" width="48" height="48" transform="rotate(45 58 58)" fill="{c2}" opacity=".8"/>'
    elif m == "bars":
        body = "".join(f'<rect x="{8+i*23}" y="{70-i*18}" width="17" height="{24+i*18}" fill="{c if i%2==0 else c2}"/>' for i in range(4))
    elif m == "dots":
        body = "".join(f'<circle cx="{20+(i%3)*30}" cy="{20+(i//3)*30}" r="{9+((i*7)%5)}" fill="{c if (i+i//3)%2 else c2}"/>' for i in range(9))
    elif m == "pillars":
        body = (f'<polygon points="50,6 94,30 6,30" fill="{c}"/>' + "".join(f'<rect x="{14+i*20}" y="36" width="11" height="44" fill="{c}"/>' for i in range(4))
                + f'<rect x="6" y="84" width="88" height="10" fill="{c2}"/>')
    elif m == "box":
        body = (f'<polygon points="50,6 92,28 50,50 8,28" fill="{c2}"/><polygon points="8,28 50,50 50,96 8,74" fill="{c}"/>'
                f'<polygon points="92,28 50,50 50,96 92,74" fill="{c}" opacity=".75"/>')
    elif m == "seal":
        red = "#ffffff" if light else "#b3261e"
        txt = e(logo["seal"])
        tcol = logo["color"] if light else "#ffffff"
        body = (f'<rect x="4" y="4" width="92" height="92" rx="8" fill="{red}"/><rect x="11" y="11" width="78" height="78" rx="4" fill="none" stroke="{tcol}" stroke-width="3"/>'
                f'<text x="50" y="63" font-size="{38 if len(logo["seal"])>1 else 56}" text-anchor="middle" fill="{tcol}" font-weight="700" '
                f'font-family="Noto Serif CJK TC, Noto Sans CJK TC, Liberation Sans">{txt}</text>')
    return f'<svg width="{size}" height="{size}" viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">{body}</svg>'


def logo_html(logo, size, light=False, direction="row", wm_size=None, wm_font=None, wm_color=None):
    wm = ""
    if logo.get("text"):
        fs = wm_size or max(14, int(size * 0.42))
        col = wm_color or ("#ffffff" if light else logo["color"])
        ff = wm_font or SANS["en"]
        wm = (f'<span class="wm" style="font-size:{fs/10:.1f}rem;color:{col};font-family:{ff};font-weight:700;'
              f'letter-spacing:.06em;white-space:nowrap">{e(logo["text"])}</span>')
    gap = int(size * 0.18)
    return (f'<div class="logo" style="display:flex;flex-direction:{direction};align-items:center;gap:{gap}px">'
            f'{mark_svg(logo, size, light)}{wm}</div>')


def avatar_html(av, size):
    bg = av["bg"]
    return (f'<svg width="{size}" height="{size}" viewBox="0 0 100 100" style="border-radius:50%;flex:none"><defs>'
            f'<radialGradient id="ag" cx=".35" cy=".3" r=".9"><stop offset="0" stop-color="#ffffff" stop-opacity=".45"/><stop offset="1" stop-color="{bg}"/></radialGradient></defs>'
            f'<rect width="100" height="100" fill="url(#ag)"/><rect width="100" height="100" fill="{bg}" opacity=".55"/>'
            f'<circle cx="50" cy="40" r="19" fill="#f1d3b8"/><path d="M50 18 C34 18 30 30 31 40 C36 30 60 28 69 38 C70 26 64 18 50 18Z" fill="#3a2a20"/>'
            f'<path d="M14 100 C16 72 32 64 50 64 C68 64 84 72 86 100Z" fill="#2f3b4f"/><path d="M42 64 L50 78 L58 64Z" fill="#ffffff"/></svg>')


def qr_html(spec, size):
    if not spec.get("qr"):
        return ""
    return f'<img class="qr" src="{spec["qr"]}" style="width:{size}px;height:{size}px;image-rendering:pixelated;flex:none">'


# ---------------------------------------------------------------- text helpers

def contacts(spec):
    return list(spec.get("phones", [])) + list(spec.get("emails", [])) + list(spec.get("webs", [])) + list(spec.get("socials", []))


def lines_html(items, cls="ln"):
    return "".join(f'<div class="{cls}">{e(t)}</div>' for t in items if t)


def addr_html(spec, cls="addr", label_cls="alab"):
    out = []
    for a in spec.get("addresses", []):
        lab = f'<div class="{label_cls}">{e(a["label"])}</div>' if a.get("label") else ""
        out.append(f'<div class="{cls}">{lab}' + "".join(f"<div>{e(l)}</div>" for l in a["lines"]) + "</div>")
    return "".join(out)


def extras(spec):
    """slogan / est / certs as display strings."""
    out = []
    if spec.get("slogan"):
        out.append(spec["slogan"])
    if spec.get("est"):
        out.append(spec["est"])
    if spec.get("certs"):
        out.append("  ·  ".join(spec["certs"]))
    return out


def name_font(spec, rng_choice):
    v = _var(spec)
    main = spec.get("name_main") or ""
    is_cjk = any("㐀" <= ch <= "鿿" for ch in main)
    if spec.get("fancy_font"):
        if is_cjk:
            return SERIF[v if v != "en" else "zh-Hant"], "normal"
        return rng_choice(FANCY_LATIN) + "," + SERIF["en"], "italic"
    return None, "normal"


# ---------------------------------------------------------------- page wrapper

FIT_JS = """
<script>
window.__fit = function(){
  const root = document.documentElement; let s = 1.0;
  const els = Array.from(document.querySelectorAll('.fit'));
  const over = () => els.some(el => el.scrollHeight > el.clientHeight + 1 || el.scrollWidth > el.clientWidth + 1);
  while (over() && s > 0.5) { s = Math.round((s - 0.03) * 100) / 100; root.style.setProperty('--s', s); }
  return s;
};
</script>"""


def page(spec, css, body, w, h, base_font):
    return f"""<!doctype html><html lang="{html_lang(spec)}"><head><meta charset="utf-8">
<style>
:root{{--s:1}}
html{{font-size:calc(10px * var(--s))}}
*{{box-sizing:border-box;margin:0;padding:0}}
html,body{{width:{w}px;height:{h}px;overflow:hidden;background:#fff}}
body{{font-family:{base_font};-webkit-font-smoothing:antialiased;text-rendering:geometricPrecision}}
.card{{width:{w}px;height:{h}px;overflow:hidden;position:relative}}
.ln{{white-space:nowrap}}
{css}
</style></head><body>{body}{FIT_JS}</body></html>"""


# ====================================================================== front templates

def t_minimal_white(spec, rng):
    v = _var(spec); p = spec["palette"]
    sf = 0.8 if spec["small_font"] else 1.0
    nf, ns = name_font(spec, rng.choice)
    accent_side = rng.choice(["left", "top", "none"])
    border = {"left": f"border-left:16px solid {p['brand']};", "top": f"border-top:14px solid {p['brand']};", "none": ""}[accent_side]
    css = f"""
.card{{background:#fff;{border}padding:58px 70px 52px 74px;display:flex;flex-direction:column;justify-content:space-between;color:#222}}
.top{{display:flex;align-items:center;justify-content:space-between;gap:24px}}
.co{{font-size:{2.5*sf:.2f}rem;font-weight:700;color:{p['brand']};letter-spacing:.03em}}
.co2{{font-size:{1.9*sf:.2f}rem;color:#666;margin-top:4px}}
.nm{{font-size:{5.6*sf:.2f}rem;font-weight:700;{f'font-family:{nf};' if nf else ''}font-style:{ns};line-height:1.15;white-space:nowrap}}
.nm2{{font-size:{3.0*sf:.2f}rem;color:#444;margin-top:2px;white-space:nowrap}}
.tt{{font-size:{2.6*sf:.2f}rem;color:{p['brand']};margin-top:10px;white-space:nowrap}}
.tt2,.dp{{font-size:{2.2*sf:.2f}rem;color:#666;margin-top:3px;white-space:nowrap}}
.bot{{display:flex;justify-content:space-between;align-items:flex-end;gap:30px}}
.ct{{font-size:{2.3*sf:.2f}rem;line-height:1.42;color:#333}}
.ad{{font-size:{2.1*sf:.2f}rem;line-height:1.35;color:#444;text-align:right;max-width:470px}}
.addr+.addr{{margin-top:8px}} .alab{{font-weight:700;color:{p['brand']}}}
.ex{{font-size:{1.8*sf:.2f}rem;color:#888;font-style:italic;margin-top:6px}}
"""
    co = f'<div><div class="co">{e(spec["company_main"])}</div>' + (f'<div class="co2">{e(spec["company_sub"])}</div>' if spec.get("company_sub") else "") + "</div>"
    logo = logo_html(spec["logo"], 92 if spec["logo"]["scale"] == "small" else 150, wm_size=26)
    mid = (f'<div><div class="nm">{e(spec["name_main"])}</div>' + (f'<div class="nm2">{e(spec["name_sub"])}</div>' if spec.get("name_sub") else "")
           + f'<div class="tt">{e(spec["title_main"])}</div>' + (f'<div class="tt2">{e(spec["title_sub"])}</div>' if spec.get("title_sub") else "")
           + (f'<div class="dp">{e(spec["dept"])}</div>' if spec.get("dept") else "") + "</div>")
    right = addr_html(spec) + lines_html(extras(spec), "ex")
    qr = qr_html(spec, 150)
    av = avatar_html(spec["avatar"], 130) if spec.get("avatar") else ""
    body = (f'<div class="card fit"><div class="top">{co}<div style="display:flex;gap:18px;align-items:center">{av}{logo}</div></div>{mid}'
            f'<div class="bot"><div class="ct">{lines_html(contacts(spec))}</div><div style="display:flex;gap:20px;align-items:flex-end"><div class="ad">{right}</div>{qr}</div></div></div>')
    return css, body, SANS[v]


def t_navy_gold(spec, rng):
    v = _var(spec)
    bg, gold = rng.choice([("#14213d", "#d4af37"), ("#0d1b2a", "#c9a227"), ("#1b1b1b", "#c5a467"), ("#102a43", "#e0c27a")])
    sf = 0.8 if spec["small_font"] else 1.0
    serif = SERIF[v]
    nf, ns = name_font(spec, rng.choice)
    logo = dict(spec["logo"]); logo["color"] = gold
    css = f"""
.card{{background:{bg};color:#e8e6df;display:grid;grid-template-columns:1.05fr 1fr;padding:60px 64px}}
.l{{display:flex;flex-direction:column;justify-content:space-between;padding-right:40px;border-right:2px solid {gold};overflow:hidden}}
.r{{display:flex;flex-direction:column;justify-content:center;padding-left:44px;gap:14px;overflow:hidden}}
.nm{{font-family:{nf or serif};font-style:{ns};font-size:{5.0*sf:.2f}rem;color:{gold};line-height:1.15;white-space:nowrap}}
.nm2{{font-family:{serif};font-size:{2.8*sf:.2f}rem;color:{gold};opacity:.85;white-space:nowrap}}
.tt{{font-size:{2.3*sf:.2f}rem;letter-spacing:.12em;text-transform:uppercase;margin-top:12px;white-space:nowrap}}
.tt2,.dp{{font-size:{2.1*sf:.2f}rem;opacity:.8;margin-top:4px;white-space:nowrap}}
.co{{font-family:{serif};font-size:{2.4*sf:.2f}rem;color:{gold};letter-spacing:.05em}}
.co2{{font-size:{1.8*sf:.2f}rem;opacity:.8}}
.ct{{font-size:{2.2*sf:.2f}rem;line-height:1.45}}
.addr{{font-size:{2.0*sf:.2f}rem;line-height:1.35;opacity:.92}} .alab{{color:{gold}}}
.ex{{font-size:{1.7*sf:.2f}rem;color:{gold};opacity:.8;letter-spacing:.08em}}
"""
    left = (f'<div class="l fit"><div>{logo_html(logo, 84 if logo["scale"]=="small" else 140, wm_size=24, wm_color=gold, wm_font=serif)}</div>'
            f'<div><div class="nm">{e(spec["name_main"])}</div>' + (f'<div class="nm2">{e(spec["name_sub"])}</div>' if spec.get("name_sub") else "")
            + f'<div class="tt">{e(spec["title_main"])}</div>' + (f'<div class="tt2">{e(spec["title_sub"])}</div>' if spec.get("title_sub") else "")
            + (f'<div class="dp">{e(spec["dept"])}</div>' if spec.get("dept") else "") + '</div>'
            + f'<div><div class="co">{e(spec["company_main"])}</div>' + (f'<div class="co2">{e(spec["company_sub"])}</div>' if spec.get("company_sub") else "") + '</div></div>')
    right = (f'<div class="r fit"><div class="ct">{lines_html(contacts(spec))}</div>{addr_html(spec)}'
             + (f'<div style="display:flex;gap:16px;align-items:center">{qr_html(spec, 120)}<div>{lines_html(extras(spec), "ex")}</div></div>' if (spec.get("qr") or extras(spec)) else "")
             + '</div>')
    return css, f'<div class="card">{left}{right}</div>', SANS[v]


def t_color_band(spec, rng):
    v = _var(spec); p = spec["palette"]
    sf = 0.8 if spec["small_font"] else 1.0
    nf, ns = name_font(spec, rng.choice)
    big = spec["logo"]["scale"] == "large"
    side = rng.choice(["left", "right"])
    cols = "390px 1fr" if side == "left" else "1fr 390px"
    css = f"""
.card{{display:grid;grid-template-columns:{cols};background:#fbfbf8}}
.band{{background:{p['brand']};color:#fff;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:22px;padding:40px 30px;text-align:center;overflow:hidden}}
.bco{{font-size:{2.6*sf:.2f}rem;font-weight:700;line-height:1.25}} .bco2{{font-size:{1.8*sf:.2f}rem;opacity:.85}}
.bsl{{font-size:{1.7*sf:.2f}rem;opacity:.85;font-style:italic}}
.main{{padding:56px 60px;display:flex;flex-direction:column;justify-content:center;gap:14px;overflow:hidden}}
.nm{{font-size:{5.0*sf:.2f}rem;font-weight:700;color:#1d1d1d;{f'font-family:{nf};' if nf else ''}font-style:{ns};white-space:nowrap;line-height:1.1}}
.nm2{{font-size:{2.8*sf:.2f}rem;color:#555;white-space:nowrap}}
.tt{{font-size:{2.4*sf:.2f}rem;color:{p['brand']};white-space:nowrap}} .tt2,.dp{{font-size:{2.0*sf:.2f}rem;color:#666;white-space:nowrap}}
.rule{{height:3px;width:90px;background:{p['accent']};margin:6px 0}}
.ct{{font-size:{2.2*sf:.2f}rem;line-height:1.42;color:#333}}
.addr{{font-size:{2.0*sf:.2f}rem;line-height:1.35;color:#444}} .addr+.addr{{margin-top:6px}} .alab{{font-weight:700;color:{p['brand']}}}
.ex{{font-size:{1.7*sf:.2f}rem;color:#888}}
"""
    band = (f'<div class="band fit">{logo_html(spec["logo"], 170 if big else 110, light=True, direction="column", wm_size=30)}'
            f'<div><div class="bco">{e(spec["company_main"])}</div>' + (f'<div class="bco2">{e(spec["company_sub"])}</div>' if spec.get("company_sub") else "") + "</div>"
            + (f'<div class="bsl">{e(spec["slogan"])}</div>' if spec.get("slogan") else "") + "</div>")
    ex = [x for x in extras(spec) if x != spec.get("slogan")]
    av = avatar_html(spec["avatar"], 120) if spec.get("avatar") else ""
    main = (f'<div class="main fit"><div style="display:flex;gap:22px;align-items:center">{av}<div><div class="nm">{e(spec["name_main"])}</div>'
            + (f'<div class="nm2">{e(spec["name_sub"])}</div>' if spec.get("name_sub") else "") + "</div></div>"
            + f'<div><div class="tt">{e(spec["title_main"])}</div>' + (f'<div class="tt2">{e(spec["title_sub"])}</div>' if spec.get("title_sub") else "")
            + (f'<div class="dp">{e(spec["dept"])}</div>' if spec.get("dept") else "") + '</div><div class="rule"></div>'
            + f'<div style="display:flex;gap:24px;align-items:flex-end;justify-content:space-between"><div><div class="ct">{lines_html(contacts(spec))}</div>{addr_html(spec)}{lines_html(ex, "ex")}</div>{qr_html(spec, 130)}</div></div>')
    body = f'<div class="card">{band}{main}</div>' if side == "left" else f'<div class="card">{main}{band}</div>'
    return css, body, SANS[v]


def t_logo_heavy(spec, rng):
    v = _var(spec); p = spec["palette"]
    sf = 0.78 if spec["small_font"] else 0.92
    nf, ns = name_font(spec, rng.choice)
    css = f"""
.card{{background:#fff;display:grid;grid-template-columns:1.15fr 1fr;padding:50px 56px;gap:40px}}
.lg{{display:flex;align-items:center;justify-content:center;flex-direction:column;gap:18px;overflow:hidden}}
.info{{display:flex;flex-direction:column;justify-content:center;gap:10px;overflow:hidden;border-left:2px solid #e3e3e3;padding-left:36px}}
.nm{{font-size:{4.2*sf:.2f}rem;font-weight:700;{f'font-family:{nf};' if nf else ''}font-style:{ns};white-space:nowrap}}
.nm2{{font-size:{2.6*sf:.2f}rem;color:#555;white-space:nowrap}}
.tt{{font-size:{2.2*sf:.2f}rem;color:{p['brand']};white-space:nowrap}} .tt2,.dp{{font-size:{2.0*sf:.2f}rem;color:#777;white-space:nowrap}}
.co{{font-size:{2.1*sf:.2f}rem;font-weight:700;color:#333;margin-top:8px}} .co2{{font-size:{1.8*sf:.2f}rem;color:#777}}
.ct{{font-size:{2.1*sf:.2f}rem;line-height:1.4;color:#333;margin-top:8px}}
.addr{{font-size:{1.9*sf:.2f}rem;line-height:1.3;color:#555}} .alab{{font-weight:700}}
.ex{{font-size:{1.7*sf:.2f}rem;color:{p['brand']};text-align:center;letter-spacing:.06em}}
"""
    lg = (f'<div class="lg fit">{logo_html(spec["logo"], 250, direction="column", wm_size=46)}{lines_html(extras(spec), "ex")}</div>')
    info = (f'<div class="info fit"><div class="nm">{e(spec["name_main"])}</div>' + (f'<div class="nm2">{e(spec["name_sub"])}</div>' if spec.get("name_sub") else "")
            + f'<div class="tt">{e(spec["title_main"])}</div>' + (f'<div class="tt2">{e(spec["title_sub"])}</div>' if spec.get("title_sub") else "")
            + (f'<div class="dp">{e(spec["dept"])}</div>' if spec.get("dept") else "")
            + f'<div class="co">{e(spec["company_main"])}</div>' + (f'<div class="co2">{e(spec["company_sub"])}</div>' if spec.get("company_sub") else "")
            + f'<div class="ct">{lines_html(contacts(spec))}</div>{addr_html(spec)}'
            + (f'<div>{qr_html(spec, 110)}</div>' if spec.get("qr") else "") + '</div>')
    return css, f'<div class="card">{lg}{info}</div>', SANS[v]


def t_bank_style(spec, rng):
    v = _var(spec); p = spec["palette"]
    bar = rng.choice(["#7b1e2b", "#0f4c3a", "#1f3a68", p["brand"]])
    sf = 0.8 if spec["small_font"] else 0.92
    serif = SERIF[v]
    nf, ns = name_font(spec, rng.choice)
    logo = dict(spec["logo"])
    css = f"""
.card{{background:#fff;display:flex;flex-direction:column}}
.bar{{background:{bar};color:#fff;height:116px;display:flex;align-items:center;gap:22px;padding:0 50px;flex:none}}
.bco{{font-family:{serif};font-size:{2.7*sf:.2f}rem;font-weight:700;letter-spacing:.04em;white-space:nowrap}} .bco2{{font-size:{1.8*sf:.2f}rem;opacity:.85;white-space:nowrap}}
.body{{flex:1;display:grid;grid-template-columns:1fr 1.1fr;gap:34px;padding:34px 50px 22px;overflow:hidden}}
.nm{{font-family:{nf or serif};font-style:{ns};font-size:{4.6*sf:.2f}rem;font-weight:700;color:#1a1a1a;white-space:nowrap}}
.nm2{{font-size:{2.5*sf:.2f}rem;color:#444;white-space:nowrap}}
.tt{{font-size:{2.2*sf:.2f}rem;color:{bar};margin-top:10px;white-space:nowrap}} .tt2,.dp{{font-size:{1.9*sf:.2f}rem;color:#555;white-space:nowrap}}
.ct{{font-size:{2.0*sf:.2f}rem;line-height:1.42;color:#222}}
.addr{{font-size:{1.8*sf:.2f}rem;line-height:1.3;color:#444;margin-top:8px}} .alab{{color:{bar};font-weight:700}}
.foot{{flex:none;border-top:1px solid #ddd;margin:0 50px;padding:10px 0 16px;font-size:{1.5*sf:.2f}rem;color:#888;display:flex;justify-content:space-between;gap:20px}}
"""
    bar_html = (f'<div class="bar">{logo_html(logo, 76, light=True)}<div><div class="bco">{e(spec["company_main"])}</div>'
                + (f'<div class="bco2">{e(spec["company_sub"])}</div>' if spec.get("company_sub") else "") + '</div></div>')
    left = (f'<div class="fit" style="overflow:hidden"><div class="nm">{e(spec["name_main"])}</div>' + (f'<div class="nm2">{e(spec["name_sub"])}</div>' if spec.get("name_sub") else "")
            + f'<div class="tt">{e(spec["title_main"])}</div>' + (f'<div class="tt2">{e(spec["title_sub"])}</div>' if spec.get("title_sub") else "")
            + (f'<div class="dp">{e(spec["dept"])}</div>' if spec.get("dept") else "")
            + (f'<div style="margin-top:14px">{avatar_html(spec["avatar"], 110)}</div>' if spec.get("avatar") else "") + '</div>')
    right = (f'<div class="fit" style="overflow:hidden;display:flex;gap:16px"><div style="flex:1;min-width:0"><div class="ct">{lines_html(contacts(spec))}</div>{addr_html(spec)}</div>'
             + (f'<div>{qr_html(spec, 120)}</div>' if spec.get("qr") else "") + '</div>')
    ex = extras(spec)
    foot = f'<div class="foot">' + "".join(f"<span>{e(x)}</span>" for x in ex) + "</div>" if ex else '<div style="height:24px"></div>'
    return css, f'<div class="card fit">{bar_html}<div class="body">{left}{right}</div>{foot}</div>', SANS[v]


def t_startup(spec, rng):
    v = _var(spec); p = spec["palette"]
    g1, g2, neon = rng.choice([("#0f172a", "#312e81", "#5eead4"), ("#111827", "#1f2937", "#f472b6"), ("#052e2b", "#0f766e", "#fde047"), ("#1e1b4b", "#4c1d95", "#a5f3fc")])
    sf = 0.8 if spec["small_font"] else 0.95
    css = f"""
.card{{background:linear-gradient(135deg,{g1},{g2});color:#f1f5f9;padding:54px 60px;display:flex;flex-direction:column;justify-content:space-between}}
.top{{display:flex;align-items:center;gap:26px}}
.nm{{font-size:{4.8*sf:.2f}rem;font-weight:700;letter-spacing:-.01em;white-space:nowrap}}
.nm2{{font-size:{2.6*sf:.2f}rem;opacity:.8;white-space:nowrap}}
.tt{{font-size:{2.2*sf:.2f}rem;color:{neon};margin-top:6px;white-space:nowrap}} .tt2,.dp{{font-size:{1.9*sf:.2f}rem;opacity:.75;white-space:nowrap}}
.mid{{display:flex;justify-content:space-between;align-items:flex-end;gap:30px}}
.ct{{font-family:{MONO};font-size:{1.95*sf:.2f}rem;line-height:1.55}}
.ct .ln::before{{content:'›  ';color:{neon}}}
.addr{{font-size:{1.8*sf:.2f}rem;opacity:.85;line-height:1.3;margin-top:8px}} .alab{{color:{neon}}}
.co{{font-size:{2.0*sf:.2f}rem;font-weight:700;letter-spacing:.1em;text-transform:uppercase;color:{neon}}}
.co2{{font-size:{1.7*sf:.2f}rem;opacity:.8}}
.ex{{font-size:{1.6*sf:.2f}rem;opacity:.7}}
"""
    logo = dict(spec["logo"]); logo["color"] = neon; logo["color2"] = "#ffffff"
    av = avatar_html(spec["avatar"], 130) if spec.get("avatar") else mark_svg(logo, 110)
    top = (f'<div class="top">{av}<div><div class="nm">{e(spec["name_main"])}</div>' + (f'<div class="nm2">{e(spec["name_sub"])}</div>' if spec.get("name_sub") else "")
           + f'<div class="tt">{e(spec["title_main"])}</div>' + (f'<div class="tt2">{e(spec["title_sub"])}</div>' if spec.get("title_sub") else "")
           + (f'<div class="dp">{e(spec["dept"])}</div>' if spec.get("dept") else "") + '</div></div>')
    qr = f'<div style="background:#fff;padding:8px;border-radius:10px">{qr_html(spec, 130)}</div>' if spec.get("qr") else ""
    mid = f'<div class="mid"><div><div class="ct">{lines_html(contacts(spec))}</div>{addr_html(spec)}</div>{qr}</div>'
    bottom = (f'<div style="display:flex;justify-content:space-between;align-items:flex-end;gap:20px"><div><div class="co">{e(spec["company_main"])}</div>'
              + (f'<div class="co2">{e(spec["company_sub"])}</div>' if spec.get("company_sub") else "") + f'</div><div style="text-align:right">{lines_html(extras(spec), "ex")}</div></div>')
    return css, f'<div class="card fit">{top}{mid}{bottom}</div>', SANS[v]


def t_japanese_minimal(spec, rng):
    v = _var(spec); p = spec["palette"]
    sf = 0.85 if spec["small_font"] else 1.0
    serif = SERIF[v]
    nf, ns = name_font(spec, rng.choice)
    logo = dict(spec["logo"])
    if v != "en" and logo["mark"] != "seal" and rng.random() < 0.6:
        logo["mark"] = "seal"
    name_is_cjk = any("\u3400" <= ch <= "\u9fff" for ch in (spec.get("name_main") or ""))
    nls = ".3em" if name_is_cjk else ".05em"
    css = f"""
.card{{background:#faf8f3;color:#2b2b2b;padding:46px 60px 40px;display:flex;flex-direction:column;justify-content:space-between;align-items:center;text-align:center}}
.hd{{width:100%;display:flex;justify-content:space-between;align-items:flex-start}}
.co{{font-size:{2.0*sf:.2f}rem;letter-spacing:.2em;color:#555;text-align:left}} .co2{{font-size:{1.6*sf:.2f}rem;color:#888;text-align:left}}
.tt{{font-size:{1.9*sf:.2f}rem;letter-spacing:.25em;color:#666}} .tt2,.dp{{font-size:{1.7*sf:.2f}rem;color:#888;letter-spacing:.1em}}
.nm{{font-family:{nf or serif};font-style:{ns};font-size:{5.6*sf:.2f}rem;letter-spacing:{nls};margin:8px 0 2px;white-space:nowrap;font-weight:400}}
.nm2{{font-size:{2.2*sf:.2f}rem;letter-spacing:.2em;color:#666;white-space:nowrap}}
.ft{{font-size:{1.65*sf:.2f}rem;color:#555;line-height:1.6}}
.ft .row{{white-space:nowrap}}
.ex{{font-size:{1.45*sf:.2f}rem;color:#999;letter-spacing:.1em}}
"""
    ct = contacts(spec)
    rows = [" ｜ ".join(ct[i:i + 2]) for i in range(0, len(ct), 2)]
    addr_rows = [" ".join(a["lines"]) for a in spec.get("addresses", [])]
    hd = (f'<div class="hd"><div><div class="co">{e(spec["company_main"])}</div>' + (f'<div class="co2">{e(spec["company_sub"])}</div>' if spec.get("company_sub") else "")
          + f'</div>{logo_html(dict(logo, text=None), 64)}</div>')
    mid = (f'<div><div class="tt">{e(spec["title_main"])}</div>' + (f'<div class="tt2">{e(spec["title_sub"])}</div>' if spec.get("title_sub") else "")
           + f'<div class="nm">{e(spec["name_main"])}</div>' + (f'<div class="nm2">{e(spec["name_sub"])}</div>' if spec.get("name_sub") else "")
           + (f'<div class="dp">{e(spec["dept"])}</div>' if spec.get("dept") else "") + '</div>')
    ft = (f'<div class="ft">' + "".join(f'<div class="row">{e(r)}</div>' for r in addr_rows + rows) + lines_html(extras(spec), "ex") + "</div>")
    wm_note = f'<div class="ex">{e(spec["logo"]["text"])}</div>' if spec["logo"].get("text") else ""
    qr = f'<div style="position:absolute;right:40px;bottom:40px">{qr_html(spec, 110)}</div>' if spec.get("qr") else ""
    return css, f'<div class="card fit">{hd}{mid}{wm_note}{ft}{qr}</div>', SANS[v]


def t_bilingual_columns(spec, rng):
    """Mixed-script card: CJK column | English column (requires mixed spec)."""
    v = _var(spec); p = spec["palette"]
    sf = 0.8 if spec["small_font"] else 0.92
    cj = SANS[v if v != "en" else "zh-Hant"]
    def is_cjk(s):
        return any("㐀" <= ch <= "鿿" for ch in (s or ""))
    names = [spec.get("name_main"), spec.get("name_sub")]
    comps = [spec.get("company_main"), spec.get("company_sub")]
    titles = [spec.get("title_main"), spec.get("title_sub")]
    pick = lambda pair, want_cjk: next((x for x in pair if x and is_cjk(x) == want_cjk), None)
    addr_c = [a for a in spec.get("addresses", []) if any(is_cjk(l) for l in a["lines"])]
    addr_e = [a for a in spec.get("addresses", []) if a not in addr_c]
    css = f"""
.card{{background:#fff;padding:44px 56px 40px;display:flex;flex-direction:column;gap:18px}}
.hd{{display:flex;align-items:center;gap:20px;border-bottom:3px solid {p['brand']};padding-bottom:14px}}
.hc{{font-size:{2.5*sf:.2f}rem;font-weight:700;color:{p['brand']};white-space:nowrap}} .he{{font-size:{1.8*sf:.2f}rem;color:#555;white-space:nowrap}}
.cols{{flex:1;display:grid;grid-template-columns:1fr 1fr;gap:34px;overflow:hidden}}
.col{{overflow:hidden}} .col+.col{{border-left:1px solid #ddd;padding-left:34px}}
.nm{{font-size:{4.4*sf:.2f}rem;font-weight:700;white-space:nowrap}}
.tt{{font-size:{2.2*sf:.2f}rem;color:{p['brand']};white-space:nowrap;margin-top:4px}}
.dp{{font-size:{1.9*sf:.2f}rem;color:#666;white-space:nowrap}}
.addr{{font-size:{1.8*sf:.2f}rem;color:#444;line-height:1.3;margin-top:10px}} .alab{{font-weight:700}}
.ft{{font-size:{2.0*sf:.2f}rem;color:#333;display:flex;flex-wrap:wrap;column-gap:30px;row-gap:2px}}
.ex{{font-size:{1.6*sf:.2f}rem;color:#999}}
"""
    hd = (f'<div class="hd">{logo_html(dict(spec["logo"], text=None), 74)}<div><div class="hc" style="font-family:{cj}">{e(pick(comps, True) or comps[0])}</div>'
          f'<div class="he">{e(pick(comps, False) or "")}</div></div><div style="margin-left:auto;text-align:right">{lines_html(extras(spec), "ex")}</div></div>')
    c1 = (f'<div class="col fit" style="font-family:{cj}"><div class="nm">{e(pick(names, True))}</div><div class="tt">{e(pick(titles, True))}</div>'
          + (f'<div class="dp">{e(spec["dept"])}</div>' if spec.get("dept") else "") + addr_html({"addresses": addr_c}) + "</div>")
    c2 = (f'<div class="col fit"><div class="nm">{e(pick(names, False))}</div><div class="tt">{e(pick(titles, False))}</div>'
          + addr_html({"addresses": addr_e}) + (qr_html(spec, 110) if spec.get("qr") else "") + "</div>")
    ft = f'<div class="ft fit">' + "".join(f'<span class="ln">{e(t)}</span>' for t in contacts(spec)) + "</div>"
    return css, f'<div class="card fit">{hd}<div class="cols">{c1}{c2}</div>{ft}</div>', cj


# ---------------------------------------------------------------- vertical templates (600x1050)

def t_vertical_cjk(spec, rng):
    """Traditional vertical writing (writing-mode: vertical-rl)."""
    v = _var(spec); p = spec["palette"]
    sf = 0.85 if spec["small_font"] else 1.0
    serif = SERIF[v if v != "en" else "zh-Hant"]
    font = serif if (spec["fancy_font"] or rng.random() < 0.5) else SANS[v if v != "en" else "zh-Hant"]
    upright = rng.random() < 0.5
    css = f"""
.card{{background:#fdfcf8;color:#222;padding:56px 50px 40px}}
.vr{{writing-mode:vertical-rl;height:820px;width:100%;font-family:{font};display:flex;flex-direction:column;flex-wrap:nowrap}}
.co{{font-size:{2.6*sf:.2f}rem;color:{p['brand']};letter-spacing:.12em;margin-left:22px;align-self:flex-start}}
.tt{{font-size:{2.4*sf:.2f}rem;letter-spacing:.2em;margin-left:16px;align-self:flex-start;padding-top:{rng.choice([60, 120, 160])}px}}
.dp{{font-size:{2.1*sf:.2f}rem;letter-spacing:.15em;color:#555;margin-left:12px;align-self:flex-start;padding-top:{rng.choice([60, 120, 160])}px}}
.nm{{font-size:{6.4*sf:.2f}rem;font-weight:700;letter-spacing:.35em;margin-left:40px;margin-right:10px;align-self:center;white-space:nowrap}}
.ad{{font-size:{1.95*sf:.2f}rem;line-height:1.55;margin-left:6px;color:#333;align-self:{rng.choice(["flex-end", "flex-start"])}}}
.ad .alab{{color:{p['brand']}}}
.ph{{font-size:{1.95*sf:.2f}rem;line-height:1.55;color:#333;align-self:inherit;{'text-orientation:upright;letter-spacing:-.05em;' if upright else ''}}}
.cg{{display:flex;flex-direction:column;align-self:stretch;justify-content:flex-start}}
.cg>div{{align-self:{rng.choice(["flex-end", "flex-start"])}}}
.ex{{font-size:{1.7*sf:.2f}rem;color:#999;letter-spacing:.1em;align-self:flex-start;padding-top:40px}}
.foot{{position:absolute;left:46px;bottom:36px;display:flex;align-items:flex-end;gap:14px}}
"""
    blocks = [f'<div class="co">{e(spec["company_main"])}</div>']
    blocks.append(f'<div class="tt">{e(spec["title_main"])}</div>')
    if spec.get("dept"):
        blocks.append(f'<div class="dp">{e(spec["dept"])}</div>')
    blocks.append(f'<div class="nm">{e(spec["name_main"])}</div>')
    grp = []
    for a in spec.get("addresses", []):
        grp.append('<div class="ad">' + (f'<span class="alab">{e(a["label"])}：</span>' if a.get("label") else "") + e("　".join(a["lines"])) + "</div>")
    for t in spec.get("phones", []):
        grp.append(f'<div class="ph">{e(t)}</div>')
    grp += [f'<div class="ad">{e(t)}</div>' for t in spec.get("emails", []) + spec.get("webs", []) + spec.get("socials", [])]
    blocks.append(f'<div class="cg">{"".join(grp)}</div>')
    blocks += [f'<div class="ex">{e(t)}</div>' for t in extras(spec)]
    foot = f'<div class="foot">{logo_html(spec["logo"], 70, wm_size=22)}{qr_html(spec, 110)}</div>'
    return css, f'<div class="card fit"><div class="vr fit">{"".join(blocks)}</div>{foot}</div>', SANS[v if v != "en" else "zh-Hant"]


def t_portrait_modern(spec, rng):
    v = _var(spec); p = spec["palette"]
    sf = 0.82 if spec["small_font"] else 0.95
    nf, ns = name_font(spec, rng.choice)
    css = f"""
.card{{background:#fff;display:flex;flex-direction:column;align-items:center;text-align:center}}
.hdr{{width:100%;min-height:{300 if spec.get('avatar') else 250}px;background:{p['brand']};display:flex;align-items:center;justify-content:center;flex:none;flex-direction:column;gap:10px;color:#fff;padding:24px 0 {80 if spec.get('avatar') else 24}px}}
.grow{{flex:1}}
.hco{{font-size:{2.1*sf:.2f}rem;font-weight:700;padding:0 30px;line-height:1.25}}
.av{{margin-top:-70px;border:8px solid #fff;border-radius:50%;flex:none;display:flex}}
.nm{{font-size:{4.6*sf:.2f}rem;font-weight:700;margin-top:22px;{f'font-family:{nf};' if nf else ''}font-style:{ns};white-space:nowrap}}
.nm2{{font-size:{2.6*sf:.2f}rem;color:#555;white-space:nowrap}}
.tt{{font-size:{2.3*sf:.2f}rem;color:{p['brand']};margin-top:8px;white-space:nowrap}} .tt2,.dp{{font-size:{2.0*sf:.2f}rem;color:#666;white-space:nowrap}}
.rule{{width:80px;height:3px;background:{p['accent']};margin:22px 0}}
.ct{{font-size:{2.15*sf:.2f}rem;line-height:1.5;color:#333;padding:0 40px}}
.addr{{font-size:{1.95*sf:.2f}rem;line-height:1.35;color:#555;margin-top:12px;padding:0 44px}} .alab{{font-weight:700;color:{p['brand']}}}
.ex{{font-size:{1.7*sf:.2f}rem;color:#999;margin-top:6px;padding:0 30px}}
.co2{{font-size:{1.7*sf:.2f}rem;opacity:.9}}
"""
    hdr = (f'<div class="hdr">{logo_html(spec["logo"], 96 if spec["logo"]["scale"]=="small" else 140, light=True, direction="column", wm_size=26)}'
           f'<div class="hco">{e(spec["company_main"])}</div>' + (f'<div class="co2">{e(spec["company_sub"])}</div>' if spec.get("company_sub") else "") + '</div>')
    av = f'<div class="av">{avatar_html(spec["avatar"], 150)}</div>' if spec.get("avatar") else '<div style="height:20px"></div>'
    body = (f'<div class="card fit">{hdr}{av}<div class="nm">{e(spec["name_main"])}</div>' + (f'<div class="nm2">{e(spec["name_sub"])}</div>' if spec.get("name_sub") else "")
            + f'<div class="tt">{e(spec["title_main"])}</div>' + (f'<div class="tt2">{e(spec["title_sub"])}</div>' if spec.get("title_sub") else "")
            + (f'<div class="dp">{e(spec["dept"])}</div>' if spec.get("dept") else "")
            + f'<div class="rule"></div><div class="grow"></div><div class="ct">{lines_html(contacts(spec))}</div>{addr_html(spec)}{lines_html(extras(spec), "ex")}'
            + (f'<div style="margin-top:18px">{qr_html(spec, 140)}</div>' if spec.get("qr") else "") + '<div class="grow"></div></div>')
    return css, body, SANS[v]


def t_portrait_classic(spec, rng):
    v = _var(spec); p = spec["palette"]
    sf = 0.82 if spec["small_font"] else 0.95
    serif = SERIF[v]
    nf, ns = name_font(spec, rng.choice)
    paper = rng.choice(["#ffffff", "#f7f3ea", "#eef2f5"])
    css = f"""
.card{{background:{paper};padding:70px 46px 54px;display:flex;flex-direction:column;align-items:center;justify-content:space-between;text-align:center;border:10px solid {paper};outline:2px solid {p['brand']};outline-offset:-26px}}
.co{{font-family:{serif};font-size:{2.4*sf:.2f}rem;color:{p['brand']};margin-top:16px;line-height:1.25}} .co2{{font-size:{1.8*sf:.2f}rem;color:#666}}
.nm{{font-family:{nf or serif};font-style:{ns};font-size:{5.0*sf:.2f}rem;font-weight:700;color:#1d1d1d;white-space:nowrap}}
.nm2{{font-size:{2.6*sf:.2f}rem;color:#555;white-space:nowrap}}
.tt{{font-size:{2.2*sf:.2f}rem;letter-spacing:.12em;color:#444;margin-top:10px;white-space:nowrap}} .tt2,.dp{{font-size:{1.9*sf:.2f}rem;color:#777;white-space:nowrap}}
.ct{{font-size:{2.05*sf:.2f}rem;line-height:1.5;color:#333}}
.addr{{font-size:{1.85*sf:.2f}rem;line-height:1.35;color:#555;margin-top:10px}} .alab{{color:{p['brand']}}}
.ex{{font-size:{1.6*sf:.2f}rem;color:#999;font-style:italic}}
"""
    top = (f'<div>{logo_html(spec["logo"], 110 if spec["logo"]["scale"]=="small" else 170, direction="column", wm_size=28, wm_font=serif)}'
           f'<div class="co">{e(spec["company_main"])}</div>' + (f'<div class="co2">{e(spec["company_sub"])}</div>' if spec.get("company_sub") else "") + '</div>')
    mid = (f'<div>' + (avatar_html(spec["avatar"], 140) if spec.get("avatar") else "") + f'<div class="nm">{e(spec["name_main"])}</div>' + (f'<div class="nm2">{e(spec["name_sub"])}</div>' if spec.get("name_sub") else "")
           + f'<div class="tt">{e(spec["title_main"])}</div>' + (f'<div class="tt2">{e(spec["title_sub"])}</div>' if spec.get("title_sub") else "")
           + (f'<div class="dp">{e(spec["dept"])}</div>' if spec.get("dept") else "") + '</div>')
    bot = (f'<div><div class="ct">{lines_html(contacts(spec))}</div>{addr_html(spec)}' + (f'<div style="margin-top:12px">{qr_html(spec, 120)}</div>' if spec.get("qr") else "")
           + lines_html(extras(spec), "ex") + '</div>')
    return css, f'<div class="card fit">{top}{mid}{bot}</div>', SANS[v]


# ====================================================================== back templates

def t_back_contact(spec, rng):
    v = _var(spec); p = spec["palette"]
    vert = spec["layout"] == "vertical"
    tint = rng.choice(["#ffffff", "#f4f6f8", p["brand"]])
    dark = tint == p["brand"]
    fg = "#f5f5f5" if dark else "#2a2a2a"
    lab = "#ffffff" if dark else p["brand"]
    css = f"""
.card{{background:{tint};color:{fg};padding:{'70px 50px' if vert else '56px 64px'};display:flex;flex-direction:column;gap:22px;justify-content:center}}
.co{{font-size:2.5rem;font-weight:700;color:{lab}}}
.grid{{display:{'flex;flex-direction:column;gap:22px' if vert else 'grid;grid-template-columns:1.25fr 1fr;gap:40px'};overflow:hidden}}
.addr{{font-size:2.1rem;line-height:1.38}} .addr+.addr{{margin-top:16px}} .alab{{font-weight:700;color:{lab};font-size:1.9rem;letter-spacing:.05em}}
.ct{{font-size:2.2rem;line-height:1.5}}
"""
    co = f'<div style="display:flex;align-items:center;gap:18px">{logo_html(dict(spec["logo"], text=None), 64, light=dark)}<div class="co">{e(spec["company_main"])}</div></div>' if spec.get("company_main") else f'<div>{logo_html(dict(spec["logo"], text=None), 64, light=dark)}</div>'
    body = f'<div class="card fit">{co}<div class="grid fit"><div>{addr_html(spec)}</div><div class="ct">{lines_html(contacts(spec))}</div></div></div>'
    return css, body, SANS[v]


def t_back_logo(spec, rng):
    v = _var(spec); p = spec["palette"]
    vert = spec["layout"] == "vertical"
    dark = rng.random() < 0.6
    bg = p["brand"] if dark else "#ffffff"
    fg = "#ffffff" if dark else p["brand"]
    css = f"""
.card{{background:{bg};color:{fg};display:flex;flex-direction:column;align-items:center;justify-content:center;gap:{40 if vert else 26}px;text-align:center;padding:40px}}
.web{{font-size:2.6rem;letter-spacing:.08em}}
.co{{font-size:2.3rem;font-weight:700;letter-spacing:.04em}}
.sl{{font-size:1.9rem;font-style:italic;opacity:.85}}
.qrw{{background:#fff;padding:10px;border-radius:6px;display:flex}}
"""
    lg = logo_html(spec["logo"], 230 if vert else 200, light=dark, direction="column" if (vert or rng.random() < 0.5) else "row", wm_size=50)
    qr = f'<div class="qrw">{qr_html(spec, 170 if vert else 150)}</div>'
    info = (f'<div class="co">{e(spec["company_main"])}</div>' if spec.get("company_main") else "") + f'<div class="web">{e(spec["webs"][0])}</div>' + (f'<div class="sl">{e(spec["slogan"])}</div>' if spec.get("slogan") else "")
    if vert:
        body = f'<div class="card fit">{lg}<div>{info}</div>{qr}</div>'
    else:
        body = f'<div class="card fit" style="flex-direction:row;gap:60px"><div style="display:flex;flex-direction:column;align-items:center;gap:20px">{lg}{info}</div>{qr}</div>'
    return css, body, SANS[v]


def t_back_decor(spec, rng):
    v = _var(spec); p = spec["palette"]
    kind = rng.choice(["circles", "stripes", "waves", "grid"])
    c1, c2 = p["brand"], p["accent"]
    w, h = (600, 1050) if spec["layout"] == "vertical" else (1050, 600)
    shapes = []
    if kind == "circles":
        for _ in range(14):
            shapes.append(f'<circle cx="{rng.randint(0, w)}" cy="{rng.randint(0, h)}" r="{rng.randint(40, 260)}" fill="#ffffff" opacity="{rng.uniform(.04, .16):.2f}"/>')
    elif kind == "stripes":
        for i in range(-10, 30):
            shapes.append(f'<rect x="{i*70}" y="-200" width="26" height="{h+600}" fill="{c2}" opacity=".35" transform="rotate(30 {w/2} {h/2})"/>')
    elif kind == "waves":
        for i in range(12):
            y = i * h / 11
            shapes.append(f'<path d="M0 {y:.0f} Q {w/4:.0f} {y-40:.0f} {w/2:.0f} {y:.0f} T {w} {y:.0f}" stroke="#ffffff" stroke-width="3" fill="none" opacity=".25"/>')
    else:
        for x in range(0, w, 50):
            for y in range(0, h, 50):
                if rng.random() < 0.35:
                    shapes.append(f'<rect x="{x+8}" y="{y+8}" width="34" height="34" fill="{c2}" opacity="{rng.uniform(.2, .6):.2f}"/>')
    svg = f'<svg width="{w}" height="{h}" style="position:absolute;left:0;top:0" xmlns="http://www.w3.org/2000/svg">{"".join(shapes)}</svg>'
    css = f"""
.card{{background:{c1};color:#fff;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:24px}}
.dec{{position:relative;font-size:3.0rem;letter-spacing:.12em;font-style:italic;text-align:center;padding:0 40px}}
.lg{{position:relative}}
"""
    lg = f'<div class="lg">{logo_html(spec["logo"], 170, light=True, direction="column", wm_size=44)}</div>' if (spec["logo"].get("text") or rng.random() < 0.6) else ""
    dec = f'<div class="dec">{e(spec["decor"])}</div>' if spec.get("decor") else ""
    return css, f'<div class="card fit">{svg}{lg}{dec}</div>', SANS[v]


TEMPLATES = {
    "minimal_white": t_minimal_white, "navy_gold": t_navy_gold, "color_band": t_color_band,
    "logo_heavy": t_logo_heavy, "bank_style": t_bank_style, "startup": t_startup,
    "japanese_minimal": t_japanese_minimal, "bilingual_columns": t_bilingual_columns,
    "vertical_cjk": t_vertical_cjk, "portrait_modern": t_portrait_modern, "portrait_classic": t_portrait_classic,
    "back_contact": t_back_contact, "back_logo": t_back_logo, "back_decor": t_back_decor,
}


def render_html(spec, rng):
    w, h = (600, 1050) if spec["layout"] == "vertical" else (1050, 600)
    css, body, base_font = TEMPLATES[spec["template"]](spec, rng)
    return page(spec, css, body, w, h, base_font), w, h

import json, sys
OUT='/home/user/wh-scan/CardImport/benchmark/runs/holdout_proxy/extractions/'
SCHEMA='/home/user/wh-scan/CardImport/schema/extraction-api.schema.json'
def F(value, conf, src=None, alts=None):
    return {"value": value, "confidence": conf, "source_text": src if src is not None else value, "alternatives": alts or []}
def P(number, kind, src, conf, hint=None, ext=None, alts=None):
    return {"number": number, "kind": kind, "source_text": src, "confidence": conf, "country_hint": hint, "extension": ext, "alternatives": alts or []}
def E(addr, conf, src=None, alts=None):
    return {"address": addr, "confidence": conf, "source_text": src or addr, "alternatives": alts or []}
def W(url, conf): return {"url": url, "confidence": conf}
def A(formatted, conf, street=None, city=None, region=None, postal_code=None, country=None):
    return {"formatted": formatted, "confidence": conf, "street": street, "city": city, "region": region, "postal_code": postal_code, "country": country}
def S(service, handle, conf): return {"service": service, "handle": handle, "confidence": conf}
def write(pid, **kw):
    d = {"schema_version": 1, "is_business_card": True, "card_side": "front", "language_hint": ["en"],
         "name": {"given": None, "family": None, "cjk_full": None, "prefix": None, "suffix": None},
         "company": None, "company_cjk": None, "job_title": None, "job_title_cjk": None,
         "department": None, "department_cjk": None, "phones": [], "emails": [], "websites": [],
         "addresses": [], "social": [], "notes_on_card": None,
         "evidence": {"concerns": [], "has_person_photo": False, "has_qr_code": False, "ignored_text": [], "overall_confidence": 0.9}}
    for k, v in kw.items():
        if k == 'name': d['name'].update(v)
        elif k == 'evidence': d['evidence'].update(v)
        else:
            assert k in d, k
            d[k] = v
    try:
        import jsonschema
        jsonschema.validate(d, json.load(open(SCHEMA)))
    except ImportError:
        pass
    p = OUT + pid + '.json'
    open(p, 'w').write(json.dumps(d, ensure_ascii=False, indent=2))
    json.load(open(p))
    print('ok', p)

import json
OUT='/home/user/wh-scan/CardImport/benchmark/runs/holdout_proxy/extractions/'
SCHEMA='/home/user/wh-scan/CardImport/schema/extraction-api.schema.json'
def F(v,c,src=None,alts=None):
    return {"value":v,"confidence":c,"source_text":src if src is not None else v,"alternatives":alts or []}
def P(num,kind,c,src,hint=None,ext=None,alts=None):
    return {"number":num,"kind":kind,"confidence":c,"source_text":src,"country_hint":hint,"extension":ext,"alternatives":alts or []}
def E(a,c,src=None,alts=None):
    return {"address":a,"confidence":c,"source_text":src or a,"alternatives":alts or []}
def W(u,c): return {"url":u,"confidence":c}
def A(formatted,street,city,region,postal,country,c):
    return {"formatted":formatted,"street":street,"city":city,"region":region,"postal_code":postal,"country":country,"confidence":c}
def write(pid, **kw):
    d={"schema_version":1,"is_business_card":True,"card_side":"front","language_hint":[],
       "name":{"given":None,"family":None,"cjk_full":None,"prefix":None,"suffix":None},
       "company":None,"company_cjk":None,"job_title":None,"job_title_cjk":None,"department":None,"department_cjk":None,
       "phones":[],"emails":[],"websites":[],"addresses":[],"social":[],"notes_on_card":None,
       "evidence":{"overall_confidence":0.9,"concerns":[],"ignored_text":[],"has_qr_code":False,"has_person_photo":False}}
    name=kw.pop('name',{}); d['name'].update(name)
    ev=kw.pop('evidence',{}); d['evidence'].update(ev)
    for k,v in kw.items():
        assert k in d, k
        d[k]=v
    try:
        import jsonschema
        jsonschema.validate(d, json.load(open(SCHEMA)))
    except ImportError:
        pass
    p=OUT+pid+'.json'
    with open(p,'w',encoding='utf-8') as f: json.dump(d,f,ensure_ascii=False,indent=2)
    json.load(open(p,encoding='utf-8'))
    print('ok',p)

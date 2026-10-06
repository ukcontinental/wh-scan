import json,sys
OUT='/home/user/wh-scan/CardImport/benchmark/runs/holdout_proxy/extractions/'
def F(v,c,s=None,a=None): return {"value":v,"confidence":c,"source_text":s if s is not None else v,"alternatives":a or []}
def P(num,kind,src,c,hint=None,ext=None,a=None): return {"number":num,"kind":kind,"source_text":src,"confidence":c,"country_hint":hint,"extension":ext,"alternatives":a or []}
def E(addr,c,src=None,a=None): return {"address":addr,"confidence":c,"source_text":src or addr,"alternatives":a or []}
def W(u,c): return {"url":u,"confidence":c}
def A(formatted,street,city,region,postal,country,c): return {"formatted":formatted,"street":street,"city":city,"region":region,"postal_code":postal,"country":country,"confidence":c}
def S(service,handle,c): return {"service":service,"handle":handle,"confidence":c}
def write(pid, **kw):
    d={"schema_version":1,"is_business_card":True,"card_side":"front","language_hint":["en"],
       "name":{"given":None,"family":None,"cjk_full":None,"prefix":None,"suffix":None},
       "company":None,"company_cjk":None,"job_title":None,"job_title_cjk":None,"department":None,"department_cjk":None,
       "phones":[],"emails":[],"websites":[],"addresses":[],"social":[],"notes_on_card":None,
       "evidence":{"concerns":[],"has_person_photo":False,"has_qr_code":False,"ignored_text":[],"overall_confidence":0.9}}
    for k,v in kw.items():
        if k=='name': d['name'].update(v)
        elif k=='evidence': d['evidence'].update(v)
        else:
            assert k in d,k; d[k]=v
    s=json.dumps(d,ensure_ascii=False,indent=2)
    open(OUT+pid+'.json','w').write(s); json.load(open(OUT+pid+'.json')); print('ok',pid)

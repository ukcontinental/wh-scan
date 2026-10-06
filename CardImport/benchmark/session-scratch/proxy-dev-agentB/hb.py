import json, sys
OUT='/home/user/wh-scan/CardImport/benchmark/runs/proxy/extractions/'
def F(v,c,src=None,alt=None): return {"value":v,"confidence":c,"source_text":src if src is not None else v,"alternatives":alt or []}
def P(num,kind,c,src,cc=None,ext=None,alt=None): return {"number":num,"kind":kind,"confidence":c,"source_text":src,"country_hint":cc,"extension":ext,"alternatives":alt or []}
def E(a,c,src,alt=None): return {"address":a,"confidence":c,"source_text":src,"alternatives":alt or []}
def W(u,c): return {"url":u,"confidence":c}
def A(formatted,street,city,region,postal,country,c): return {"formatted":formatted,"street":street,"city":city,"region":region,"postal_code":postal,"country":country,"confidence":c}
def card(id, **k):
    d={"schema_version":1,"is_business_card":True,"card_side":"front","language_hint":["en"],
       "name":{"given":None,"family":None,"cjk_full":None,"prefix":None,"suffix":None},
       "company":None,"company_cjk":None,"job_title":None,"job_title_cjk":None,"department":None,
       "phones":[],"emails":[],"websites":[],"addresses":[],"social":[],"notes_on_card":None,
       "evidence":{"ignored_text":[],"concerns":[],"has_qr_code":False,"has_person_photo":False,"overall_confidence":0.9}}
    ev=k.pop('evidence',{}); nm=k.pop('name',{})
    d['name'].update(nm); d['evidence'].update(ev); d.update(k)
    s=json.dumps(d,ensure_ascii=False,indent=2)
    open(OUT+id+'.json','w',encoding='utf-8').write(s)
    json.loads(open(OUT+id+'.json',encoding='utf-8').read())
    print('wrote',id)

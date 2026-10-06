import json,sys
OUT='/home/user/wh-scan/CardImport/benchmark/runs/holdout_proxy/extractions/'
def F(v,c,src=None,alt=None):
    return {"value":v,"confidence":c,"source_text":src if src is not None else v,"alternatives":alt or []}
def P(num,kind,src,c,cc=None,ext=None,alt=None):
    return {"number":num,"kind":kind,"source_text":src,"confidence":c,"country_hint":cc,"extension":ext,"alternatives":alt or []}
def E(a,src,c,alt=None): return {"address":a,"source_text":src,"confidence":c,"alternatives":alt or []}
def W(u,c): return {"url":u,"confidence":c}
def A(formatted,street,city,region,pc,country,c):
    return {"formatted":formatted,"street":street,"city":city,"region":region,"postal_code":pc,"country":country,"confidence":c}
def card(pid,given=None,family=None,cjk=None,prefix=None,suffix=None,company=None,company_cjk=None,job=None,job_cjk=None,dept=None,dept_cjk=None,phones=(),emails=(),websites=(),addresses=(),social=(),side="front",lang=("en",),notes=None,ignored=(),concerns=(),photo=False,qr=False,overall=0.9,is_card=True):
    d={"schema_version":1,"is_business_card":is_card,"card_side":side,"language_hint":list(lang),
       "name":{"given":given,"family":family,"cjk_full":cjk,"prefix":prefix,"suffix":suffix},
       "company":company,"company_cjk":company_cjk,"job_title":job,"job_title_cjk":job_cjk,"department":dept,"department_cjk":dept_cjk,
       "phones":list(phones),"emails":list(emails),"websites":list(websites),"addresses":list(addresses),"social":list(social),
       "notes_on_card":notes,"evidence":{"has_qr_code":qr,"has_person_photo":photo,"ignored_text":list(ignored),"concerns":list(concerns),"overall_confidence":overall}}
    p=OUT+pid+'.json'
    open(p,'w',encoding='utf-8').write(json.dumps(d,ensure_ascii=False,indent=2))
    json.load(open(p,encoding='utf-8')); print('ok',p)

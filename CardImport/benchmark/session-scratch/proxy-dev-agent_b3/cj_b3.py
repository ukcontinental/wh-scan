import json
OUT='/home/user/wh-scan/CardImport/benchmark/runs/proxy/extractions/'
def F(v,c,src=None,alts=None):
    return {"value":v,"confidence":c,"source_text":src if src is not None else v,"alternatives":alts or []}
def P(num,kind,src,c,hint=None,ext=None,alts=None):
    return {"number":num,"kind":kind,"source_text":src,"confidence":c,"country_hint":hint,"extension":ext,"alternatives":alts or []}
def E(a,src,c,alts=None): return {"address":a,"source_text":src,"confidence":c,"alternatives":alts or []}
def W(u,c): return {"url":u,"confidence":c}
def A(fmt,street,city,region,pc,country,c):
    return {"formatted":fmt,"street":street,"city":city,"region":region,"postal_code":pc,"country":country,"confidence":c}
def S(svc,h,c): return {"service":svc,"handle":h,"confidence":c}
def write(id, given=None,family=None,cjk=None,prefix=None,suffix=None,company=None,company_cjk=None,department=None,
          job_title=None,job_title_cjk=None,phones=(),emails=(),websites=(),addresses=(),social=(),
          card_side="front",is_bc=True,lang=("en",),notes=None,concerns=(),photo=False,qr=False,ignored=(),overall=0.9):
    d={"schema_version":1,"is_business_card":is_bc,"card_side":card_side,"language_hint":list(lang),
       "name":{"given":given,"family":family,"cjk_full":cjk,"prefix":prefix,"suffix":suffix},
       "company":company,"company_cjk":company_cjk,"department":department,"job_title":job_title,"job_title_cjk":job_title_cjk,
       "phones":list(phones),"emails":list(emails),"websites":list(websites),"addresses":list(addresses),"social":list(social),
       "notes_on_card":notes,
       "evidence":{"concerns":list(concerns),"has_person_photo":photo,"has_qr_code":qr,"ignored_text":list(ignored),"overall_confidence":overall}}
    s=json.dumps(d,ensure_ascii=False,indent=2)
    json.loads(s)
    open(OUT+id+'.json','w').write(s+"\n")
    print("wrote",id)

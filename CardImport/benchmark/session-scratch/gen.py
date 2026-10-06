import json, os
OUT="/home/user/wh-scan/CardImport/benchmark/runs/proxy/extractions"
def F(v,c,src=None,alts=None): return {"value":v,"confidence":c,"source_text":src if src is not None else v,"alternatives":alts or []}
def P(num,kind,c,src,cc,ext=None,alts=None): return {"number":num,"kind":kind,"confidence":c,"source_text":src,"country_hint":cc,"extension":ext,"alternatives":alts or []}
def E(a,c,src,alts=None): return {"address":a,"confidence":c,"source_text":src,"alternatives":alts or []}
def W(u,c): return {"url":u,"confidence":c}
def A(formatted,street,city,region,pc,country,c): return {"formatted":formatted,"street":street,"city":city,"region":region,"postal_code":pc,"country":country,"confidence":c}
def card(**k):
    d={"schema_version":1,"is_business_card":True,"card_side":"front","language_hint":["en"],
       "name":{"given":None,"family":None,"cjk_full":None,"prefix":None,"suffix":None},
       "company":None,"company_cjk":None,"job_title":None,"job_title_cjk":None,"department":None,
       "phones":[],"emails":[],"websites":[],"addresses":[],"social":[],"notes_on_card":None,
       "evidence":{"concerns":[],"has_person_photo":False,"has_qr_code":False,"ignored_text":[],"overall_confidence":0.9}}
    ev=k.pop("evidence",{}); nm=k.pop("name",{})
    d.update(k); d["evidence"].update(ev); d["name"].update(nm); return d

cards={}
cards["img_0004"]=card(language_hint=["zh-Hant","en"],
  name={"cjk_full":F("陳嘉欣",0.96)},
  company=F("九龍灣物流有限公司",0.93),
  job_title_cjk=F("總經理",0.96),
  phones=[P("(852) 5365 4042","mobile",0.95,"手提電話：(852) 5365 4042","HK"),
          P("+852-2600-0792","work",0.95,"電話：+852-2600-0792","HK"),
          P("+852 2584 5611","fax",0.95,"傳真：+852 2584 5611","HK")],
  emails=[E("vivian.chan@kblogistics.com.hk",0.95,"信箱：vivian.chan@kblogistics.com.hk"),
          E("contact@kblogistics.com.hk",0.95,"信箱：contact@kblogistics.com.hk")],
  websites=[W("www.kblogistics.com.hk",0.95)],
  addresses=[A("九龍觀塘鴻圖道12號永發工業大廈9樓B室","鴻圖道12號永發工業大廈9樓B室","觀塘","九龍",None,"Hong Kong",0.85)],
  evidence={"ignored_text":["KB LOGISTICS","安全 準時 專業","始於1962"],"overall_confidence":0.92,"concerns":[]})

cards["img_0010"]=card(card_side="back",
  websites=[W("www.pinecrestpack.ca",0.95)],
  evidence={"has_qr_code":True,"ignored_text":["PINECREST"],"overall_confidence":0.9,"concerns":["no_person_on_side"]})

cards["img_0016"]=card(
  name={"given":F("Sarah",0.96,"Sarah MacDonald"),"family":F("MacDonald",0.95,"Sarah MacDonald")},
  company=F("NORTHSTAR COLD CHAIN INC.",0.92,"NORTHSTAR COLD CHAIN INC.",["Northstar Cold Chain Inc."]),
  job_title=F("General Manager",0.95),
  phones=[P("604-555-0198","mobile",0.92,"C 604-555-0198","CA"),
          P("604 555 0161","work",0.92,"T: 604 555 0161","CA"),
          P("+1 604 555 0109","fax",0.92,"Fax: +1 604 555 0109","CA")],
  emails=[E("sarah@northstarcoldchain.com",0.93,"E: sarah@northstarcoldchain.com")],
  websites=[W("northstarcoldchain.com",0.93)],
  addresses=[A("4321 Still Creek Dr, Unit 110, Burnaby, BC V5C 6S7, Canada","4321 Still Creek Dr, Unit 110","Burnaby","BC","V5C 6S7","Canada",0.88)],
  evidence={"concerns":["small_text"],"overall_confidence":0.9})

cards["img_0022"]=card(language_hint=["zh-Hant","en"],
  name={"given":F("Grace",0.97,"Grace Huang"),"family":F("Huang",0.97,"Grace Huang"),"cjk_full":F("黃淑芬",0.96)},
  company=F("Heng Chang International Trading Co., Ltd.",0.96),
  company_cjk=F("恒昌國際貿易有限公司",0.9,"恒昌國際貿易有限公司",["恆昌國際貿易有限公司"]),
  job_title=F("Sales Manager",0.97), job_title_cjk=F("業務經理",0.96),
  phones=[P("+886 960 345 354","mobile",0.96,"M 手機 +886 960 345 354","TW"),
          P("886-2-2780-4587","work",0.95,"電話 Tel: 886-2-2780-4587","TW"),
          P("886-2-2230-1797","fax",0.95,"傳真 Fax: 886-2-2230-1797","TW")],
  emails=[E("grace.huang@hengchang-trade.com.tw",0.96,"E-mail: grace.huang@hengchang-trade.com.tw")],
  websites=[W("www.hengchang-trade.com.tw",0.96)],
  addresses=[A("台灣 104 台北市中山區南京東路二段88號12樓","南京東路二段88號12樓","中山區","台北市","104","台灣",0.88)],
  evidence={"ignored_text":["ISO 9001:2015","恒昌"],"overall_confidence":0.94})

cards["img_0028"]=card(language_hint=["zh-Hant","en"],
  name={"cjk_full":F("劉建宏",0.96)},
  company=F("瑞光冷鏈物流股份有限公司",0.93),
  job_title_cjk=F("業務開發經理",0.95), department=F("冷鏈事業部",0.92),
  phones=[P("0941-517-202","mobile",0.95,"手機：0941-517-202","TW")],
  emails=[E("henry_liu@ruiguang-logistics.com.tw",0.94,"E-mail：henry_liu@ruiguang-logistics.com.tw")],
  websites=[W("www.ruiguang-logistics.com.tw",0.94)],
  addresses=[A("台灣 114 台北市內湖區瑞光路35號8樓","瑞光路35號8樓","內湖區","台北市","114","台灣",0.87)],
  evidence={"has_person_photo":True,"has_qr_code":True,"ignored_text":["瑞光"],"overall_confidence":0.92})

cards["img_0034"]=card(language_hint=["zh-Hant","en"],
  name={"given":F("Winnie",0.96,"Winnie Cheung"),"family":F("Cheung",0.96,"Winnie Cheung"),"cjk_full":F("張美儀",0.95)},
  company=F("Harbour Trust CPA Limited",0.95), company_cjk=F("港信會計師事務所有限公司",0.94),
  job_title=F("Branch Manager",0.95), job_title_cjk=F("分行經理",0.95),
  phones=[P("(852) 5527 4300","mobile",0.94,"手機 Mobile: (852) 5527 4300","HK"),
          P("3458 8142","work",0.92,"T 電話 3458 8142 轉 3941","HK","3941"),
          P("(852) 2292 2807","fax",0.94,"傳真 Fax: (852) 2292 2807","HK")],
  emails=[E("winnie.cheung@harbourtrustcpa.com.hk",0.93,"電郵 Email: winnie.cheung@harbourtrustcpa.com.hk"),
          E("contact@harbourtrustcpa.com.hk",0.93,"電郵 Email: contact@harbourtrustcpa.com.hk")],
  websites=[W("https://www.harbourtrustcpa.com.hk",0.93)],
  social=[{"service":"wechat","handle":"winniecheung30","confidence":0.92}],
  addresses=[A("中環德輔道中88號景豐大廈22樓2208室","德輔道中88號景豐大廈22樓2208室","中環",None,None,"Hong Kong",0.85)],
  evidence={"has_qr_code":True,"overall_confidence":0.92,"concerns":["perspective_skew"]})

cards["img_0040"]=card(card_side="back",
  phones=[P("604.555.0175","work",0.95,"Office: 604.555.0175","CA"),
          P("+1 604 555 0109","fax",0.95,"Fax: +1 604 555 0109","CA")],
  emails=[E("service@northstarcoldchain.com",0.95,"service@northstarcoldchain.com")],
  websites=[W("northstarcoldchain.com",0.95)],
  addresses=[A("4321 Still Creek Dr, Unit 110, Burnaby, BC V5C 6S7, Canada","4321 Still Creek Dr, Unit 110","Burnaby","BC","V5C 6S7","Canada",0.93),
             A("1055 W Georgia St, Suite 2100, Vancouver, BC V6E 3P3, Canada","1055 W Georgia St, Suite 2100","Vancouver","BC","V6E 3P3","Canada",0.93)],
  evidence={"ignored_text":["Head Office","Warehouse & Distribution"],"overall_confidence":0.93,"concerns":["no_person_on_side","multiple_addresses"]})

cards["img_0046"]=card(language_hint=["zh-Hant","en"],
  name={"cjk_full":F("何詠詩",0.96)},
  company=F("港信會計師事務所有限公司",0.95),
  job_title_cjk=F("合夥人",0.95),
  phones=[P("+852-5632-3122","mobile",0.96,"手提：+852-5632-3122","HK"),
          P("2131 6381","work",0.95,"直線：2131 6381","HK"),
          P("+852-3514-6250","fax",0.96,"傳真：+852-3514-6250","HK")],
  emails=[E("stephanie@harbourtrustcpa.com",0.3,"E-mail：stephanie@harbourtrustcpa.com.",["stephanie@harbourtrustcpa.com.hk"])],
  websites=[W("harbourtrustcpa.com.hk",0.95)],
  addresses=[A("中環德輔道中88號景豐大廈22樓2208室","德輔道中88號景豐大廈22樓2208室","中環",None,None,"Hong Kong",0.88)],
  evidence={"has_qr_code":True,"ignored_text":["創立於1962年"],"overall_confidence":0.85,"concerns":["partially_cut_off","email_obscured_by_qr_code"]})

cards["img_0052"]=card(
  name={"given":F("Sophie",0.97,"Sophie Lam"),"family":F("Lam",0.97,"Sophie Lam")},
  company=F("Cedarline Logistics Inc.",0.96), job_title=F("Director of Operations",0.96),
  phones=[P("+1-416-555-0172","mobile",0.96,"M: +1-416-555-0172","CA"),
          P("+1-905-555-0171","work",0.92,"P: +1-905-555-0171","CA"),
          P("+1-905-555-0197","fax",0.96,"F: +1-905-555-0197","CA")],
  emails=[E("sophiel@cedarline.ca",0.94,"E: sophiel@cedarline.ca")],
  websites=[W("www.cedarline.ca",0.96)],
  social=[{"service":"linkedin","handle":"sophie-lam","confidence":0.9}],
  addresses=[A("6750 Mississauga Rd, Unit 7, Mississauga, ON L5N 2L3, Canada","6750 Mississauga Rd, Unit 7","Mississauga","ON","L5N 2L3","Canada",0.93)],
  evidence={"ignored_text":["CEDARLINE"],"overall_confidence":0.94})

cards["img_0058"]=card(language_hint=["zh-Hans","en"],
  name={"cjk_full":F("李娜",0.97)},
  company=F("北京云帆软件有限公司",0.95),
  job_title_cjk=F("创始人兼首席执行官",0.95),
  phones=[P("+86 158 0921 4136","mobile",0.96,"手机：+86 158 0921 4136","CN")],
  emails=[E("lina@yunfansoft.cn",0.96,"lina@yunfansoft.cn")],
  websites=[W("https://www.yunfansoft.cn",0.95)],
  social=[{"service":"wechat","handle":"lina95","confidence":0.94}],
  addresses=[A("北京市朝阳区建国路93号1203室（100022）","建国路93号1203室","北京市","朝阳区","100022","China",0.85)],
  evidence={"ignored_text":["云帆","CloudSail","科技创新 引领未来"],"overall_confidence":0.94})

for k,v in cards.items():
    p=os.path.join(OUT,k+".json")
    with open(p,"w",encoding="utf-8") as f: json.dump(v,f,ensure_ascii=False,indent=2)
    json.load(open(p,encoding="utf-8")); print("ok",p)

from hb import *
card('img_0030', card_side="back",
 websites=[W("www.wuitaifoods.com.hk",0.96)],
 evidence={"ignored_text":["WUI TAI"],"concerns":["no_person_on_side"],"has_qr_code":True,"overall_confidence":0.93})
card('img_0036', language_hint=["zh-Hans","en"],
 name={"given":F("Leon",0.96,"Dr. Leon Liu"),"family":F("Liu",0.96,"Dr. Leon Liu"),"prefix":F("Dr.",0.95,"Dr. Leon Liu"),"cjk_full":F("刘洋",0.96)},
 company=F("Shenzhen Haichuan Electronic Technology Co., Ltd.",0.96),
 company_cjk=F("深圳市海川电子科技有限公司",0.95),
 job_title=F("Marketing Specialist",0.96), job_title_cjk=F("市场专员",0.95),
 department=F("R&D Center",0.92,"研发中心 R&D Center"),
 phones=[P("158-1901-3900","mobile",0.95,"手机 Mob: 158-1901-3900","CN")],
 emails=[E("leon_liu@haichuan-tech.cn",0.94,"邮箱 Email: leon_liu@haichuan-tech.cn")],
 websites=[W("www.haichuan-tech.cn",0.95)],
 social=[{"service":"wechat","handle":"liuleon87","confidence":0.94}],
 addresses=[A("Floor 12, Tower A, No. 9 Gaoxin South 1st Road, Nanshan District, Shenzhen, Guangdong 518057","Floor 12, Tower A, No. 9 Gaoxin South 1st Road, Nanshan District","Shenzhen","Guangdong","518057","China",0.9)],
 evidence={"ignored_text":[],"concerns":[],"overall_confidence":0.93})

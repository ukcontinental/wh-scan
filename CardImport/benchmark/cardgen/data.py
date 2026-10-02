"""Static pools of fictional names, companies, addresses, titles and marketing text.

Everything here is invented. North-American numbers use the reserved 555-01xx block.
"""

# ---------------------------------------------------------------- names
# (cjk_full, family_latin, given_latin)
TW_NAMES = [
    ("陳志豪", "Chen", "Jason"), ("林美玲", "Lin", "Linda"), ("張家豪", "Chang", "Kevin"),
    ("黃淑芬", "Huang", "Grace"), ("李承恩", "Lee", "Eric"), ("吳佩珊", "Wu", "Peggy"),
    ("劉建宏", "Liu", "Henry"), ("蔡宜君", "Tsai", "Irene"), ("楊志偉", "Yang", "Wilson"),
    ("許雅婷", "Hsu", "Tina"), ("鄭偉倫", "Cheng", "Alan"), ("謝佳穎", "Hsieh", "Joyce"),
    ("郭俊傑", "Kuo", "Jack"), ("洪詩涵", "Hung", "Sandy"), ("曾冠宇", "Tseng", "Leo"),
    ("廖思妤", "Liao", "Cindy"), ("蕭博文", "Hsiao", "Vincent"), ("賴怡如", "Lai", "Annie"),
]
HK_NAMES = [
    ("陳嘉欣", "Chan", "Vivian"), ("李志明", "Lee", "Kenneth"), ("黃永強", "Wong", "Raymond"),
    ("張美儀", "Cheung", "Winnie"), ("梁家輝", "Leung", "Patrick"), ("何詠詩", "Ho", "Stephanie"),
    ("周子健", "Chow", "Edmund"), ("林曉彤", "Lam", "Karen"), ("吳家樂", "Ng", "Calvin"),
]
# (cjk_full, family_pinyin, given_pinyin, optional english given name)
CN_NAMES = [
    ("张伟", "Zhang", "Wei", None), ("王芳", "Wang", "Fang", "Fiona"), ("李娜", "Li", "Na", None),
    ("刘洋", "Liu", "Yang", "Leon"), ("陈静", "Chen", "Jing", None), ("杨磊", "Yang", "Lei", None),
    ("赵敏", "Zhao", "Min", "Amy"), ("黄海涛", "Huang", "Haitao", None), ("周晓明", "Zhou", "Xiaoming", "Tony"),
    ("吴婷婷", "Wu", "Tingting", None), ("徐浩", "Xu", "Hao", "Howard"), ("孙丽华", "Sun", "Lihua", None),
    ("马俊", "Ma", "Jun", None), ("朱晓雯", "Zhu", "Xiaowen", "Sherry"), ("郑凯", "Zheng", "Kai", None),
]
CA_WESTERN = [
    ("John", "Thompson"), ("Sarah", "MacDonald"), ("Marc", "Tremblay"), ("Priya", "Patel"),
    ("Michael", "Nguyen"), ("Emily", "Gagnon"), ("Daniel", "Roy"), ("Jessica", "Wilson"),
    ("Ryan", "O'Neill"), ("Amanda", "Kowalski"), ("Nathalie", "Bouchard"), ("Graham", "Fraser"),
    ("Aisha", "Rahman"), ("Owen", "Campbell"),
]
# Chinese-Canadian: (cjk_full, family, given)
CA_CHINESE = [
    ("張凱文", "Zhang", "Kevin"), ("陳欣怡", "Chen", "Olivia"), ("黃以恆", "Wong", "Ethan"),
    ("林淑慧", "Lam", "Sophie"), ("劉德成", "Lau", "Derek"), ("吳美華", "Ng", "Michelle"),
    ("鄧志遠", "Tang", "Justin"),
]
US_WESTERN = [
    ("Robert", "Johnson"), ("Laura", "Bennett"), ("Brian", "Carter"), ("Rachel", "Goldberg"),
    ("Carlos", "Ramirez"), ("Megan", "Sullivan"), ("Andrew", "Kim"), ("Heather", "Collins"),
]
US_CHINESE = [("劉珍妮", "Liu", "Jennifer"), ("王建國", "Wang", "Peter")]

# ---------------------------------------------------------------- addresses
# Each address has an 'en' form and optionally a 'cjk' form; structured fields are given
# exactly as they will be printed. 'area' = phone area code used for landlines there.
ADDR = {
    # Canada
    "tor_front": {"cc": "CA", "area": "416", "en": {"street": "120 Front St W, Suite 400", "city": "Toronto", "region": "ON", "postal_code": "M5J 2M2", "country": "Canada"},
                  "cjk": {"street": "前街西120號400室", "city": "多倫多", "region": "安大略省", "postal_code": "M5J 2M2", "country": "加拿大"}},
    "tor_bay": {"cc": "CA", "area": "647", "en": {"street": "333 Bay St, 18th Floor", "city": "Toronto", "region": "ON", "postal_code": "M5H 2R2", "country": "Canada"}, "cjk": None},
    "mis_ware": {"cc": "CA", "area": "905", "en": {"street": "6750 Mississauga Rd, Unit 7", "city": "Mississauga", "region": "ON", "postal_code": "L5N 2L3", "country": "Canada"},
                 "cjk": {"street": "密西沙加路6750號7單元", "city": "密西沙加", "region": "安大略省", "postal_code": "L5N 2L3", "country": "加拿大"}},
    "mkm_hwy7": {"cc": "CA", "area": "905", "en": {"street": "3601 Highway 7 E, Suite 1008", "city": "Markham", "region": "ON", "postal_code": "L3R 0M3", "country": "Canada"},
                 "cjk": {"street": "7號公路東3601號1008室", "city": "萬錦", "region": "安大略省", "postal_code": "L3R 0M3", "country": "加拿大"}},
    "van_burr": {"cc": "CA", "area": "604", "en": {"street": "1055 W Georgia St, Suite 2100", "city": "Vancouver", "region": "BC", "postal_code": "V6E 3P3", "country": "Canada"},
                 "cjk": {"street": "西喬治亞街1055號2100室", "city": "溫哥華", "region": "卑詩省", "postal_code": "V6E 3P3", "country": "加拿大"}},
    "bby_ware": {"cc": "CA", "area": "604", "en": {"street": "4321 Still Creek Dr, Unit 110", "city": "Burnaby", "region": "BC", "postal_code": "V5C 6S7", "country": "Canada"}, "cjk": None},
    # US
    "nyc_bway": {"cc": "US", "area": "212", "en": {"street": "1450 Broadway, 18th Floor", "city": "New York", "region": "NY", "postal_code": "10018", "country": "USA"},
                 "cjk": {"street": "百老匯大道1450號18樓", "city": "紐約", "region": "紐約州", "postal_code": "10018", "country": "美國"}},
    "nyc_madison": {"cc": "US", "area": "212", "en": {"street": "420 Madison Ave, Suite 1201", "city": "New York", "region": "NY", "postal_code": "10017", "country": "USA"}, "cjk": None},
    "nyc_canal": {"cc": "US", "area": "212", "en": {"street": "88 Canal St, 3rd Floor", "city": "New York", "region": "NY", "postal_code": "10002", "country": "USA"},
                  "cjk": {"street": "堅尼街88號3樓", "city": "紐約", "region": "紐約州", "postal_code": "10002", "country": "美國"}},
    # Taiwan
    "tpe_songren": {"cc": "TW", "area": "2", "en": {"street": "5F., No. 100, Songren Rd., Xinyi Dist.", "city": "Taipei City", "region": None, "postal_code": "110", "country": "Taiwan"},
                    "cjk": {"street": "信義區松仁路100號5樓", "city": "台北市", "region": None, "postal_code": "110", "country": "台灣"}},
    "tpe_nanjing": {"cc": "TW", "area": "2", "en": {"street": "12F., No. 88, Sec. 2, Nanjing E. Rd., Zhongshan Dist.", "city": "Taipei City", "region": None, "postal_code": "104", "country": "Taiwan"},
                    "cjk": {"street": "中山區南京東路二段88號12樓", "city": "台北市", "region": None, "postal_code": "104", "country": "台灣"}},
    "ntp_wenhua": {"cc": "TW", "area": "2", "en": {"street": "No. 188, Sec. 1, Wenhua Rd., Banqiao Dist.", "city": "New Taipei City", "region": None, "postal_code": "220", "country": "Taiwan"},
                   "cjk": {"street": "板橋區文化路一段188號", "city": "新北市", "region": None, "postal_code": "220", "country": "台灣"}},
    "tpe_neihu": {"cc": "TW", "area": "2", "en": {"street": "8F., No. 35, Ruiguang Rd., Neihu Dist.", "city": "Taipei City", "region": None, "postal_code": "114", "country": "Taiwan"},
                  "cjk": {"street": "內湖區瑞光路35號8樓", "city": "台北市", "region": None, "postal_code": "114", "country": "台灣"}},
    "txg_taiwan": {"cc": "TW", "area": "4", "en": {"street": "8F., No. 99, Sec. 3, Taiwan Blvd., Xitun Dist.", "city": "Taichung City", "region": None, "postal_code": "407", "country": "Taiwan"},
                   "cjk": {"street": "西屯區台灣大道三段99號8樓", "city": "台中市", "region": None, "postal_code": "407", "country": "台灣"}},
    "tyn_factory": {"cc": "TW", "area": "3", "en": {"street": "No. 26, Gongye 5th Rd., Guanyin Dist.", "city": "Taoyuan City", "region": None, "postal_code": "328", "country": "Taiwan"},
                    "cjk": {"street": "觀音區工業五路26號", "city": "桃園市", "region": None, "postal_code": "328", "country": "台灣"}},
    # Hong Kong (no postal codes)
    "hk_canton": {"cc": "HK", "area": "", "en": {"street": "Unit 1503, 15/F, Harbour Crest Centre, 30 Canton Road, Tsim Sha Tsui", "city": "Kowloon", "region": None, "postal_code": None, "country": "Hong Kong"},
                  "cjk": {"street": "尖沙咀廣東道30號海峰中心15樓1503室", "city": "九龍", "region": None, "postal_code": None, "country": "香港"}},
    "hk_queens": {"cc": "HK", "area": "", "en": {"street": "Room 2208, 22/F, Kingsfield Tower, 88 Des Voeux Road Central", "city": "Central", "region": None, "postal_code": None, "country": "Hong Kong"},
                  "cjk": {"street": "德輔道中88號景豐大廈22樓2208室", "city": "中環", "region": None, "postal_code": None, "country": "香港"}},
    "hk_kwuntong": {"cc": "HK", "area": "", "en": {"street": "Flat B, 9/F, Wing Fat Industrial Building, 12 Hung To Road, Kwun Tong", "city": "Kowloon", "region": None, "postal_code": None, "country": "Hong Kong"},
                    "cjk": {"street": "觀塘鴻圖道12號永發工業大廈9樓B室", "city": "九龍", "region": None, "postal_code": None, "country": "香港"}},
    # Mainland China (cjk forms in Simplified)
    "sh_zhangjiang": {"cc": "CN", "area": "21", "en": {"street": "Room 501, Building 3, No. 88 Zhangjiang Road, Pudong New Area", "city": "Shanghai", "region": None, "postal_code": "200120", "country": "China"},
                      "cjk": {"street": "浦东新区张江路88号3号楼501室", "city": "上海市", "region": None, "postal_code": "200120", "country": "中国"}},
    "sz_nanshan": {"cc": "CN", "area": "755", "en": {"street": "Floor 12, Tower A, No. 9 Gaoxin South 1st Road, Nanshan District", "city": "Shenzhen", "region": "Guangdong", "postal_code": "518057", "country": "China"},
                   "cjk": {"street": "南山区高新南一道9号A座12楼", "city": "深圳市", "region": "广东省", "postal_code": "518057", "country": "中国"}},
    "gz_tianhe": {"cc": "CN", "area": "20", "en": {"street": "Room 1806, No. 385 Tianhe Road, Tianhe District", "city": "Guangzhou", "region": "Guangdong", "postal_code": "510620", "country": "China"},
                  "cjk": {"street": "天河区天河路385号1806室", "city": "广州市", "region": "广东省", "postal_code": "510620", "country": "中国"}},
    "bj_jianguo": {"cc": "CN", "area": "10", "en": {"street": "Suite 1203, No. 93 Jianguo Road, Chaoyang District", "city": "Beijing", "region": None, "postal_code": "100022", "country": "China"},
                   "cjk": {"street": "朝阳区建国路93号1203室", "city": "北京市", "region": None, "postal_code": "100022", "country": "中国"}},
    "hz_xihu": {"cc": "CN", "area": "571", "en": {"street": "No. 16 Longjing Road, Xihu District", "city": "Hangzhou", "region": "Zhejiang", "postal_code": "310013", "country": "China"},
                "cjk": {"street": "西湖区龙井路16号", "city": "杭州市", "region": "浙江省", "postal_code": "310013", "country": "中国"}},
    "sz_suzhou": {"cc": "CN", "area": "512", "en": {"street": "No. 58 Suhong East Road, Suzhou Industrial Park", "city": "Suzhou", "region": "Jiangsu", "postal_code": "215021", "country": "China"},
                  "cjk": {"street": "苏州工业园区苏虹东路58号", "city": "苏州市", "region": "江苏省", "postal_code": "215021", "country": "中国"}},
    "dl_port": {"cc": "CN", "area": "411", "en": {"street": "No. 7 Gangxing Road, Zhongshan District", "city": "Dalian", "region": "Liaoning", "postal_code": "116001", "country": "China"},
                "cjk": {"street": "中山区港兴路7号", "city": "大连市", "region": "辽宁省", "postal_code": "116001", "country": "中国"}},
}

# ---------------------------------------------------------------- companies
# industry drives titles / slogans / certs / logo marks.
# wordmark: brand text in the logo that is NOT the company name (-> distractor) or None.
COMPANIES = {
    "CA": [
        {"en": "Harbourview Frozen Foods Ltd.", "short": "HARBOURVIEW", "cjk": "海景冷凍食品有限公司", "domain": "harbourviewfoods.ca", "industry": "food", "wordmark": "OCEAN CREST", "addrs": ["tor_front", "mis_ware"]},
        {"en": "Cedarline Logistics Inc.", "short": "CEDARLINE", "cjk": "雪松物流有限公司", "domain": "cedarline.ca", "industry": "logistics", "wordmark": None, "addrs": ["mis_ware", "tor_bay"]},
        {"en": "Northstar Cold Chain Inc.", "short": "NORTHSTAR", "cjk": "北星冷鏈有限公司", "domain": "northstarcoldchain.com", "industry": "logistics", "wordmark": "FROSTLINE", "addrs": ["bby_ware", "van_burr"]},
        {"en": "Lakeshore Trading Co.", "short": "LAKESHORE", "cjk": "湖濱貿易公司", "domain": "lakeshoretrading.ca", "industry": "trading", "wordmark": None, "addrs": ["mkm_hwy7", "mis_ware"]},
        {"en": "Kestrel Analytics Inc.", "short": "kestrel", "cjk": None, "domain": "kestrelanalytics.io", "industry": "tech", "wordmark": None, "addrs": ["tor_bay"]},
        {"en": "Granite Peak Capital Partners", "short": "GRANITE PEAK", "cjk": "花崗峰資本", "domain": "granitepeakcap.ca", "industry": "finance", "wordmark": None, "addrs": ["tor_bay", "van_burr"]},
        {"en": "Morgan Consulting Group", "short": "MORGAN", "cjk": None, "domain": "morganconsulting.ca", "industry": "consulting", "wordmark": None, "addrs": ["tor_front"]},
        {"en": "Brightwater Seafood Inc.", "short": "BRIGHTWATER", "cjk": "碧水海產有限公司", "domain": "brightwaterseafood.ca", "industry": "food", "wordmark": "TIDEWELL", "addrs": ["van_burr", "bby_ware"]},
        {"en": "True North Food Distributors Ltd.", "short": "TRUE NORTH", "cjk": "真北食品經銷有限公司", "domain": "truenorthfood.ca", "industry": "food", "wordmark": None, "addrs": ["mkm_hwy7", "mis_ware"]},
        {"en": "Pinecrest Packaging Corp.", "short": "PINECREST", "cjk": None, "domain": "pinecrestpack.ca", "industry": "packaging", "wordmark": None, "addrs": ["mis_ware"]},
    ],
    "US": [
        {"en": "Taylor Jordan & Associates LLP", "short": "TJ&A", "cjk": None, "domain": "taylorjordanlaw.com", "industry": "consulting", "wordmark": None, "addrs": ["nyc_madison"]},
        {"en": "Hudson & Pine Advisory LLC", "short": "HUDSON & PINE", "cjk": None, "domain": "hudsonpine.com", "industry": "finance", "wordmark": None, "addrs": ["nyc_madison"]},
        {"en": "Silverline Software Inc.", "short": "silverline", "cjk": None, "domain": "silverline.io", "industry": "tech", "wordmark": None, "addrs": ["nyc_bway"]},
        {"en": "Empire Gourmet Imports Inc.", "short": "EMPIRE GOURMET", "cjk": "帝國美食進口公司", "domain": "empiregourmet.com", "industry": "food", "wordmark": "AURORA BAY", "addrs": ["nyc_canal", "nyc_bway"]},
        {"en": "Atlas Bay Bank", "short": "ATLAS BAY", "cjk": "亞特拉斯灣銀行", "domain": "atlasbaybank.com", "industry": "finance", "wordmark": None, "addrs": ["nyc_bway", "nyc_canal"]},
        {"en": "Redwood Supply Co.", "short": "REDWOOD", "cjk": None, "domain": "redwoodsupply.com", "industry": "trading", "wordmark": None, "addrs": ["nyc_canal"]},
    ],
    "TW": [
        {"en": "Da Ming Food Co., Ltd.", "short": "DA MING", "cjk": "大明食品股份有限公司", "domain": "daming-food.com.tw", "industry": "food", "wordmark": None, "addrs": ["tpe_songren", "tyn_factory"]},
        {"en": "Chia Feng Foods Co., Ltd.", "short": "CHIA FENG", "cjk": "嘉豐食品股份有限公司", "domain": "chiafeng.com.tw", "industry": "food", "wordmark": "金穗", "addrs": ["ntp_wenhua", "tyn_factory"]},
        {"en": "Ruiguang Cold Chain Logistics Co., Ltd.", "short": "RUIGUANG", "cjk": "瑞光冷鏈物流股份有限公司", "domain": "ruiguang-logistics.com.tw", "industry": "logistics", "wordmark": None, "addrs": ["tpe_neihu", "tyn_factory"]},
        {"en": "Heng Chang International Trading Co., Ltd.", "short": "HENG CHANG", "cjk": "恆昌國際貿易有限公司", "domain": "hengchang-trade.com.tw", "industry": "trading", "wordmark": None, "addrs": ["tpe_nanjing"]},
        {"en": "Xinhe Technology Inc.", "short": "XINHE", "cjk": "新禾科技股份有限公司", "domain": "xinhetech.com.tw", "industry": "tech", "wordmark": None, "addrs": ["tpe_neihu", "txg_taiwan"]},
        {"en": "Dawnlight Design Studio", "short": "dawnlight", "cjk": "晨曦設計工作室", "domain": "dawnlight.design", "industry": "design", "wordmark": None, "addrs": ["tpe_songren"]},
        {"en": "Fu Yuan Seafood Co., Ltd.", "short": "FU YUAN", "cjk": "福源水產有限公司", "domain": "fuyuanseafood.com.tw", "industry": "food", "wordmark": "海之味", "addrs": ["txg_taiwan", "tyn_factory"]},
        {"en": "Hebang Commercial Bank", "short": "HEBANG BANK", "cjk": "合邦商業銀行", "domain": "hebangbank.com.tw", "industry": "finance", "wordmark": None, "addrs": ["tpe_nanjing", "txg_taiwan"]},
    ],
    "HK": [
        {"en": "Chan & Chan Trading Ltd.", "short": "CHAN & CHAN", "cjk": "陳陳貿易有限公司", "domain": "chanandchan.com.hk", "industry": "trading", "wordmark": None, "addrs": ["hk_canton", "hk_kwuntong"]},
        {"en": "Harbour Trust CPA Limited", "short": "HARBOUR TRUST", "cjk": "港信會計師事務所有限公司", "domain": "harbourtrustcpa.com.hk", "industry": "finance", "wordmark": None, "addrs": ["hk_queens"]},
        {"en": "Wui Tai Foods Limited", "short": "WUI TAI", "cjk": "滙泰食品有限公司", "domain": "wuitaifoods.com.hk", "industry": "food", "wordmark": "GOLDEN BOWL", "addrs": ["hk_kwuntong", "hk_canton"]},
        {"en": "Kowloon Bay Logistics Ltd.", "short": "KB LOGISTICS", "cjk": "九龍灣物流有限公司", "domain": "kblogistics.com.hk", "industry": "logistics", "wordmark": None, "addrs": ["hk_kwuntong"]},
    ],
    "CN": [
        {"en": "Shanghai Xinyuan Food Co., Ltd.", "short": "XINYUAN", "cjk": "上海鑫源食品有限公司", "domain": "xinyuanfood.com.cn", "industry": "food", "wordmark": "鲜之源", "addrs": ["sh_zhangjiang"]},
        {"en": "Shenzhen Haichuan Electronic Technology Co., Ltd.", "short": "HAICHUAN", "cjk": "深圳市海川电子科技有限公司", "domain": "haichuan-tech.cn", "industry": "tech", "wordmark": None, "addrs": ["sz_nanshan"]},
        {"en": "Guangzhou Hengtai Import & Export Co., Ltd.", "short": "HENGTAI", "cjk": "广州恒泰进出口贸易有限公司", "domain": "hengtai-trade.com", "industry": "trading", "wordmark": None, "addrs": ["gz_tianhe"]},
        {"en": "Beijing Yunfan Software Co., Ltd.", "short": "YUNFAN", "cjk": "北京云帆软件有限公司", "domain": "yunfansoft.cn", "industry": "tech", "wordmark": "CloudSail", "addrs": ["bj_jianguo"]},
        {"en": "Hangzhou Qinghe Tea Co., Ltd.", "short": "QINGHE TEA", "cjk": "杭州青禾茶业有限公司", "domain": "qinghetea.com", "industry": "tea", "wordmark": None, "addrs": ["hz_xihu"]},
        {"en": "Suzhou Ruida Packaging Materials Co., Ltd.", "short": "RUIDA", "cjk": "苏州瑞达包装材料有限公司", "domain": "ruidapack.com.cn", "industry": "packaging", "wordmark": None, "addrs": ["sz_suzhou", "sh_zhangjiang"]},
        {"en": "Dalian Haiyun Aquatic Products Co., Ltd.", "short": "HAIYUN", "cjk": "大连海韵水产有限公司", "domain": "haiyunseafood.cn", "industry": "food", "wordmark": None, "addrs": ["dl_port", "sh_zhangjiang"]},
    ],
}

# ---------------------------------------------------------------- titles / departments
# (en, zh-Hant, zh-Hans)
TITLES = {
    "food": [("Sales Manager", "業務經理", "销售经理"), ("Purchasing Manager", "採購經理", "采购经理"),
             ("Export Manager", "外銷經理", "出口经理"), ("General Manager", "總經理", "总经理"),
             ("Quality Assurance Manager", "品保經理", "质量经理"), ("President", "董事長", "董事长"),
             ("Account Executive", "業務專員", "客户专员")],
    "logistics": [("Logistics Coordinator", "物流專員", "物流专员"), ("Director of Operations", "營運總監", "运营总监"),
                  ("Business Development Manager", "業務開發經理", "业务拓展经理"), ("General Manager", "總經理", "总经理")],
    "trading": [("Sales Manager", "業務經理", "销售经理"), ("Vice President, Sales", "業務副總經理", "销售副总裁"),
                ("Purchasing Manager", "採購經理", "采购经理"), ("Managing Director", "董事總經理", "董事总经理")],
    "tech": [("Senior Software Engineer", "資深軟體工程師", "高级软件工程师"), ("Product Manager", "產品經理", "产品经理"),
             ("Founder & CEO", "創辦人暨執行長", "创始人兼首席执行官"), ("Marketing Specialist", "行銷專員", "市场专员")],
    "finance": [("Relationship Manager", "理財專員", "客户经理"), ("Chief Financial Officer", "財務長", "首席财务官"),
                ("Branch Manager", "分行經理", "支行行长"), ("Partner", "合夥人", "合伙人"), ("Vice President", "副總裁", "副总裁")],
    "consulting": [("Partner", "合夥人", "合伙人"), ("Senior Consultant", "資深顧問", "高级顾问"), ("Associate", "專員", "专员")],
    "design": [("Senior Designer", "資深設計師", "高级设计师"), ("Creative Director", "創意總監", "创意总监")],
    "tea": [("Sales Manager", "業務經理", "销售经理"), ("General Manager", "總經理", "总经理")],
    "packaging": [("Account Manager", "客戶經理", "客户经理"), ("Plant Manager", "廠長", "厂长"), ("Sales Representative", "業務代表", "销售代表")],
}
DEPARTMENTS = {
    "food": [("Sales Department", "業務部", "销售部"), ("International Trade Division", "國際貿易部", "国际贸易部"), ("Procurement", "採購部", "采购部"), ("Quality Assurance", "品保部", "质量部")],
    "logistics": [("Operations", "營運部", "运营部"), ("Cold Chain Division", "冷鏈事業部", "冷链事业部")],
    "trading": [("Import & Export Dept.", "進出口部", "进出口部"), ("Sales Department", "業務部", "销售部")],
    "tech": [("R&D Center", "研發中心", "研发中心"), ("Marketing", "行銷部", "市场部")],
    "finance": [("Corporate Banking", "企業金融部", "公司金融部"), ("Wealth Management", "財富管理部", "财富管理部"), ("Audit & Assurance", "審計部", "审计部")],
    "consulting": [("Strategy Practice", "策略部", "战略部")],
    "design": [("Brand Studio", "品牌部", "品牌部")],
    "tea": [("Sales Department", "業務部", "销售部")],
    "packaging": [("Customer Service", "客服部", "客服部")],
}

# ---------------------------------------------------------------- distractor text
SLOGANS = {
    "food": {"en": ["Your Trusted Partner in Frozen Foods", "Fresh from Ocean to Table", "Taste the Difference", "Quality You Can Trust"],
             "zh-Hant": ["品質第一 服務至上", "新鮮直送 安心美味", "嚴選食材 用心把關"],
             "zh-Hans": ["品质第一 服务至上", "新鲜直送 安心美味", "严选食材 用心把关"]},
    "logistics": {"en": ["Delivering Freshness, Every Mile", "Cold Chain Experts", "On Time. Every Time."],
                  "zh-Hant": ["冷鏈專家 準時送達", "安全 準時 專業"], "zh-Hans": ["冷链专家 准时送达", "安全 准时 专业"]},
    "trading": {"en": ["Connecting Asia & North America", "Global Sourcing, Local Service"],
                "zh-Hant": ["誠信經營 互利共贏", "連結全球 服務在地"], "zh-Hans": ["诚信经营 互利共赢", "连接全球 服务本地"]},
    "tech": {"en": ["Build Smarter.", "Data that Drives Decisions", "Innovation for Tomorrow"],
             "zh-Hant": ["科技創新 引領未來"], "zh-Hans": ["科技创新 引领未来"]},
    "finance": {"en": ["Growing Together Since 1962", "Your Financial Partner", "Integrity. Insight. Results."],
                "zh-Hant": ["誠信 穩健 專業"], "zh-Hans": ["诚信 稳健 专业"]},
    "consulting": {"en": ["Clarity. Strategy. Results.", "Advice that Moves You Forward"], "zh-Hant": ["專業 誠信 創新"], "zh-Hans": ["专业 诚信 创新"]},
    "design": {"en": ["Design with Purpose", "Make It Beautiful"], "zh-Hant": ["設計 讓生活更美好"], "zh-Hans": ["设计 让生活更美好"]},
    "tea": {"en": ["From Our Gardens to Your Cup"], "zh-Hant": ["一片好茶 源自青山"], "zh-Hans": ["一片好茶 源自青山"]},
    "packaging": {"en": ["Packaging Solutions that Protect"], "zh-Hant": ["專業包裝 安全可靠"], "zh-Hans": ["专业包装 安全可靠"]},
}
CERTS = {
    "food": ["HACCP", "ISO 22000", "FSSC 22000", "BRCGS AA", "ISO 9001:2015"],
    "logistics": ["ISO 9001:2015", "HACCP", "GDP Certified"],
    "trading": ["ISO 9001:2015"],
    "tech": ["ISO 27001", "SOC 2 Type II"],
    "finance": ["ISO 27001"],
    "consulting": [],
    "design": [],
    "tea": ["ISO 22000", "Organic Certified"],
    "packaging": ["ISO 9001:2015", "ISO 14001", "FSC Certified"],
}
EST = {"en": ["Since {y}", "Est. {y}", "Established {y}"], "zh-Hant": ["創立於{y}年", "始於{y}"], "zh-Hans": ["创立于{y}年", "始于{y}"]}
DECOR_TEXT = {"en": ["Thank you", "THINK FRESH", "Let's grow together", "Good food, good life"],
              "zh-Hant": ["感謝您的支持", "用心 做好每一件事"], "zh-Hans": ["感谢您的支持", "用心 做好每一件事"]}

BRAND_COLORS = ["#0b4f8a", "#1d6b5f", "#8a1c2b", "#c4561d", "#2c3e50", "#6a2c8a", "#0f7d9c", "#b8860b",
                "#3b5d2a", "#a12a5e", "#14213d", "#d1495b", "#00798c", "#5b3e96", "#9a031e", "#386641"]

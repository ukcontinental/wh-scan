import XCTest
@testable import CardCore

final class PhoneTests: XCTestCase {
    func n(_ s: String, _ r: String? = nil) -> NormalizedPhone? { PhoneNormalizer.normalize(s, regionHint: r, defaultRegion: "CA") }

    func testNANPFormats() {
        XCTAssertEqual(n("(416) 555-0137")?.e164, "+14165550137")
        XCTAssertEqual(n("416.555.0137")?.e164, "+14165550137")
        XCTAssertEqual(n("+1 416 555 0137")?.e164, "+14165550137")
        XCTAssertEqual(n("1-800-555-0199")?.e164, "+18005550199")
        XCTAssertEqual(n("T 416.555.0137")?.e164, "+14165550137")
    }

    func testExtension() {
        let p = n("Tel: (416) 555-0137 ext. 204")
        XCTAssertEqual(p?.e164, "+14165550137")
        XCTAssertEqual(p?.extensionNumber, "204")
        XCTAssertEqual(n("02-2345-6789 分機 15", "TW")?.extensionNumber, "15")
        XCTAssertEqual(n("416-555-0137 x22")?.extensionNumber, "22")
    }

    func testTaiwan() {
        let m = n("0912-345-678")
        XCTAssertEqual(m?.e164, "+886912345678")
        XCTAssertEqual(m?.planType, .mobile)
        XCTAssertEqual(n("02-2345-6789", "TW")?.e164, "+886223456789")
        XCTAssertEqual(n("+886 (0)2 2345 6789")?.e164, "+886223456789")
        XCTAssertEqual(n("+886-912-345-678")?.planType, .mobile)
    }

    func testChinaAndHK() {
        XCTAssertEqual(n("138 1234 5678", "CN")?.e164, "+8613812345678")
        XCTAssertEqual(n("+86 21 6123 4567")?.e164, "+862161234567")
        XCTAssertEqual(n("021-6123 4567", "CN")?.e164, "+862161234567")
        let hk = n("+852 9123 4567")
        XCTAssertEqual(hk?.e164, "+85291234567")
        XCTAssertEqual(hk?.planType, .mobile)
        XCTAssertEqual(n("2123 4567", "HK")?.e164, "+85221234567")
    }

    func testInvalidNANP() {
        XCTAssertEqual(n("(116) 555-0137")?.isValid, false)
    }

    func testLabels() {
        XCTAssertEqual(PhoneNormalizer.kindFromLabel("M: 0912-345-678"), .mobile)
        XCTAssertEqual(PhoneNormalizer.kindFromLabel("傳真 Fax: 02-2345-6789"), .fax)
        XCTAssertEqual(PhoneNormalizer.kindFromLabel("手機：0912 345 678"), .mobile)
        XCTAssertEqual(PhoneNormalizer.kindFromLabel("Tel (416) 555-0137"), .work)
        XCTAssertNil(PhoneNormalizer.kindFromLabel("416 555 0137"))
    }
}

final class EmailTests: XCTestCase {
    func testRepair() {
        XCTAssertEqual(EmailValidator.repair(" John.Chen @ ABCFoods.com "), "john.chen@abcfoods.com")
        XCTAssertEqual(EmailValidator.repair("E: john@abcfoods,com."), "john@abcfoods.com")
        XCTAssertEqual(EmailValidator.repair("mary@gmial.com"), "mary@gmail.com")
        XCTAssertEqual(EmailValidator.repair("lee@abc.corn"), "lee@abc.com")
        XCTAssertEqual(EmailValidator.repair("王@例子.com".replacingOccurrences(of: "王", with: "w")), "w@例子.com")
    }

    func testValidate() {
        XCTAssertTrue(EmailValidator.isSyntacticallyValid("a.b@c.co.uk"))
        XCTAssertFalse(EmailValidator.isSyntacticallyValid("a..b@c.com"))
        XCTAssertFalse(EmailValidator.isSyntacticallyValid("ab.c.com"))
        let near = EmailValidator.validate("john@abcfood5.com", siblingDomains: ["www.abcfoods.com"])
        XCTAssertTrue(near.contains { $0.code == "email_domain_near_miss" })
        let ok = EmailValidator.validate("john@abcfoods.com", siblingDomains: ["abcfoods.com"])
        XCTAssertTrue(ok.contains { $0.code == "email_domain_matches_website" })
    }

    func testDomains() {
        XCTAssertEqual(DomainUtil.host(fromURL: "https://www.ABCFoods.com/contact"), "abcfoods.com")
        XCTAssertEqual(DomainUtil.registrable("mail.abcfoods.com.tw"), "abcfoods.com.tw")
        XCTAssertEqual(DomainUtil.label("www.abcfoods.com.tw"), "abcfoods")
    }
}

final class NameTests: XCTestCase {
    func testSplitCJK() {
        XCTAssertEqual(NameUtil.splitCJK("王大明").family, "王")
        XCTAssertEqual(NameUtil.splitCJK("王大明").given, "大明")
        XCTAssertEqual(NameUtil.splitCJK("歐陽志明").family, "歐陽")
        XCTAssertEqual(NameUtil.splitCJK("欧阳志明").family, "欧阳")
    }

    func testCrossScript() {
        XCTAssertGreaterThanOrEqual(NameUtil.crossScriptMatch(latinGiven: "David", latinFamily: "Wang", cjkFull: "王大明"), 0.75)
        XCTAssertGreaterThanOrEqual(NameUtil.crossScriptMatch(latinGiven: "Victoria", latinFamily: "Chan", cjkFull: "陳美玲"), 0.75)
        XCTAssertGreaterThanOrEqual(NameUtil.crossScriptMatch(latinGiven: "Ming-Hui", latinFamily: "Chen", cjkFull: "陳明輝"), 0.9)
        XCTAssertGreaterThanOrEqual(NameUtil.crossScriptMatch(latinGiven: "Wei", latinFamily: "Zhang", cjkFull: "张伟"), 0.9)
        XCTAssertLessThan(NameUtil.crossScriptMatch(latinGiven: "John", latinFamily: "Smith", cjkFull: "王大明"), 0.5)
    }

    func testNameShape() {
        XCTAssertTrue(NameUtil.looksLikePersonName("John Chen"))
        XCTAssertTrue(NameUtil.looksLikePersonName("王大明"))
        XCTAssertFalse(NameUtil.looksLikePersonName("ABC Foods Ltd."))
        XCTAssertFalse(NameUtil.looksLikePersonName("品質第一服務至上"))
        XCTAssertFalse(NameUtil.looksLikePersonName("john@abc.com"))
    }

    func testCompany() {
        XCTAssertEqual(CompanyUtil.key("ABC Foods Ltd."), CompanyUtil.key("ABC FOODS LIMITED"))
        XCTAssertEqual(CompanyUtil.key("大明食品股份有限公司"), CompanyUtil.key("大明食品有限公司"))
        XCTAssertEqual(CompanyUtil.domainAffinity(company: "ABC Foods Ltd.", domainLabel: "abcfoods"), 1)
        XCTAssertGreaterThanOrEqual(CompanyUtil.domainAffinity(company: "Pacific Rim Logistics Inc.", domainLabel: "prl"), 0.8)
        XCTAssertTrue(CompanyUtil.hasLegalSuffix("Chan & Chan Trading Co."))
    }
}

final class AddressTests: XCTestCase {
    func testCountryInference() {
        XCTAssertEqual(AddressValidator.inferCountry(ExtractedAddress(city: "Toronto", region: "ON", postalCode: "M5J 2M2", confidence: 1)), "CA")
        XCTAssertEqual(AddressValidator.inferCountry(ExtractedAddress(formatted: "台北市信義區松仁路100號", confidence: 1)), "TW")
        XCTAssertEqual(AddressValidator.inferCountry(ExtractedAddress(city: "New York", region: "NY", postalCode: "10001", confidence: 1)), "US")
    }

    func testPostalRepair() {
        XCTAssertEqual(AddressValidator.repairCanadianPostalCode("M5J 2MZ"), "M5J 2M2")
        XCTAssertEqual(AddressValidator.repairCanadianPostalCode("MSJ2M2"), "M5J 2M2")
    }
}

final class OCRCrossCheckTests: XCTestCase {
    let ocr = OCRResult(engine: "test", lines: [
        OCRLine(text: "John Chen", confidence: 0.95), OCRLine(text: "Sales Manager", confidence: 0.9),
        OCRLine(text: "ABC Foods Ltd.", confidence: 0.95), OCRLine(text: "M 416.555.0137", confidence: 0.9),
        OCRLine(text: "john.chen@abcfoods.com", confidence: 0.9),
    ])

    func testSupport() {
        XCTAssertEqual(OCRCrossCheck.support(value: "+1 416-555-0137", kind: .phone, ocr: ocr), .strong)
        XCTAssertEqual(OCRCrossCheck.support(value: "416-555-0187", kind: .phone, ocr: ocr), .conflict)
        XCTAssertEqual(OCRCrossCheck.support(value: "john.chen@abcfeods.com", kind: .email, ocr: ocr), .conflict)
        XCTAssertEqual(OCRCrossCheck.support(value: "john.chen@abcfood5.com", kind: .email, ocr: ocr), .partial)
        XCTAssertEqual(OCRCrossCheck.support(value: "905-555-0100", kind: .phone, ocr: ocr), .none)
        XCTAssertEqual(OCRCrossCheck.support(value: "john.chen@abcfoods.com", kind: .email, ocr: ocr), .strong)
        XCTAssertEqual(OCRCrossCheck.support(value: "Sales Director", kind: .jobTitle, ocr: ocr), .none)
        XCTAssertEqual(OCRCrossCheck.support(value: "王大明", kind: .personName, ocr: ocr), .unavailable)
    }
}

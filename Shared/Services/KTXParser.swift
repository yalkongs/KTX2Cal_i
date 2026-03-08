import Foundation

/// KTX 앱 공유 텍스트 파서
/// 실제 공유 형식 예시:
///   승차일자 2026년 3월 11일 (수)
///   KTX-산천 195
///   행신(21:10)출발 → 동대구(23:21)도착
class KTXParser {

    // MARK: - 공개 인터페이스

    /// Share Extension에서 받은 공유 텍스트 파싱
    func parseSharedText(_ text: String) -> KTXTicket? {
        // \r\n(Windows) 및 단독 \r(CR)을 모두 \n으로 정규화
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return parse(lines: lines, rawText: text)
    }

    /// OCR 결과 파싱 (이미지 공유 fallback)
    func parse(lines: [String], rawText: String = "") -> KTXTicket? {
        let text = lines.joined(separator: "\n")
        print("=== KTXParser 입력 ===\n\(text)\n=====================")

        var trainNumber      = ""
        var trainType        = ""
        var departureStation = ""
        var arrivalStation   = ""
        var departureDate: Date?
        var arrivalDate: Date?
        var carNumber        = ""
        var seatNumber       = ""
        var passengerName    = ""
        var ticketClass      = ""
        var price            = ""
        var travelDateStr    = ""

        // ── 1. 날짜 파싱 ────────────────────────────────────
        // "승차일자 2026년 3월 11일 (수)" 또는 "2026.03.11"
        let datePatterns: [(String, Bool)] = [
            // (패턴, 2자리연도여부)
            (#"(\d{4})년\s*(\d{1,2})월\s*(\d{1,2})일"#, false),
            (#"(\d{4})[./\-](\d{1,2})[./\-](\d{1,2})"#, false),
            (#"(\d{2})[./](\d{1,2})[./](\d{1,2})"#, true)
        ]
        for (pattern, twoDigit) in datePatterns {
            if let m = regexMatch(pattern, in: text) {
                var y  = Int(m[1]) ?? 0
                if twoDigit { y += 2000 }
                let mo = Int(m[2]) ?? 0
                let d  = Int(m[3]) ?? 0
                travelDateStr = String(format: "%04d-%02d-%02d", y, mo, d)
                break
            }
        }

        // ── 2. 열차 종류 + 번호 ─────────────────────────────
        // "KTX-산천 195", "KTX 101", "SRT 301"
        if let m = regexMatch(
            #"(KTX-청룡|KTX-산천|KTX|SRT|ITX-새마을|ITX-마음|무궁화|누리로)\s*(\d{1,4})"#,
            in: text
        ) {
            trainType   = m[1]
            trainNumber = m[2]
        }
        if trainType.isEmpty { trainType = "KTX" }

        // ── 3. 구간 + 시간 (핵심 패턴) ──────────────────────
        // "행신(21:10)출발 → 동대구(23:21)도착"
        // "서울(09:30)출발 → 부산(11:45)도착"
        let routePattern = #"([가-힣A-Za-z·\s]{2,6})\((\d{1,2}:\d{2})\)출발\s*[→▶>]\s*([가-힣A-Za-z·\s]{2,6})\((\d{1,2}:\d{2})\)도착"#
        if let m = regexMatch(routePattern, in: text) {
            departureStation = cleanStation(m[1])
            arrivalStation   = cleanStation(m[3])
            departureDate    = makeDate(dateStr: travelDateStr, timeStr: m[2])
            arrivalDate      = makeDate(dateStr: travelDateStr, timeStr: m[4])

            // 심야 열차: 도착이 출발보다 이르면 다음날
            if let dep = departureDate, let arr = arrivalDate, arr < dep {
                arrivalDate = Calendar.current.date(byAdding: .day, value: 1, to: arr)
            }
        } else {
            // Fallback: 역명과 시간을 별도로 추출
            // "서울 → 부산" 형태
            if let m = regexMatch(#"([가-힣]{2,5})\s*[→▶>]\s*([가-힣]{2,5})"#, in: text) {
                departureStation = cleanStation(m[1])
                arrivalStation   = cleanStation(m[2])
            }
            // 시간: "21:10", "21시10분"
            let timePattern = #"(\d{1,2})[:시]\s*(\d{2})분?"#
            let times = allRegexMatches(timePattern, in: text).compactMap { m -> (Int, Int)? in
                let h = Int(m[1]) ?? -1, mn = Int(m[2]) ?? -1
                guard h >= 0, h < 24, mn >= 0, mn < 60 else { return nil }
                return (h, mn)
            }
            if times.count >= 2 {
                departureDate = makeDate(dateStr: travelDateStr, h: times[0].0, m: times[0].1)
                arrivalDate   = makeDate(dateStr: travelDateStr, h: times[1].0, m: times[1].1)
                if let dep = departureDate, let arr = arrivalDate, arr < dep {
                    arrivalDate = Calendar.current.date(byAdding: .day, value: 1, to: arr)
                }
            } else if times.count == 1 {
                departureDate = makeDate(dateStr: travelDateStr, h: times[0].0, m: times[0].1)
                arrivalDate = departureDate.map { Calendar.current.date(byAdding: .hour, value: 2, to: $0)! }
            }
        }

        // ── 4. 좌석 정보 ─────────────────────────────────────
        // "3호차 15A번", "3-15A", "호차3 좌석15A"
        if let m = regexMatch(#"(\d+)\s*호차\s*(\d+[A-Za-z가-힣]?)번?"#, in: text) {
            carNumber = m[1]; seatNumber = m[2]
        } else {
            if let m = regexMatch(#"(\d+)호차"#, in: text)             { carNumber  = m[1] }
            if let m = regexMatch(#"(\d+[A-Za-z])번?\s*(?:좌석)?"#, in: text) { seatNumber = m[1] }
        }

        // ── 5. 등급 ──────────────────────────────────────────
        for kw in ["특실", "우등실", "일반실"] {
            if text.contains(kw) { ticketClass = kw; break }
        }

        // ── 6. 운임 ──────────────────────────────────────────
        if let m = regexMatch(#"(\d{1,3}(?:,\d{3})+|\d{4,6})\s*원"#, in: text) {
            price = m[1]
        }

        // ── 7. 성명 ──────────────────────────────────────────
        for pattern in [#"(?:성명|이름|승객)\s*:?\s*([가-힣]{2,5})"#, #"([가-힣]{2,4})님"#] {
            if let m = regexMatch(pattern, in: text) { passengerName = m[1]; break }
        }

        // ── 유효성 검사 ───────────────────────────────────────
        guard let depDate = departureDate else {
            print("⚠️ 파싱 실패: 출발 시간을 찾지 못했습니다.")
            return nil
        }

        return KTXTicket(
            trainNumber: trainNumber.isEmpty ? "미확인" : trainNumber,
            trainType: trainType,
            departureStation: departureStation.isEmpty ? "미확인" : departureStation,
            arrivalStation: arrivalStation.isEmpty ? "미확인" : arrivalStation,
            departureDate: depDate,
            arrivalDate: arrivalDate ?? Calendar.current.date(byAdding: .hour, value: 2, to: depDate)!,
            carNumber: carNumber,
            seatNumber: seatNumber,
            passengerName: passengerName,
            ticketClass: ticketClass,
            price: price,
            rawSharedText: rawText
        )
    }

    // MARK: - 헬퍼

    private func cleanStation(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
         .replacingOccurrences(of: "역", with: "")
    }

    private func makeDate(dateStr: String, timeStr: String) -> Date? {
        let parts = timeStr.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2 else { return nil }
        return makeDate(dateStr: dateStr, h: parts[0], m: parts[1])
    }

    private func makeDate(dateStr: String, h: Int, m: Int) -> Date? {
        let dateParts = dateStr.split(separator: "-").compactMap { Int($0) }
        var dc = DateComponents()
        if dateParts.count == 3 {
            dc.year = dateParts[0]; dc.month = dateParts[1]; dc.day = dateParts[2]
        } else {
            // 날짜 정보 없으면 오늘
            let today = Calendar.current.dateComponents([.year, .month, .day], from: Date())
            dc.year = today.year; dc.month = today.month; dc.day = today.day
        }
        dc.hour = h; dc.minute = m; dc.second = 0
        return Calendar.current.date(from: dc)
    }

    private func regexMatch(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (0..<m.numberOfRanges).map {
            guard let r = Range(m.range(at: $0), in: text) else { return "" }
            return String(text[r])
        }
    }

    private func allRegexMatches(_ pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { m in
            (0..<m.numberOfRanges).map {
                guard let r = Range(m.range(at: $0), in: text) else { return "" }
                return String(text[r])
            }
        }
    }
}

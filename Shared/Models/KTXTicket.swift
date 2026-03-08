import Foundation

struct KTXTicket: Identifiable, Equatable, Codable {
    let id: UUID
    var trainNumber: String       // 열차번호
    var trainType: String         // 열차종류 (KTX, KTX-산천, SRT 등)
    var departureStation: String  // 출발역
    var arrivalStation: String    // 도착역
    var departureDate: Date       // 출발 날짜+시간
    var arrivalDate: Date         // 도착 날짜+시간
    var carNumber: String         // 호차
    var seatNumber: String        // 좌석번호
    var passengerName: String     // 승객명
    var ticketClass: String       // 등급 (특실/일반실)
    var price: String             // 운임
    var rawSharedText: String     // 원본 공유 텍스트

    init(
        id: UUID = UUID(),
        trainNumber: String,
        trainType: String,
        departureStation: String,
        arrivalStation: String,
        departureDate: Date,
        arrivalDate: Date,
        carNumber: String = "",
        seatNumber: String = "",
        passengerName: String = "",
        ticketClass: String = "",
        price: String = "",
        rawSharedText: String = ""
    ) {
        self.id = id
        self.trainNumber = trainNumber
        self.trainType = trainType
        self.departureStation = departureStation
        self.arrivalStation = arrivalStation
        self.departureDate = departureDate
        self.arrivalDate = arrivalDate
        self.carNumber = carNumber
        self.seatNumber = seatNumber
        self.passengerName = passengerName
        self.ticketClass = ticketClass
        self.price = price
        self.rawSharedText = rawSharedText
    }

    var eventTitle: String {
        "\(trainType) \(trainNumber) | \(departureStation)→\(arrivalStation)"
    }

    var eventNotes: String {
        var lines = [String]()
        lines.append("🚄 \(trainType) \(trainNumber)")
        lines.append("📍 \(departureStation) → \(arrivalStation)")
        if !carNumber.isEmpty    { lines.append("🚃 \(carNumber)호차 \(seatNumber)번") }
        if !passengerName.isEmpty { lines.append("👤 \(passengerName)") }
        if !ticketClass.isEmpty  { lines.append("💺 \(ticketClass)") }
        if !price.isEmpty        { lines.append("💰 \(price)원") }
        lines.append("")
        lines.append("📱 KTX캘린더 앱으로 자동 등록됨")
        return lines.joined(separator: "\n")
    }

    static var sample: KTXTicket {
        let cal = Calendar.current
        let now = Date()
        let dep = cal.date(bySettingHour: 9,  minute: 30, second: 0, of: now) ?? now
        let arr = cal.date(bySettingHour: 11, minute: 45, second: 0, of: now) ?? now
        return KTXTicket(
            trainNumber: "101",
            trainType: "KTX",
            departureStation: "서울",
            arrivalStation: "부산",
            departureDate: dep,
            arrivalDate: arr,
            carNumber: "3",
            seatNumber: "15A",
            passengerName: "홍길동",
            ticketClass: "일반실",
            price: "59,800",
            rawSharedText: "KTX 101\n서울→부산\n09:30→11:45\n3호차 15A"
        )
    }
}

import Foundation

/// App Group을 통해 메인 앱 ↔ Share Extension 간 티켓 히스토리 공유
class TicketStore {
    static let shared = TicketStore()

    private let appGroupID = "group.com.yalkongs.KTXCalendar"
    private let storageKey = "savedTickets"

    private var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    private init() {}

    func save(_ ticket: KTXTicket) {
        var tickets = loadAll()
        // 최신 순 정렬, 최대 50개 유지
        tickets.insert(ticket, at: 0)
        if tickets.count > 50 { tickets = Array(tickets.prefix(50)) }

        if let data = try? JSONEncoder().encode(tickets) {
            defaults?.set(data, forKey: storageKey)
        }
    }

    func loadAll() -> [KTXTicket] {
        guard let data = defaults?.data(forKey: storageKey),
              let tickets = try? JSONDecoder().decode([KTXTicket].self, from: data) else {
            return []
        }
        return tickets
    }

    func deleteAll() {
        defaults?.removeObject(forKey: storageKey)
    }
}

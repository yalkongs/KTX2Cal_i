import EventKit
import Foundation

/// iOS EventKit 기반 캘린더 연동
/// → iPhone에 Google Calendar 계정이 추가되어 있으면 자동으로 Google Calendar에 동기화
class CalendarService: ObservableObject {

    private let eventStore = EKEventStore()

    @Published var authorizationStatus: EKAuthorizationStatus = .notDetermined
    @Published var availableCalendars: [EKCalendar] = []
    @Published var selectedCalendar: EKCalendar?

    /// 이 앱이 등록한 이벤트 식별 마커 (eventNotes에 포함)
    static let ktxMarker = "#KTXCalendar"

    init() {
        updateAuthorizationStatus()
    }

    func updateAuthorizationStatus() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
    }

    // MARK: - 권한

    func requestAccess() async -> Bool {
        do {
            let granted: Bool
            if #available(iOS 17.0, *) {
                granted = try await eventStore.requestFullAccessToEvents()
            } else {
                granted = try await eventStore.requestAccess(to: .event)
            }
            await MainActor.run {
                updateAuthorizationStatus()
                if granted { loadCalendars() }
            }
            return granted
        } catch {
            print("캘린더 접근 권한 요청 실패: \(error)")
            return false
        }
    }

    // MARK: - 캘린더 목록

    func loadCalendars() {
        let calendars = eventStore.calendars(for: .event)
            .filter { $0.allowsContentModifications }
            .sorted { $0.title < $1.title }
        availableCalendars = calendars

        // Google Calendar 계정 우선 선택
        selectedCalendar = calendars.first {
            $0.source.sourceType == .calDAV &&
            ($0.source.title.lowercased().contains("google") ||
             $0.source.title.contains("Gmail"))
        } ?? eventStore.defaultCalendarForNewEvents
    }

    // MARK: - KTX 이벤트 조회

    /// 캘린더에서 이 앱으로 등록한 KTX 이벤트 조회 (과거 6개월 ~ 미래 1년)
    func fetchKTXEvents() -> [EKEvent] {
        let now    = Date()
        let past   = Calendar.current.date(byAdding: .month, value: -6, to: now) ?? now
        let future = Calendar.current.date(byAdding: .year,  value:  1, to: now) ?? now

        let predicate = eventStore.predicateForEvents(
            withStart: past, end: future, calendars: nil
        )
        return eventStore.events(matching: predicate)
            .filter { isKTXCalendarEvent($0) }
            .sorted { $0.startDate < $1.startDate }
    }

    /// 이 앱이 등록한 KTX 이벤트인지 판별
    private func isKTXCalendarEvent(_ event: EKEvent) -> Bool {
        // 앱 마커 포함 여부 (가장 정확)
        if let notes = event.notes, notes.contains(Self.ktxMarker) { return true }
        return false
    }

    // MARK: - 이벤트 추가

    @discardableResult
    func addEvent(ticket: KTXTicket, calendar: EKCalendar? = nil) async -> Result<String, CalendarError> {
        if authorizationStatus != .fullAccess && authorizationStatus != .authorized {
            let granted = await requestAccess()
            if !granted { return .failure(.accessDenied) }
        }

        return await withCheckedContinuation { continuation in
            let event = EKEvent(eventStore: eventStore)
            event.calendar  = calendar ?? selectedCalendar ?? eventStore.defaultCalendarForNewEvents
            event.title     = ticket.eventTitle
            event.startDate = ticket.departureDate
            event.endDate   = ticket.arrivalDate
            // 앱 마커를 노트에 포함 → 나중에 조회/식별용
            event.notes     = ticket.eventNotes + "\n\n" + Self.ktxMarker
            event.location  = "\(ticket.departureStation)역"
            event.addAlarm(EKAlarm(relativeOffset: -30 * 60))  // 출발 30분 전 알림

            do {
                try eventStore.save(event, span: .thisEvent)
                continuation.resume(returning: .success(event.eventIdentifier ?? ""))
            } catch {
                continuation.resume(returning: .failure(.saveFailed(error.localizedDescription)))
            }
        }
    }

    // MARK: - 이벤트 삭제

    /// 이벤트 ID로 캘린더에서 삭제 (리스트 '취소' 기능)
    @discardableResult
    func deleteEvent(eventIdentifier: String) -> Result<Void, CalendarError> {
        guard let event = eventStore.event(withIdentifier: eventIdentifier) else {
            return .failure(.notFound)
        }
        do {
            try eventStore.remove(event, span: .thisEvent, commit: true)
            return .success(())
        } catch {
            return .failure(.saveFailed(error.localizedDescription))
        }
    }

    // MARK: - 중복 체크

    func isDuplicate(ticket: KTXTicket) -> Bool {
        let predicate = eventStore.predicateForEvents(
            withStart: ticket.departureDate.addingTimeInterval(-60),
            end: ticket.departureDate.addingTimeInterval(60),
            calendars: nil
        )
        return eventStore.events(matching: predicate)
            .contains { $0.title == ticket.eventTitle }
    }

    // MARK: - 에러 타입

    enum CalendarError: LocalizedError {
        case accessDenied
        case saveFailed(String)
        case notFound

        var errorDescription: String? {
            switch self {
            case .accessDenied:        return "캘린더 접근 권한이 없습니다. 설정에서 허용해 주세요."
            case .saveFailed(let m):   return "이벤트 처리 실패: \(m)"
            case .notFound:            return "캘린더에서 해당 일정을 찾을 수 없습니다."
            }
        }
    }
}

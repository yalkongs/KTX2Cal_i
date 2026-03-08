import SwiftUI
import EventKit

struct ContentView: View {
    @StateObject private var calendarService = CalendarService()

    // EventKit에서 불러온 KTX 이벤트 목록
    @State private var ktxEvents: [EKEvent] = []
    @State private var isLoading = false
    @State private var deleteError: String?
    @State private var showDeleteConfirm = false
    @State private var eventToDelete: EKEvent?

    private static let sectionDateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy년 M월"
        f.locale = Locale(identifier: "ko_KR")
        return f
    }()

    var body: some View {
        NavigationStack {
            contentArea
                .navigationTitle("🚄 KTX 일정")
                .navigationBarTitleDisplayMode(.large)
                .toolbar { refreshButton }
                .alert("일정 취소", isPresented: $showDeleteConfirm, presenting: eventToDelete, actions: deleteAlertActions, message: deleteAlertMessage)
                .alert("삭제 오류", isPresented: showErrorBinding) { Button("확인") { deleteError = nil } } message: { Text(deleteError ?? "") }
        }
        .task {
            await calendarService.requestAccess()
            loadEvents()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            loadEvents()
        }
    }

    private var showErrorBinding: Binding<Bool> {
        Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })
    }

    @ViewBuilder
    private var contentArea: some View {
        if calendarService.authorizationStatus == .notDetermined {
            permissionView
        } else if calendarService.authorizationStatus == .denied
               || calendarService.authorizationStatus == .restricted {
            accessDeniedView
        } else if isLoading {
            ProgressView("불러오는 중...").frame(maxHeight: .infinity)
        } else if ktxEvents.isEmpty {
            emptyView
        } else {
            ticketList
        }
    }

    private var refreshButton: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Button { loadEvents() } label: { Image(systemName: "arrow.clockwise") }
        }
    }

    @ViewBuilder
    private func deleteAlertActions(_ event: EKEvent) -> some View {
        Button("삭제", role: .destructive) { deleteEvent(event) }
        Button("취소", role: .cancel) {}
    }

    private func deleteAlertMessage(_ event: EKEvent) -> some View {
        Text("\"\(event.title ?? "")\" 일정을 캘린더에서 삭제합니다.")
    }

    // MARK: - 티켓 리스트

    /// 가장 가까운 예정 이벤트의 ID (스크롤 기준)
    private var firstUpcomingEventID: String? {
        ktxEvents
            .filter { $0.startDate >= Date() }
            .min(by: { $0.startDate < $1.startDate })?
            .eventIdentifier
    }

    private var ticketList: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(groupedByMonth, id: \.0) { (month, events) in
                    Section(month) {
                        ForEach(events, id: \.eventIdentifier) { event in
                            KTXEventRow(event: event) {
                                eventToDelete = event
                                showDeleteConfirm = true
                            }
                            .id(event.eventIdentifier)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .refreshable { loadEvents() }
            .onChange(of: ktxEvents) {
                scrollToFirstUpcoming(proxy: proxy)
            }
        }
    }

    private func scrollToFirstUpcoming(proxy: ScrollViewProxy) {
        guard let id = firstUpcomingEventID else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            proxy.scrollTo(id, anchor: .top)
        }
    }

    /// 월별 그룹핑 (승차 시간 오름차순)
    private var groupedByMonth: [(String, [EKEvent])] {
        var dict: [String: [EKEvent]] = [:]
        for event in ktxEvents {
            let key = Self.sectionDateFmt.string(from: event.startDate)
            dict[key, default: []].append(event)
        }
        return dict
            .map { ($0.key, $0.value.sorted { $0.startDate < $1.startDate }) }
            .sorted { $0.0 < $1.0 }
    }

    // MARK: - 로직

    private func loadEvents() {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let events = calendarService.fetchKTXEvents()
            DispatchQueue.main.async {
                ktxEvents = events
                isLoading = false
            }
        }
    }

    private func deleteEvent(_ event: EKEvent) {
        let id = event.eventIdentifier ?? ""
        let result = calendarService.deleteEvent(eventIdentifier: id)
        switch result {
        case .success:
            withAnimation { ktxEvents.removeAll { $0.eventIdentifier == id || ($0.eventIdentifier ?? "") == id } }
        case .failure(let error):
            deleteError = error.localizedDescription
        }
    }

    // MARK: - 보조 뷰

    private var permissionView: some View {
        VStack(spacing: 20) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 60)).foregroundColor(.blue)
            Text("캘린더 접근 권한 필요")
                .font(.title2).bold()
            Text("KTX 일정을 저장하고 조회하려면\n캘린더 접근 권한이 필요합니다.")
                .multilineTextAlignment(.center).foregroundColor(.secondary)
            Button("권한 허용") {
                Task { await calendarService.requestAccess() }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private var accessDeniedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 60)).foregroundColor(.orange)
            Text("캘린더 접근이 거부됨")
                .font(.title2).bold()
            Text("설정 → 개인 정보 보호 → 캘린더에서\nKTX캘린더 앱의 접근을 허용해 주세요.")
                .multilineTextAlignment(.center).foregroundColor(.secondary)
            Button("설정 열기") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "train.side.front.car")
                .font(.system(size: 60)).foregroundColor(.secondary.opacity(0.4))
            Text("등록된 KTX 일정이 없습니다")
                .font(.headline).foregroundColor(.secondary)
            Text("KTX 앱에서 승차권을 선택한 후\n공유 버튼을 눌러 이 앱으로 공유하세요.")
                .font(.subheadline).foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 8) {
                Label("KTX 앱에서 승차권 선택", systemImage: "1.circle.fill")
                Label("공유 버튼 탭", systemImage: "2.circle.fill")
                Label("'KTX2Cal' 선택", systemImage: "3.circle.fill")
                Label("캘린더에 자동 추가!", systemImage: "4.circle.fill")
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
        .padding()
    }
}

// MARK: - KTX 이벤트 행

struct KTXEventRow: View {
    let event: EKEvent
    let onCancel: () -> Void

    private var isPast: Bool { event.startDate < Date() }

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()
    private static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d일 (E)"
        f.locale = Locale(identifier: "ko_KR")
        return f
    }()

    /// 이벤트 제목에서 열차 정보 파싱 "KTX-산천 195 | 행신→동대구"
    private var titleParts: (trainInfo: String, route: String) {
        let title = event.title ?? ""
        let parts = title.components(separatedBy: " | ")
        return (parts.first ?? title, parts.last ?? "")
    }

    var body: some View {
        HStack(spacing: 12) {
            // 날짜 뱃지
            VStack(spacing: 2) {
                Text(Self.dateFmt.string(from: event.startDate))
                    .font(.caption2).bold()
                    .foregroundColor(isPast ? .secondary : .blue)
                    .multilineTextAlignment(.center)

                if isPast {
                    Text("완료")
                        .font(.caption2)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(4)
                        .foregroundColor(.secondary)
                } else {
                    Text("예정")
                        .font(.caption2)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Color.blue.opacity(0.15))
                        .cornerRadius(4)
                        .foregroundColor(.blue)
                }
            }
            .frame(width: 52)

            Divider().frame(height: 44)

            // 경로 + 시간
            VStack(alignment: .leading, spacing: 4) {
                Text(titleParts.trainInfo)
                    .font(.subheadline).bold()
                    .lineLimit(1)
                    .foregroundColor(isPast ? .secondary : .primary)

                HStack(spacing: 4) {
                    if !titleParts.route.isEmpty {
                        Text(titleParts.route)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Text("·")
                        .font(.caption).foregroundColor(.secondary)
                    Text("\(Self.timeFmt.string(from: event.startDate)) 출발")
                        .font(.caption).foregroundColor(.secondary)
                    if let end = event.endDate {
                        Text("→ \(Self.timeFmt.string(from: end))")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            // 삭제 버튼
            Button {
                onCancel()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(isPast ? .secondary.opacity(0.5) : .red.opacity(0.7))
                    .font(.title3)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .opacity(isPast ? 0.45 : 1.0)
        .saturation(isPast ? 0.0 : 1.0)   // 과거 항목은 채도 제거 (흑백)
    }
}

#Preview {
    ContentView()
}

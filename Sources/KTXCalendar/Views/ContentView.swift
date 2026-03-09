import SwiftUI
import EventKit

// MARK: - Color Palette

private extension Color {
    /// 메인 KTX 블루 (선명한 코발트)
    static let ktxBlue   = Color(red: 0.14, green: 0.42, blue: 0.96)
    /// 보조 인디고
    static let ktxIndigo = Color(red: 0.32, green: 0.22, blue: 0.90)
    /// 앱 배경 (연한 청회색)
    static let ktxBg     = Color(red: 0.93, green: 0.94, blue: 0.98)
}

// MARK: - ContentView

struct ContentView: View {
    @StateObject private var calendarService = CalendarService()

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
                // ── 헤더 고정 (inline = 스크롤해도 사라지지 않음) ──
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
                .toolbarBackground(.visible,           for: .navigationBar)
                .toolbar {
                    // 그라디언트 커스텀 타이틀
                    ToolbarItem(placement: .principal) {
                        HStack(spacing: 5) {
                            Text("🚄")
                                .font(.system(size: 16))
                            Text("KTX 일정")
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.ktxBlue, .ktxIndigo],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        }
                    }
                    // 새로고침 버튼
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button { loadEvents() } label: {
                            Image(systemName: "arrow.clockwise")
                                .foregroundColor(.ktxBlue)
                        }
                    }
                }
                .background(Color.ktxBg.ignoresSafeArea())
                .alert("일정 취소", isPresented: $showDeleteConfirm,
                       presenting: eventToDelete,
                       actions: deleteAlertActions,
                       message: deleteAlertMessage)
                .alert("삭제 오류", isPresented: showErrorBinding) {
                    Button("확인") { deleteError = nil }
                } message: { Text(deleteError ?? "") }
        }
        .task {
            await calendarService.requestAccess()
            loadEvents()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.willEnterForegroundNotification)
        ) { _ in loadEvents() }
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
            ProgressView("불러오는 중…").frame(maxHeight: .infinity)
        } else if ktxEvents.isEmpty {
            emptyView
        } else {
            ticketList
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

    // MARK: - 카드 리스트

    private var firstUpcomingEventID: String? {
        ktxEvents
            .filter { $0.startDate >= Date() }
            .min(by: { $0.startDate < $1.startDate })?
            .eventIdentifier
    }

    private var ticketList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12, pinnedViews: [.sectionHeaders]) {
                    ForEach(groupedByMonth, id: \.0) { (month, events) in
                        Section {
                            ForEach(events, id: \.eventIdentifier) { event in
                                KTXEventRow(event: event) {
                                    eventToDelete = event
                                    showDeleteConfirm = true
                                }
                                .id(event.eventIdentifier)
                                // ── 독립 카드 스타일 ────────────────────────
                                .background(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(Color(.systemBackground))
                                        .shadow(
                                            color: (event.startDate < Date()
                                                ? Color.gray : Color.ktxBlue)
                                                .opacity(event.startDate < Date() ? 0.06 : 0.15),
                                            radius: 10, x: 0, y: 4
                                        )
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                .padding(.horizontal, 16)
                            }
                        } header: {
                            // ── 월 섹션 헤더 (스크롤 시 상단 고정) ─────────
                            HStack {
                                Text(month)
                                    .font(.system(size: 13, weight: .heavy))
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [.ktxBlue, .ktxIndigo],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .kerning(0.3)
                                Spacer()
                            }
                            .padding(.horizontal, 22)
                            .padding(.vertical, 8)
                            .background(Color.ktxBg)
                        }
                    }
                }
                .padding(.vertical, 8)
                .padding(.bottom, 16)
            }
            .refreshable { loadEvents() }
            .onChange(of: ktxEvents) {
                scrollToFirstUpcoming(proxy: proxy)
            }
        }
    }

    private func scrollToFirstUpcoming(proxy: ScrollViewProxy) {
        guard let id = firstUpcomingEventID else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation { proxy.scrollTo(id, anchor: .top) }
        }
    }

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

    // MARK: - 이벤트 로드 / 삭제

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
        switch calendarService.deleteEvent(eventIdentifier: id) {
        case .success:
            withAnimation {
                ktxEvents.removeAll {
                    $0.eventIdentifier == id || ($0.eventIdentifier ?? "") == id
                }
            }
        case .failure(let error):
            deleteError = error.localizedDescription
        }
    }

    // MARK: - 보조 뷰

    private var permissionView: some View {
        VStack(spacing: 20) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 60)).foregroundColor(.ktxBlue)
            Text("캘린더 접근 권한 필요").font(.title2).bold()
            Text("KTX 일정을 저장하고 조회하려면\n캘린더 접근 권한이 필요합니다.")
                .multilineTextAlignment(.center).foregroundColor(.secondary)
            Button("권한 허용") { Task { await calendarService.requestAccess() } }
                .buttonStyle(.borderedProminent).tint(.ktxBlue)
        }.padding()
    }

    private var accessDeniedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 60)).foregroundColor(.orange)
            Text("캘린더 접근이 거부됨").font(.title2).bold()
            Text("설정 → 개인 정보 보호 → 캘린더에서\nKTX캘린더 앱의 접근을 허용해 주세요.")
                .multilineTextAlignment(.center).foregroundColor(.secondary)
            Button("설정 열기") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }.buttonStyle(.bordered)
        }.padding()
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
                Label("공유 버튼 탭",           systemImage: "2.circle.fill")
                Label("'KTX2Cal' 선택",        systemImage: "3.circle.fill")
                Label("캘린더에 자동 추가!",    systemImage: "4.circle.fill")
            }
            .font(.caption).foregroundColor(.secondary)
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }.padding()
    }
}

// MARK: - KTX 이벤트 카드 행

struct KTXEventRow: View {
    let event: EKEvent
    let onCancel: () -> Void

    private var isPast: Bool { event.startDate < Date() }

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()
    private static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d"
        f.locale = Locale(identifier: "ko_KR")
        return f
    }()
    private static let dayFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        f.locale = Locale(identifier: "ko_KR")
        return f
    }()

    /// 이벤트 제목 파싱, \r 방어
    private var titleParts: (trainInfo: String, route: String) {
        let title = (event.title ?? "")
            .replacingOccurrences(of: "\r\n", with: "")
            .replacingOccurrences(of: "\r",   with: "")
            .replacingOccurrences(of: "\n",   with: "")
        let parts = title.components(separatedBy: " | ")
        return (parts.first ?? title, parts.last ?? "")
    }

    /// 출발역 / 도착역 분리
    private var routeParts: (dep: String, arr: String) {
        let parts = titleParts.route.components(separatedBy: "→")
        guard parts.count == 2 else { return (titleParts.route, "") }
        return (parts[0].trimmingCharacters(in: .whitespaces),
                parts[1].trimmingCharacters(in: .whitespaces))
    }

    private var accent: Color { isPast ? Color(.systemGray3) : .ktxBlue }

    // MARK: 상태 램프

    private var lampColor: Color {
        if isPast { return Color(.systemGray4) }
        let h = event.startDate.timeIntervalSinceNow / 3600
        if h <= 8  { return .red    }
        if h <= 24 { return .yellow }
        return .green
    }

    private var shouldBlink: Bool {
        guard !isPast else { return false }
        let h = event.startDate.timeIntervalSinceNow / 3600
        return h > 8 && h <= 24
    }

    @State private var lampOpacity: Double = 1.0

    var body: some View {
        HStack(alignment: .center, spacing: 0) {

            // ── 상태 램프 (halo + core) ───────────────────────
            ZStack {
                // 외부 후광 (halo)
                Circle()
                    .fill(lampColor.opacity(isPast ? 0.0 : 0.18))
                    .frame(width: 24, height: 24)
                // 내부 발광점
                Circle()
                    .fill(lampColor)
                    .frame(width: 12, height: 12)
                    .opacity(lampOpacity)
                    .shadow(color: lampColor.opacity(isPast ? 0 : 0.9), radius: 5)
            }
            .padding(.leading, 14)
            .onAppear {
                guard shouldBlink else { return }
                withAnimation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true)) {
                    lampOpacity = 0.15
                }
            }

            // ── 날짜 뱃지 ─────────────────────────────────────
            VStack(spacing: 2) {
                Text(Self.dateFmt.string(from: event.startDate))
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundColor(isPast ? .secondary : .ktxBlue)
                Text(Self.dayFmt.string(from: event.startDate))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(.tertiaryLabel))
                    .padding(.bottom, 2)
                Text(isPast ? "완료" : "예정")
                    .font(.system(size: 10, weight: .bold)).tracking(0.5)
                    .padding(.horizontal, 6).padding(.vertical, 2.5)
                    .background(isPast ? Color(.systemGray5) : Color.ktxBlue.opacity(0.12))
                    .clipShape(Capsule())
                    .foregroundColor(isPast ? Color(.systemGray2) : .ktxBlue)
            }
            .frame(width: 50)
            .padding(.leading, 10)

            // ── 점선 구분 (티켓 재단선 느낌) ─────────────────
            VStack(spacing: 4) {
                ForEach(0..<7, id: \.self) { _ in
                    Circle()
                        .fill(Color(.separator))
                        .frame(width: 2, height: 2)
                }
            }
            .padding(.horizontal, 12)

            // ── 메인 콘텐츠 ───────────────────────────────────
            VStack(alignment: .leading, spacing: 6) {

                // ① 역명 (크고 굵게)
                HStack(alignment: .firstTextBaseline) {
                    Text(routeParts.dep)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(isPast ? .secondary : .primary)
                    Spacer()
                    Text(routeParts.arr)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(isPast ? .secondary : .primary)
                }

                // ② 연결선 + 시간 (그라디언트 라인)
                HStack(spacing: 0) {
                    Text(Self.timeFmt.string(from: event.startDate))
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundColor(isPast ? .secondary : .ktxBlue)
                        .fixedSize()

                    HStack(spacing: 0) {
                        Circle()
                            .fill(accent.opacity(0.55))
                            .frame(width: 6, height: 6)
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [accent.opacity(0.45), accent.opacity(0.12)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(height: 2)
                        Image(systemName: "arrowtriangle.right.fill")
                            .font(.system(size: 6))
                            .foregroundColor(accent.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 8)

                    if let end = event.endDate {
                        Text(Self.timeFmt.string(from: end))
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .foregroundColor(isPast ? .secondary : .ktxBlue)
                            .fixedSize()
                    }
                }

                // ③ 편명 (보조, 작게)
                HStack(spacing: 4) {
                    Image(systemName: "tram.fill")
                        .font(.system(size: 10))
                        .foregroundColor(Color(.tertiaryLabel))
                    Text(titleParts.trainInfo)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(.tertiaryLabel))
                        .lineLimit(1)
                }
            }
            .padding(.vertical, 14)

            // ── 삭제 버튼 ─────────────────────────────────────
            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(isPast ? Color(.systemGray4) : Color.red.opacity(0.60))
            }
            .buttonStyle(.plain)
            .padding(.leading, 8)
            .padding(.trailing, 14)
        }
        .opacity(isPast ? 0.50 : 1.0)
        .saturation(isPast ? 0.0 : 1.0)
    }
}

#Preview {
    ContentView()
}

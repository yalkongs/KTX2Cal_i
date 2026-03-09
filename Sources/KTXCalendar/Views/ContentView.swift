import SwiftUI
import EventKit

// MARK: - Palette

private extension Color {
    static let ktxBlue = Color(red: 0.14, green: 0.42, blue: 0.96)
    static let ktxBg   = Color(red: 0.93, green: 0.94, blue: 0.98)
}

// MARK: - ContentView

struct ContentView: View {
    @StateObject private var calendarService = CalendarService()

    @State private var ktxEvents: [EKEvent] = []
    @State private var isLoading = false
    @State private var deleteError: String?
    @State private var showDeleteConfirm = false
    @State private var eventToDelete: EKEvent?

    /// 그룹핑 키: "yyyy-MM" (10월·11월도 사전순 정렬 올바름)
    private static let sectionKeyFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM"; return f
    }()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                appHeader
                Divider().opacity(0.4)
                contentArea
            }
            .background(Color.ktxBg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
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

    // MARK: - 앱 헤더 (완전 고정)

    private var appHeader: some View {
        HStack(spacing: 12) {
            // 앱 아이콘 배지
            Image(systemName: "tram.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.ktxBlue)
                )

            // 타이틀 + 건수
            VStack(alignment: .leading, spacing: 1) {
                Text("KTX 일정")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.primary)
                if !ktxEvents.isEmpty {
                    Text("승차권 \(ktxEvents.count)건")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // 새로고침
            Button { loadEvents() } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.ktxBlue)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color(.secondarySystemGroupedBackground)))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 13)
        .background(Color(.systemBackground))
    }

    // MARK: - 콘텐츠 라우팅

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

    // MARK: - 티켓 리스트

    private var firstUpcomingEventID: String? {
        ktxEvents
            .filter { $0.startDate >= Date() }
            .min(by: { $0.startDate < $1.startDate })?
            .eventIdentifier
    }

    private var ticketList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10, pinnedViews: [.sectionHeaders]) {
                    ForEach(groupedByMonth, id: \.0) { (key, events) in
                        Section {
                            ForEach(events, id: \.eventIdentifier) { event in
                                KTXEventRow(event: event) {
                                    eventToDelete = event
                                    showDeleteConfirm = true
                                }
                                .id(event.eventIdentifier)
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(Color(.systemBackground))
                                        .shadow(
                                            color: (event.startDate < Date()
                                                ? Color.gray : Color.ktxBlue)
                                                .opacity(event.startDate < Date() ? 0.05 : 0.13),
                                            radius: 9, x: 0, y: 3
                                        )
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .padding(.horizontal, 16)
                            }
                        } header: {
                            monthSectionHeader(key: key)
                        }
                    }
                }
                .padding(.vertical, 6)
                .padding(.bottom, 20)
            }
            .refreshable { loadEvents() }
            .onChange(of: ktxEvents) {
                scrollToFirstUpcoming(proxy: proxy)
            }
        }
    }

    /// "yyyy-MM" 키를 받아 "3월  2026" 형태로 표시
    @ViewBuilder
    private func monthSectionHeader(key: String) -> some View {
        let parts = key.split(separator: "-")
        let year     = parts.first.map(String.init) ?? ""
        let monthNum = parts.last.flatMap { Int($0) } ?? 0

        HStack(alignment: .lastTextBaseline, spacing: 6) {
            Text("\(monthNum)월")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.primary.opacity(0.78))
            Text(year)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 6)
        .background(Color.ktxBg)
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
            let key = Self.sectionKeyFmt.string(from: event.startDate)
            dict[key, default: []].append(event)
        }
        return dict
            .map { ($0.key, $0.value.sorted { $0.startDate < $1.startDate }) }
            .sorted { $0.0 < $1.0 }   // "2026-03" < "2026-10" ← 올바른 정렬
    }

    // MARK: - 이벤트 CRUD

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

// MARK: - KTX 이벤트 카드

struct KTXEventRow: View {
    let event: EKEvent
    let onCancel: () -> Void

    private var isPast: Bool { event.startDate < Date() }

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()
    private static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d (EEE)"
        f.locale = Locale(identifier: "ko_KR")
        return f
    }()

    /// \r 방어 + 제목 파싱
    private var titleParts: (trainInfo: String, route: String) {
        let t = (event.title ?? "")
            .replacingOccurrences(of: "\r\n", with: "")
            .replacingOccurrences(of: "\r",   with: "")
            .replacingOccurrences(of: "\n",   with: "")
        let p = t.components(separatedBy: " | ")
        return (p.first ?? t, p.last ?? "")
    }

    private var routeParts: (dep: String, arr: String) {
        let p = titleParts.route.components(separatedBy: "→")
        guard p.count == 2 else { return (titleParts.route, "") }
        return (p[0].trimmingCharacters(in: .whitespaces),
                p[1].trimmingCharacters(in: .whitespaces))
    }

    private var accent: Color { isPast ? Color(.systemGray3) : .ktxBlue }

    // MARK: 상태 램프

    private var lampColor: Color {
        if isPast { return Color(.systemGray4) }
        let h = event.startDate.timeIntervalSinceNow / 3600
        if h <= 8  { return .red    }
        if h <= 24 { return .orange }   // 주황 (노랑보다 흰 배경에서 가독성 ↑)
        return .green
    }

    private var shouldBlink: Bool {
        guard !isPast else { return false }
        let h = event.startDate.timeIntervalSinceNow / 3600
        return h > 8 && h <= 24
    }

    @State private var lampOpacity: Double = 1.0

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── ① 역명 ─────────────────────────────────────
            HStack(alignment: .center) {
                Text(routeParts.dep)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(isPast ? .secondary : .primary)
                    .minimumScaleFactor(0.75)
                    .lineLimit(1)

                Spacer()

                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(accent.opacity(0.45))
                    .padding(.horizontal, 6)

                Spacer()

                Text(routeParts.arr)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(isPast ? .secondary : .primary)
                    .minimumScaleFactor(0.75)
                    .lineLimit(1)
                    .multilineTextAlignment(.trailing)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            // ── ② 시간 + 연결선 ────────────────────────────
            HStack(spacing: 0) {
                Text(Self.timeFmt.string(from: event.startDate))
                    .font(.system(size: 18, weight: .semibold, design: .monospaced))
                    .foregroundColor(isPast ? .secondary : .ktxBlue)
                    .fixedSize()

                // 그라디언트 라인 (fade-in / fade-out)
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0), accent.opacity(0.30), accent.opacity(0)],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .frame(height: 1.5)
                    .padding(.horizontal, 10)

                if let end = event.endDate {
                    Text(Self.timeFmt.string(from: end))
                        .font(.system(size: 18, weight: .semibold, design: .monospaced))
                        .foregroundColor(isPast ? .secondary : .ktxBlue)
                        .fixedSize()
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)

            // ── ③ 하단 메타 바 ────────────────────────────
            HStack(spacing: 0) {
                // 상태 램프
                ZStack {
                    Circle()
                        .fill(lampColor.opacity(isPast ? 0 : 0.18))
                        .frame(width: 18, height: 18)
                    Circle()
                        .fill(lampColor)
                        .frame(width: 9, height: 9)
                        .opacity(lampOpacity)
                        .shadow(color: lampColor.opacity(isPast ? 0 : 0.8), radius: 3)
                }
                .padding(.trailing, 5)
                .onAppear {
                    guard shouldBlink else { return }
                    withAnimation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true)) {
                        lampOpacity = 0.15
                    }
                }

                Text(isPast ? "완료" : "예정")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isPast ? .secondary : .ktxBlue)

                metaDot

                Image(systemName: "tram.fill")
                    .font(.system(size: 10))
                    .foregroundColor(Color(.tertiaryLabel))
                    .padding(.trailing, 3)
                Text(titleParts.trainInfo)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                metaDot

                Text(Self.dateFmt.string(from: event.startDate))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                Spacer(minLength: 8)

                // 삭제 버튼
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color(.tertiaryLabel))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color(.systemGray5)))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 14)
        }
        .opacity(isPast ? 0.52 : 1.0)
        .saturation(isPast ? 0.0 : 1.0)
    }

    private var metaDot: some View {
        Circle()
            .fill(Color(.systemGray4))
            .frame(width: 3, height: 3)
            .padding(.horizontal, 6)
    }
}

#Preview {
    ContentView()
}

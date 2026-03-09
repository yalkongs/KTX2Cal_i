import SwiftUI
import EventKit

// MARK: - Palette (아이콘 색상 기반)

private extension Color {
    /// 아이콘 네이비  #003060
    static let ktxNavy    = Color(red: 0.08, green: 0.22, blue: 0.42)
    /// 아이콘 스카이블루  #3090d8
    static let ktxSky     = Color(red: 0.19, green: 0.56, blue: 0.85)
    /// 아이콘 오렌지  #f07800
    static let ktxOrange  = Color(red: 0.94, green: 0.47, blue: 0.00)
    /// 앱 배경 (시스템 적응)
    static let ktxBg      = Color(red: 0.93, green: 0.94, blue: 0.98)
    /// 카드 우측 배경 (다크모드에서도 밝게 유지)
    static let ktxCardBg  = Color(red: 0.96, green: 0.97, blue: 1.00)
}

// MARK: - ContentView

struct ContentView: View {
    @StateObject private var calendarService = CalendarService()

    @State private var ktxEvents:        [EKEvent] = []
    @State private var isLoading         = false
    @State private var deleteError:      String?
    @State private var showDeleteConfirm = false
    @State private var eventToDelete:    EKEvent?

    /// 그룹핑 키: "yyyy-MM" → 사전 정렬 시 10·11·12월도 올바름
    private static let sectionKeyFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM"; return f
    }()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                appHeader
                Divider().opacity(0.35)
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

    // MARK: - 앱 헤더

    private var appHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "tram.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.ktxNavy)
                )

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

            Button { loadEvents() } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.ktxNavy)
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
                LazyVStack(spacing: 12, pinnedViews: [.sectionHeaders]) {
                    ForEach(groupedByMonth, id: \.0) { (key, events) in
                        Section {
                            ForEach(events, id: \.eventIdentifier) { event in
                                KTXEventRow(event: event) {
                                    eventToDelete = event
                                    showDeleteConfirm = true
                                }
                                .id(event.eventIdentifier)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .shadow(
                                    color: Color.ktxNavy.opacity(event.startDate < Date() ? 0.05 : 0.14),
                                    radius: 8, x: 0, y: 3
                                )
                                .padding(.horizontal, 16)
                            }
                        } header: {
                            monthHeader(key: key)
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

    @ViewBuilder
    private func monthHeader(key: String) -> some View {
        let parts    = key.split(separator: "-")
        let year     = parts.first.map(String.init) ?? ""
        let monthNum = parts.last.flatMap { Int($0) } ?? 0

        HStack(alignment: .lastTextBaseline, spacing: 5) {
            Text("\(monthNum)월")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.primary.opacity(0.75))
            Text(year)
                .font(.system(size: 12))
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
            .sorted { $0.0 < $1.0 }
    }

    // MARK: - CRUD

    private func loadEvents() {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let events = calendarService.fetchKTXEvents()
            DispatchQueue.main.async {
                self.ktxEvents = events
                self.isLoading = false
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
                .font(.system(size: 60)).foregroundColor(.ktxNavy)
            Text("캘린더 접근 권한 필요").font(.title2).bold()
            Text("KTX 일정을 저장하고 조회하려면\n캘린더 접근 권한이 필요합니다.")
                .multilineTextAlignment(.center).foregroundColor(.secondary)
            Button("권한 허용") { Task { await calendarService.requestAccess() } }
                .buttonStyle(.borderedProminent).tint(.ktxNavy)
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
    let event:    EKEvent
    let onCancel: () -> Void

    private var isPast: Bool { event.startDate < Date() }

    // MARK: Formatters
    private static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()
    private static let monthFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "M월"
        f.locale = Locale(identifier: "ko_KR"); return f
    }()
    private static let dayNumFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "d"; return f
    }()
    private static let dowFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEEEE"   // 최단형: 일·월·화…
        f.locale = Locale(identifier: "ko_KR"); return f
    }()

    // MARK: 제목 파싱 (\r 방어)
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

    // MARK: 상태 램프
    private var lampColor: Color {
        if isPast { return Color(.systemGray4) }
        let h = event.startDate.timeIntervalSinceNow / 3600
        if h <= 8  { return .red         }
        if h <= 24 { return .ktxOrange   }
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
        HStack(spacing: 0) {

            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            // 좌측 컬럼 — 네이비 배경
            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            VStack(spacing: 0) {

                Spacer()

                // 상태 램프
                ZStack {
                    Circle()
                        .fill(lampColor.opacity(isPast ? 0 : 0.30))
                        .frame(width: 20, height: 20)
                    Circle()
                        .fill(lampColor)
                        .frame(width: 11, height: 11)
                        .opacity(lampOpacity)
                        .shadow(color: lampColor.opacity(isPast ? 0 : 1.0), radius: 4)
                }
                .onAppear {
                    guard shouldBlink else { return }
                    withAnimation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true)) {
                        lampOpacity = 0.15
                    }
                }

                Spacer().frame(height: 10)

                // 월 (작게)
                Text(Self.monthFmt.string(from: event.startDate))
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(.white.opacity(0.65))

                // 일 (크게, dominant)
                Text(Self.dayNumFmt.string(from: event.startDate))
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)

                // 요일 (한 글자)
                Text(Self.dowFmt.string(from: event.startDate))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.80))

                Spacer().frame(height: 12)

                // 예정 / 완료 뱃지
                Text(isPast ? "완료" : "예정")
                    .font(.system(size: 10, weight: .bold)).tracking(0.5)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(isPast
                                  ? Color.white.opacity(0.18)
                                  : Color.ktxOrange.opacity(0.88))
                    )
                    .foregroundColor(.white)

                Spacer()
            }
            .frame(width: 66)
            .background(isPast ? Color(red: 0.38, green: 0.40, blue: 0.45) : Color.ktxNavy)

            // 좌우 경계선
            Rectangle()
                .fill(Color.white.opacity(0.22))
                .frame(width: 0.5)

            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            // 우측 컬럼 — 밝은 카드 배경
            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            VStack(alignment: .leading, spacing: 0) {

                // ① 역명
                HStack(alignment: .center) {
                    Text(routeParts.dep)
                        .font(.system(size: 23, weight: .bold))
                        .foregroundColor(isPast ? .secondary : .primary)
                        .minimumScaleFactor(0.75)
                        .lineLimit(1)

                    Spacer()

                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color.ktxSky.opacity(0.55))
                        .padding(.horizontal, 4)

                    Spacer()

                    Text(routeParts.arr)
                        .font(.system(size: 23, weight: .bold))
                        .foregroundColor(isPast ? .secondary : .primary)
                        .minimumScaleFactor(0.75)
                        .lineLimit(1)
                        .multilineTextAlignment(.trailing)
                }
                .padding(.top, 16)

                // ② 시간 + 오렌지 연결선
                HStack(spacing: 0) {
                    Text(Self.timeFmt.string(from: event.startDate))
                        .font(.system(size: 17, weight: .semibold, design: .monospaced))
                        .foregroundColor(isPast ? .secondary : .ktxNavy)
                        .fixedSize()

                    // 아이콘 오렌지 그라디언트 라인
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: isPast
                                    ? [Color.secondary.opacity(0.2), Color.secondary.opacity(0.05)]
                                    : [Color.ktxOrange.opacity(0.70), Color.ktxOrange.opacity(0.12)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(height: 2)
                        .padding(.horizontal, 8)

                    if let end = event.endDate {
                        Text(Self.timeFmt.string(from: end))
                            .font(.system(size: 17, weight: .semibold, design: .monospaced))
                            .foregroundColor(isPast ? .secondary : .ktxNavy)
                            .fixedSize()
                    }
                }
                .padding(.top, 10)

                // ③ 편명 + 삭제 버튼
                HStack(spacing: 4) {
                    Image(systemName: "tram.fill")
                        .font(.system(size: 10))
                        .foregroundColor(Color(.tertiaryLabel))
                    Text(titleParts.trainInfo)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Button(action: onCancel) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Color(.tertiaryLabel))
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(Color(.systemGray5)))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 10)
                .padding(.bottom, 14)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .background(Color.ktxCardBg)
        }
        .opacity(isPast ? 0.60 : 1.0)
        .saturation(isPast ? 0.15 : 1.0)
    }
}

#Preview {
    ContentView()
}

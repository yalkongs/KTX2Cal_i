import SwiftUI

/// Share Extension 내에서 표시되는 승차권 확인 UI
struct ShareTicketView: View {
    @State var ticket: KTXTicket
    @ObservedObject var calendarService: CalendarService
    let onComplete: (KTXTicket) -> Void
    let onCancel: () -> Void

    @State private var isAdding     = false
    @State private var addResult: AddResult?

    enum AddResult { case success, failure(String), duplicate }

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()
    private static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy년 M월 d일 (E)"
        f.locale = Locale(identifier: "ko_KR")
        return f
    }()

    var body: some View {
        NavigationStack {
            Form {
                // ── 승차권 요약 카드 ──────────────────────────
                Section {
                    VStack(spacing: 12) {
                        // 열차 타입 배지
                        HStack {
                            Text(ticket.trainType)
                                .font(.caption).bold()
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(6)
                            Text("\(ticket.trainNumber)호")
                                .font(.headline)
                            Spacer()
                            if !ticket.ticketClass.isEmpty {
                                Text(ticket.ticketClass)
                                    .font(.caption).foregroundColor(.secondary)
                            }
                        }

                        // 출발 → 도착
                        HStack(alignment: .top) {
                            VStack(spacing: 2) {
                                Text(ticket.departureStation)
                                    .font(.title3).bold()
                                Text(Self.timeFmt.string(from: ticket.departureDate))
                                    .font(.title2).foregroundColor(.blue)
                            }
                            .frame(maxWidth: .infinity)

                            Image(systemName: "arrow.right")
                                .foregroundColor(.secondary)
                                .padding(.top, 6)

                            VStack(spacing: 2) {
                                Text(ticket.arrivalStation)
                                    .font(.title3).bold()
                                Text(Self.timeFmt.string(from: ticket.arrivalDate))
                                    .font(.title2).foregroundColor(.blue)
                            }
                            .frame(maxWidth: .infinity)
                        }

                        Text(Self.dateFmt.string(from: ticket.departureDate))
                            .font(.caption).foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                // ── 좌석 정보 (있을 때만) ──────────────────────
                if !ticket.carNumber.isEmpty || !ticket.seatNumber.isEmpty {
                    Section("좌석") {
                        HStack {
                            Label("호차", systemImage: "rectangle.split.3x1")
                            Spacer()
                            TextField("호차", text: $ticket.carNumber)
                                .multilineTextAlignment(.trailing)
                        }
                        HStack {
                            Label("좌석번호", systemImage: "chair")
                            Spacer()
                            TextField("좌석", text: $ticket.seatNumber)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }

                // ── 날짜/시간 수정 ────────────────────────────
                Section("시간 확인/수정") {
                    DatePicker("출발", selection: $ticket.departureDate,
                               displayedComponents: [.date, .hourAndMinute])
                    DatePicker("도착", selection: $ticket.arrivalDate,
                               displayedComponents: [.date, .hourAndMinute])
                }

                // ── 캘린더 선택 ───────────────────────────────
                if !calendarService.availableCalendars.isEmpty {
                    Section("캘린더") {
                        ForEach(calendarService.availableCalendars,
                                id: \.calendarIdentifier) { cal in
                            HStack {
                                Circle()
                                    .fill(Color(cgColor: cal.cgColor))
                                    .frame(width: 10, height: 10)
                                Text(cal.title)
                                Spacer()
                                if calendarService.selectedCalendar?.calendarIdentifier == cal.calendarIdentifier {
                                    Image(systemName: "checkmark").foregroundColor(.blue)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { calendarService.selectedCalendar = cal }
                        }
                    }
                }

                // ── 원본 공유 텍스트 (접어두기) ──────────────
                if !ticket.rawSharedText.isEmpty {
                    Section {
                        DisclosureGroup("원본 공유 텍스트") {
                            Text(ticket.rawSharedText)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("캘린더에 추가")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        addToCalendar()
                    } label: {
                        if isAdding {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Text("추가").bold()
                        }
                    }
                    .disabled(isAdding)
                }
            }
            .overlay { resultOverlay }
        }
        .task { await calendarService.requestAccess() }
    }

    // MARK: - 결과 오버레이

    @ViewBuilder
    private var resultOverlay: some View {
        if let result = addResult {
            ZStack {
                Color.black.opacity(0.45).ignoresSafeArea()
                VStack(spacing: 20) {
                    switch result {
                    case .success:
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 52)).foregroundColor(.green)
                        Text("캘린더에 추가됐습니다!")
                            .font(.title3).bold()
                        Text("\(ticket.departureStation) → \(ticket.arrivalStation)\n\(ticket.trainType) \(ticket.trainNumber)호 · \(Self.timeFmt.string(from: ticket.departureDate)) 출발")
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                        Button("완료") { onComplete(ticket) }
                            .buttonStyle(.borderedProminent)

                    case .failure(let msg):
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 52)).foregroundColor(.red)
                        Text("추가 실패").font(.title3).bold()
                        Text(msg).multilineTextAlignment(.center).foregroundColor(.secondary)
                        Button("닫기") { addResult = nil }.buttonStyle(.bordered)

                    case .duplicate:
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 52)).foregroundColor(.orange)
                        Text("이미 등록된 일정").font(.title3).bold()
                        Text("동일한 일정이 이미 존재합니다.")
                            .foregroundColor(.secondary)
                        HStack(spacing: 12) {
                            Button("취소") { addResult = nil }.buttonStyle(.bordered)
                            Button("그래도 추가") { addResult = nil; forceAdd() }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                }
                .padding(32)
                .background(.regularMaterial)
                .cornerRadius(24)
                .padding(.horizontal, 28)
            }
        }
    }

    // MARK: - 로직

    private func addToCalendar() {
        if calendarService.isDuplicate(ticket: ticket) {
            addResult = .duplicate; return
        }
        forceAdd()
    }

    private func forceAdd() {
        isAdding = true
        Task {
            let result = await calendarService.addEvent(ticket: ticket)
            await MainActor.run {
                isAdding = false
                switch result {
                case .success:    addResult = .success
                case .failure(let e): addResult = .failure(e.localizedDescription)
                }
            }
        }
    }
}

import UIKit
import SwiftUI
import UniformTypeIdentifiers

/// KTX 앱 공유 시트에서 호출되는 Share Extension 진입점
class ShareViewController: UIViewController {

    private let parser         = KTXParser()
    private let ocrService     = OCRService()
    private let calendarService = CalendarService()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        extractSharedContent()
    }

    // MARK: - 공유 데이터 추출

    private func extractSharedContent() {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            showError("공유 데이터를 가져올 수 없습니다.")
            return
        }

        var sharedText: String?
        var sharedImage: UIImage?
        let group = DispatchGroup()

        for item in items {
            for provider in (item.attachments ?? []) {

                // ① 텍스트 수신
                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    group.enter()
                    provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { data, _ in
                        if let text = data as? String { sharedText = text }
                        else if let data = data as? Data { sharedText = String(data: data, encoding: .utf8) }
                        group.leave()
                    }
                }

                // ② 이미지 수신
                if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    group.enter()
                    provider.loadItem(forTypeIdentifier: UTType.image.identifier) { data, _ in
                        if let image = data as? UIImage { sharedImage = image }
                        else if let url = data as? URL, let img = UIImage(contentsOfFile: url.path) {
                            sharedImage = img
                        } else if let data = data as? Data {
                            sharedImage = UIImage(data: data)
                        }
                        group.leave()
                    }
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            self?.processSharedContent(text: sharedText, image: sharedImage)
        }
    }

    // MARK: - 콘텐츠 처리

    private func processSharedContent(text: String?, image: UIImage?) {
        // ① 텍스트로 먼저 파싱 시도
        if let text = text, !text.isEmpty {
            print("📨 공유 텍스트:\n\(text)")
            if let ticket = parser.parseSharedText(text) {
                showTicketUI(ticket: ticket)
                return
            }
        }

        // ② 이미지가 있으면 OCR fallback
        if let image = image {
            showLoadingUI()
            ocrService.recognizeText(from: image) { [weak self] result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let lines):
                        let raw = lines.joined(separator: "\n")
                        if let ticket = self?.parser.parse(lines: lines, rawText: raw) {
                            self?.showTicketUI(ticket: ticket)
                        } else {
                            self?.showError("이미지에서 승차권 정보를 인식하지 못했습니다.\n이미지가 명확한지 확인해 주세요.")
                        }
                    case .failure(let error):
                        self?.showError("텍스트 인식 오류: \(error.localizedDescription)")
                    }
                }
            }
            return
        }

        showError("KTX 앱에서 승차권 정보를 공유해 주세요.")
    }

    // MARK: - UI 표시

    private func showTicketUI(ticket: KTXTicket) {
        let hostingVC = UIHostingController(
            rootView: ShareTicketView(
                ticket: ticket,
                calendarService: calendarService,
                onComplete: { [weak self] savedTicket in
                    // App Group에 저장
                    TicketStore.shared.save(savedTicket)
                    self?.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
                },
                onCancel: { [weak self] in
                    self?.extensionContext?.cancelRequest(
                        withError: NSError(domain: "KTXCalendar", code: 0,
                                          userInfo: [NSLocalizedDescriptionKey: "사용자가 취소했습니다."])
                    )
                }
            )
        )
        hostingVC.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(hostingVC)
        view.addSubview(hostingVC.view)
        NSLayoutConstraint.activate([
            hostingVC.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingVC.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hostingVC.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingVC.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        hostingVC.didMove(toParent: self)
    }

    private func showLoadingUI() {
        let spinner = UIActivityIndicatorView(style: .large)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimating()
        view.addSubview(spinner)
        let label = UILabel()
        label.text = "승차권 정보 인식 중..."
        label.font = .systemFont(ofSize: 15)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -20),
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 12)
        ])
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(title: "인식 실패", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "닫기", style: .cancel) { [weak self] _ in
            self?.extensionContext?.cancelRequest(
                withError: NSError(domain: "KTXCalendar", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: message])
            )
        })
        present(alert, animated: true)
    }
}

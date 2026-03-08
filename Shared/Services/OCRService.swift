import Vision
import UIKit

/// Vision 프레임워크로 이미지에서 텍스트 추출
class OCRService {

    /// 이미지에서 텍스트 인식 후 완료 핸들러 호출
    func recognizeText(from image: UIImage, completion: @escaping (Result<[String], Error>) -> Void) {
        guard let cgImage = image.cgImage else {
            completion(.failure(OCRError.invalidImage))
            return
        }

        let request = VNRecognizeTextRequest { request, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                completion(.success([]))
                return
            }

            // 신뢰도 높은 순서로 텍스트 추출, 위→아래 순 정렬
            let lines = observations
                .compactMap { $0.topCandidates(1).first }
                .sorted { $0.confidence > $1.confidence }
                .map { $0.string }

            // Y좌표 기준으로 정렬 (위에서 아래)
            let sortedLines = observations
                .sorted { $0.boundingBox.minY > $1.boundingBox.minY }  // Vision 좌표계는 하단이 0
                .compactMap { $0.topCandidates(1).first?.string }

            completion(.success(sortedLines))
        }

        // 한국어 우선, 영어 포함
        request.recognitionLanguages = ["ko-KR", "en-US"]
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.minimumTextHeight = 0.015  // 작은 텍스트도 인식

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                completion(.failure(error))
            }
        }
    }

    enum OCRError: LocalizedError {
        case invalidImage

        var errorDescription: String? {
            switch self {
            case .invalidImage:
                return "이미지를 처리할 수 없습니다."
            }
        }
    }
}

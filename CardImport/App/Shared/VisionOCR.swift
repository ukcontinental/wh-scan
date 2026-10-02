import Foundation
import Vision
import UIKit
import CardCore

/// On-device OCR (free, private). Its transcript is an independent second reading that the
/// pipeline uses to cross-check every value the AI model returns.
struct VisionOCR: OCRProvider {
    func recognize(_ image: ImagePayload) async throws -> OCRResult {
        guard let cg = UIImage(data: image.data)?.cgImage else { return OCRResult(engine: "vision", lines: []) }
        return try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                request.recognitionLanguages = ["zh-Hant", "zh-Hans", "en-US"]
                let handler = VNImageRequestHandler(cgImage: cg, orientation: .up)
                do {
                    try handler.perform([request])
                    let observations = request.results ?? []
                    let lines: [OCRLine] = observations.compactMap { obs in
                        guard let top = obs.topCandidates(1).first else { return nil }
                        let bb = obs.boundingBox   // normalised, origin bottom-left
                        return OCRLine(text: top.string, confidence: Double(top.confidence),
                                       box: [bb.origin.x, 1 - bb.origin.y - bb.height, bb.width, bb.height])
                    }
                    // Reading order: top to bottom, then left to right.
                    let sorted = lines.sorted { a, b in
                        let ay = a.box?[1] ?? 0, by = b.box?[1] ?? 0
                        if abs(ay - by) > 0.02 { return ay < by }
                        return (a.box?[0] ?? 0) < (b.box?[0] ?? 0)
                    }
                    cont.resume(returning: OCRResult(engine: "apple-vision", lines: sorted))
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }
}

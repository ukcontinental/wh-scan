import Foundation
import UIKit
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import CardCore

/// Turns a photo (HEIC/JPEG from Photos or the camera) into what the pipeline needs:
/// an upright, card-cropped, size-limited JPEG, the capture time (EXIF) and a colour signature.
enum ImagePreparer {
    struct Prepared {
        var jpeg: Data
        var captureDate: Date?
        var visual: VisualSignature?
    }

    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    static func prepare(_ data: Data, maxLongEdge: CGFloat = 2000) -> Prepared? {
        let date = captureDate(from: data)
        // Decode straight to a ≤2400 px upright bitmap (never the full 24–48 MP original).
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let thumb = CGImageSourceCreateThumbnailAtIndex(src, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: 2400,
              ] as CFDictionary) else { return nil }
        var image = CIImage(cgImage: thumb)
        var aspect: Double? = nil
        if let cropped = cropToCard(image) {
            image = cropped
            let e = cropped.extent
            aspect = Double(max(e.width, e.height) / max(1, min(e.width, e.height)))
        }
        let longEdge = max(image.extent.width, image.extent.height)
        if longEdge > maxLongEdge {
            let scale = maxLongEdge / longEdge
            let f = CIFilter.lanczosScaleTransform()
            f.inputImage = image
            f.scale = Float(scale)
            f.aspectRatio = 1
            if let out = f.outputImage { image = out }
        }
        image = image.transformed(by: CGAffineTransform(translationX: -image.extent.origin.x, y: -image.extent.origin.y))
        guard let cg = context.createCGImage(image, from: image.extent) else { return nil }
        guard let jpeg = UIImage(cgImage: cg).jpegData(compressionQuality: 0.85) else { return nil }
        return Prepared(jpeg: jpeg, captureDate: date, visual: signature(cg, aspect: aspect))
    }

    /// EXIF DateTimeOriginal (+ OffsetTimeOriginal). Reading metadata from the image data needs no Photos permission.
    static func captureDate(from data: Data) -> Date? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any],
              let original = exif[kCGImagePropertyExifDateTimeOriginal] as? String else { return nil }
        let offset = exif["OffsetTimeOriginal" as CFString] as? String
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        if let offset {
            f.dateFormat = "yyyy:MM:dd HH:mm:ssZZZZZ"
            if let d = f.date(from: original + offset) { return d }
        }
        f.dateFormat = "yyyy:MM:dd HH:mm:ss"
        f.timeZone = .current
        return f.date(from: original)
    }

    /// Detects the card and corrects perspective. Falls back to the full photo when unsure,
    /// so a bad crop can never cut text off.
    static func cropToCard(_ image: CIImage) -> CIImage? {
        let request = VNDetectDocumentSegmentationRequest()
        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        guard (try? handler.perform([request])) != nil,
              let obs = request.results?.first, obs.confidence >= 0.8 else { return nil }
        let w = image.extent.width, h = image.extent.height
        func pt(_ p: CGPoint) -> CGPoint { CGPoint(x: image.extent.origin.x + p.x * w, y: image.extent.origin.y + p.y * h) }
        let quadArea = abs((obs.topRight.x - obs.bottomLeft.x) * (obs.topLeft.y - obs.bottomRight.y))
        guard quadArea >= 0.2 else { return nil }
        let f = CIFilter.perspectiveCorrection()
        f.inputImage = image
        f.topLeft = pt(obs.topLeft); f.topRight = pt(obs.topRight)
        f.bottomLeft = pt(obs.bottomLeft); f.bottomRight = pt(obs.bottomRight)
        guard let out = f.outputImage, out.extent.width > 200, out.extent.height > 120 else { return nil }
        return out
    }

    /// 12 hue buckets (weighted by saturation) + 3 grey buckets, L1-normalised.
    static func signature(_ cg: CGImage, aspect: Double?) -> VisualSignature? {
        let size = 32
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        guard let ctx = CGContext(data: &pixels, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: size, height: size))
        var hist = [Double](repeating: 0, count: 15)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let r = Double(pixels[i]) / 255, g = Double(pixels[i + 1]) / 255, b = Double(pixels[i + 2]) / 255
            let mx = max(r, g, b), mn = min(r, g, b), delta = mx - mn
            let sat = mx == 0 ? 0 : delta / mx
            if sat < 0.18 {
                hist[12 + (mx < 0.33 ? 0 : (mx < 0.7 ? 1 : 2))] += 1
                continue
            }
            var hue: Double
            if mx == r { hue = (g - b) / delta } else if mx == g { hue = 2 + (b - r) / delta } else { hue = 4 + (r - g) / delta }
            hue = (hue * 60).truncatingRemainder(dividingBy: 360)
            if hue < 0 { hue += 360 }
            hist[min(11, Int(hue / 30))] += sat
        }
        let total = hist.reduce(0, +)
        guard total > 0 else { return nil }
        return VisualSignature(colorHistogram: hist.map { $0 / total }, aspectRatio: aspect)
    }
}

/// Temporary image files in the App Group container.
struct TempImageStore: ImageStore {
    func url(_ id: String) -> URL { AppGroup.imagesDir.appendingPathComponent(id + ".jpg") }

    func save(_ data: Data, id: String) throws { try data.write(to: url(id), options: .atomic) }

    func load(_ photoID: String) async throws -> ImagePayload {
        ImagePayload(data: try Data(contentsOf: url(photoID)), mediaType: "image/jpeg")
    }

    func delete(_ photoID: String) async { try? FileManager.default.removeItem(at: url(photoID)) }

    func image(_ id: String) -> UIImage? { UIImage(contentsOfFile: url(id).path) }
}

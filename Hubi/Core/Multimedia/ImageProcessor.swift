import Foundation
import UIKit

enum ImageProcessor {
    /// 把 UIImage 压缩到 base64 (JPEG)，maxBytes 默认 4MB（OpenAI vision 单图限制）
    static func toBase64(_ image: UIImage, maxBytes: Int = 4 * 1024 * 1024) -> (mime: String, b64: String)? {
        var quality: CGFloat = 0.85
        var data = image.jpegData(compressionQuality: quality)
        while let d = data, d.count > maxBytes, quality > 0.2 {
            quality -= 0.15
            data = image.jpegData(compressionQuality: quality)
        }
        guard let final = data else { return nil }
        return ("image/jpeg", final.base64EncodedString())
    }

    /// 缩放，使最长边不超过 maxDim（典型 1024 节省 token）
    static func resized(_ image: UIImage, maxDim: CGFloat = 1024) -> UIImage {
        let w = image.size.width, h = image.size.height
        let m = max(w, h)
        guard m > maxDim else { return image }
        let scale = maxDim / m
        let size = CGSize(width: w * scale, height: h * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }
}

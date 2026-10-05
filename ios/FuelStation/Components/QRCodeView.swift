import SwiftUI
import CoreImage.CIFilterBuiltins

enum CodeImage {
    private static let context = CIContext()

    static func qr(_ text: String) -> UIImage? {
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(text.utf8)
        f.correctionLevel = "M"
        return render(f.outputImage, scale: 12)
    }

    static func barcode(_ text: String) -> UIImage? {
        let f = CIFilter.code128BarcodeGenerator()
        f.message = Data(text.utf8)
        f.quietSpace = 4
        return render(f.outputImage, scale: 4)
    }

    private static func render(_ image: CIImage?, scale: CGFloat) -> UIImage? {
        guard let image = image?.transformed(by: CGAffineTransform(scaleX: scale, y: scale)),
              let cg = context.createCGImage(image, from: image.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

struct QRCodeView: View {
    let text: String
    var body: some View {
        if let img = CodeImage.qr(text) {
            Image(uiImage: img).interpolation(.none).resizable().scaledToFit()
        } else {
            Image(systemName: "qrcode").resizable().scaledToFit()
        }
    }
}

struct BarcodeView: View {
    let text: String
    var body: some View {
        if let img = CodeImage.barcode(text) {
            Image(uiImage: img).interpolation(.none).resizable()
        }
    }
}

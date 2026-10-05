import SwiftUI
import AVFoundation

/// Camera QR/barcode scanner (AVFoundation — works on every iPhone, no paid SDK).
struct QRScannerView: UIViewControllerRepresentable {
    var onCode: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerController {
        let vc = ScannerController()
        vc.onCode = onCode
        return vc
    }

    func updateUIViewController(_ vc: ScannerController, context: Context) {}

    final class ScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
        var onCode: ((String) -> Void)?
        private let session = AVCaptureSession()
        private var preview: AVCaptureVideoPreviewLayer?
        private var lastCode: String?
        private var lastTime = Date.distantPast

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard granted else { return }
                DispatchQueue.main.async { self?.configure() }
            }
        }

        private func configure() {
            guard let device = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else { return }
            session.addInput(input)
            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else { return }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.qr, .code128].filter { output.availableMetadataObjectTypes.contains($0) }
            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspectFill
            layer.frame = view.bounds
            view.layer.addSublayer(layer)
            preview = layer
            DispatchQueue.global(qos: .userInitiated).async { [session] in session.startRunning() }
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            preview?.frame = view.bounds
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            DispatchQueue.global(qos: .userInitiated).async { [session] in session.stopRunning() }
        }

        nonisolated func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection) {
            guard let code = (objects.first as? AVMetadataMachineReadableCodeObject)?.stringValue else { return }
            // Delegate queue is .main (set in configure), so we're already on the main actor.
            MainActor.assumeIsolated { handle(code) }
        }

        private func handle(_ code: String) {
            // Debounce repeated reads of the same code.
            if code == lastCode, Date().timeIntervalSince(lastTime) < 3 { return }
            lastCode = code
            lastTime = Date()
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onCode?(code)
        }
    }
}

/// Scanner with a framed viewfinder overlay and a manual-entry fallback.
struct ScanSheet: View {
    let title: String
    var manualPlaceholder = "Card number or mobile"
    var onCode: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var manual = ""

    var body: some View {
        NavigationStack {
            ZStack {
                QRScannerView { code in
                    onCode(code)
                    dismiss()
                }
                .ignoresSafeArea()
                RoundedRectangle(cornerRadius: 28).strokeBorder(.white, lineWidth: 4).frame(width: 260, height: 260)
                    .shadow(color: Theme.brand, radius: 12)
                VStack {
                    Spacer()
                    HStack {
                        TextField(manualPlaceholder, text: $manual)
                            .textInputAutocapitalization(.characters)
                            .padding(14)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                        Button("Go") { onCode(manual); dismiss() }
                            .buttonStyle(SecondaryButtonStyle())
                            .disabled(manual.count < 4)
                    }
                    .padding()
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }
}

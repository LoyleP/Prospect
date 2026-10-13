// Views/Components/QRScannerView.swift
// Camera view that reports the first QR code it sees. On a device without a camera (the simulator) it
// says so, and the caller offers pasting the invitation instead.
import AVFoundation
import SwiftUI

struct QRScannerView: UIViewControllerRepresentable {
    var onCode: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerController {
        let c = ScannerController()
        c.onCode = onCode
        return c
    }

    func updateUIViewController(_ controller: ScannerController, context: Context) {}
}

final class ScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: (String) -> Void = { _ in }
    private let session = AVCaptureSession()
    private var preview: AVCaptureVideoPreviewLayer?
    private var found = false
    private let message = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        message.textColor = .white
        message.textAlignment = .center
        message.numberOfLines = 0
        message.font = .preferredFont(forTextStyle: .body)
        message.isHidden = true
        view.addSubview(message)

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: configure()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { ok in
                DispatchQueue.main.async { ok ? self.configure() : self.show(L("Allow camera access in Settings to scan the invitation.")) }
            }
        default: show(L("Allow camera access in Settings to scan the invitation."))
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preview?.frame = view.bounds
        message.frame = view.bounds.insetBy(dx: 32, dy: 0)
    }

    deinit { if session.isRunning { session.stopRunning() } }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if session.isRunning { session.stopRunning() }
    }

    private func show(_ text: String) {
        message.text = text
        message.isHidden = false
    }

    private func configure() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else {
            show(L("Camera unavailable on this device."))
            return
        }
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.insertSublayer(layer, at: 0)
        preview = layer
        DispatchQueue.global(qos: .userInitiated).async { self.session.startRunning() }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !found, let code = (objects.first as? AVMetadataMachineReadableCodeObject)?.stringValue else { return }
        found = true
        onCode(code)
        // A wrong code must not freeze the camera: allow scanning again shortly after.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.found = false }
    }
}

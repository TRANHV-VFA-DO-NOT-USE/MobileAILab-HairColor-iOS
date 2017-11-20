import UIKit
import AVFoundation

// Conveniece container for AVCaptureVideoPreviewLayer.
// Handles device rotaion and layer layout
class CameraPreviewView: UIView {

    override func awakeFromNib() {
        super.awakeFromNib()
        // Observe device rotation
        let selector = #selector(deviceOrientationDidChange(_:))
        UIDevice.subscribeToDeviceOrientationNotifications(self, selector: selector)
    }

    /// Insert layer at index 0
    func addCaptureVideoPreviewLayer(_ previewLayer: AVCaptureVideoPreviewLayer) {
        self.previewLayer?.removeFromSuperlayer()
        self.layer.insertSublayer(previewLayer, at: 0)
        self.previewLayer = previewLayer
        self.previewLayer?.videoGravity = .resizeAspectFill
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }

    /// Change video orientation to always display video in correct orientation
    @objc private func deviceOrientationDidChange(_ notification: Notification) {
        previewLayer?.connection?.videoOrientation = UIDevice.current.videoOrientation
    }

    private weak var previewLayer: AVCaptureVideoPreviewLayer?
}


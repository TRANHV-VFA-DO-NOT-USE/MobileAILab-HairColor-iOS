import UIKit
import AVFoundation
import Vision
import CoreML

class ViewController: UIViewController {
    
    @IBOutlet weak var cameraPreview: CameraPreviewView!
    @IBOutlet weak var predictionView: UIImageView!
    
    private var session: AVCaptureSession?
    
    lazy var predictionRequest: VNCoreMLRequest = {
        // Load the ML model through its generated class and create a Vision request for it.
        do {
            let model = try VNCoreMLModel(for: mu_224_050_best2().model)
            let request = VNCoreMLRequest(model: model, completionHandler: self.handlePrediction)
            request.imageCropAndScaleOption = VNImageCropAndScaleOption.centerCrop
            return request
        } catch {
            fatalError("can't load Vision ML model: \(error)")
        }
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        predictionView.transform = CGAffineTransform(scaleX: -1, y: 1)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        AVCaptureDevice.requestAuthorization { [weak self] (granted) in
            self?.permissions(granted)
        }
        session?.startRunning()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        session?.stopRunning()
    }
    
    private func permissions(_ granted: Bool) {
        if granted && session == nil {
            setupSession()
        }
    }
    
    private func setupSession() {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: AVMediaType.video, position: .front) else {
            fatalError("Capture device not available")
        }
        guard let input = try? AVCaptureDeviceInput(device: device) else {
            fatalError("Capture input not available")
        }
        let output = AVCaptureVideoDataOutput()
        output.setSampleBufferDelegate(self, queue: DispatchQueue.global(qos: .userInteractive))
        
        let session = AVCaptureSession()
        session.addInput(input)
        session.addOutput(output)
        
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        cameraPreview.addCaptureVideoPreviewLayer(previewLayer)
        
        self.session = session
        session.startRunning()
    }
    
    /// Update orientation for AVCaptureConnection so that CVImageBuffer pixels
    /// are rotated correctly in captureOutput(_:didOutput:from:)
    /// - Note: Even though rotation of pixel buffer is hardware accelerated,
    /// this is not the most effecient way of handling it. I was not able to test
    /// getting exif rotation based on device rotation, hence rotating the buffer
    /// I will update it in a near future
    @objc private func deviceOrientationDidChange(_ notification: Notification) {
        session?.outputs.forEach {
            $0.connections.forEach {
                $0.videoOrientation = UIDevice.current.videoOrientation
            }
        }
    }
    
    private func handlePrediction(request: VNRequest, error: Error?) {
        guard let observations = request.results as? [VNCoreMLFeatureValueObservation] else {
            fatalError("unexpected result type from VNCoreMLRequest")
        }
        if let multiArray: MLMultiArray = observations[0].featureValue.multiArrayValue {
            let image = maskToRGBA(maskArray: MultiArray<Double>(multiArray), rgba: (255, 255, 0, 100))
            DispatchQueue.main.async { [weak self] in
                self?.predictionView.image = image
            }
        }
    }
    
}

extension ViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        deviceOrientationDidChange(Notification(name: Notification.Name("")))
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        var requestOptions: [VNImageOption: Any] = [:]
        if let cameraIntrinsicData = CMGetAttachment(sampleBuffer, kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix, nil) {
            requestOptions = [.cameraIntrinsics: cameraIntrinsicData]
        }
        
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: requestOptions)
        do {
            try handler.perform([predictionRequest])
        } catch {
            print(error)
        }
    }
    
}

func maskToRGBA(maskArray: MultiArray<Double>,
                rgba: (r: Double, g: Double, b: Double, a: Double)) -> UIImage? {
    let height = maskArray.shape[1]
    let width = maskArray.shape[2]
    var bytes = [UInt8](repeating: 0, count: height * width * 4)
    
    for h in 0..<height {
        for w in 0..<width {
            let offset = h * width * 4 + w * 4
            let val = maskArray[0, h, w]
            bytes[offset + 0] = (val * rgba.r).toUInt8
            bytes[offset + 1] = (val * rgba.g).toUInt8
            bytes[offset + 2] = (val * rgba.b).toUInt8
            bytes[offset + 3] = (val * rgba.a).toUInt8
        }
    }
    
    return UIImage.fromByteArray(bytes, width: width, height: height,
                                 scale: 0, orientation: .up,
                                 bytesPerRow: width * 4,
                                 colorSpace: CGColorSpaceCreateDeviceRGB(),
                                 alphaInfo: .premultipliedLast)
}

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
//            let request = VNCoreMLRequest(model: model, completionHandler: self.handlePrediction)
            let request = VNCoreMLRequest(model: model)
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
        
//        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
//        cameraPreview.addCaptureVideoPreviewLayer(previewLayer)
        
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
        // each prediction is now attached to the request
        // obtain model result
        guard let observations = predictionRequest.results as? [VNCoreMLFeatureValueObservation] else {
            fatalError("unexpected result type from VNCoreMLRequest")
        }
        
        // convert to MLMultiArray and then convert to UIImage
        var mask: UIImage = UIImage()
        if let multiArray: MLMultiArray = observations[0].featureValue.multiArrayValue {
            mask = maskToRGBA(maskArray: MultiArray<Double>(multiArray), rgba: (255, 255, 0, 100))!
        }
        
        let image = mergeMaskAndBackground(mask: mask, background: pixelBuffer, size: 1080)!
        
        // Display images
        DispatchQueue.main.async { [weak self] in
            //                self?.cameraPreview.image = image
            self?.predictionView.image = image
        }
    }
        
    
}

//func resizedCroppedImage(image: UIImage, newSize:CGSize) -> UIImage {
//    var ratio: CGFloat = 0
//    var delta: CGFloat = 0
//    var offset = CGPoint.zero
//    if image.size.width > image.size.height {
//        ratio = newSize.width / image.size.width
//        delta = (ratio * image.size.width) - (ratio * image.size.height)
//        offset = CGPoint(x: delta / 2, y: 0)
//    } else {
//        ratio = newSize.width / image.size.height
//        delta = (ratio * image.size.height) - (ratio * image.size.width)
//        offset = CGPoint(x: 0, y: delta / 2)
//    }
//    let clipRect = CGRect(x: -offset.x, y: -offset.y, width: (ratio * image.size.width) + delta, height: (ratio * image.size.height) + delta)
//    UIGraphicsBeginImageContextWithOptions(newSize, true, 0.0)
//    UIRectClip(clipRect)
//    image.draw(in: clipRect)
//    let newImage = UIGraphicsGetImageFromCurrentImageContext()
//    UIGraphicsEndImageContext()
//    return newImage!
//}

func cropImageToSquare(image: UIImage) -> UIImage? {
    var imageHeight = image.size.height
    var imageWidth = image.size.width
    
    if imageHeight > imageWidth {
        imageHeight = imageWidth
    }
    else {
        imageWidth = imageHeight
    }
    
    let size = CGSize(width: imageWidth, height: imageHeight)
    
    let refWidth : CGFloat = CGFloat(image.cgImage!.width)
    let refHeight : CGFloat = CGFloat(image.cgImage!.height)
    
    let x = (refWidth - size.width) / 2
    let y = (refHeight - size.height) / 2
    
    let cropRect = CGRect(x: x, y: y, width: size.height, height: size.width)
    if let imageRef = image.cgImage!.cropping(to: cropRect) {
        return UIImage(cgImage: imageRef, scale: 0, orientation: image.imageOrientation)
    }
    
    return nil
}
    
func mergeMaskAndBackground(mask: UIImage, background: CVPixelBuffer, size: Int) -> UIImage? {
    // Merge two images
    let sizeImage = CGSize(width: size, height: size)
    UIGraphicsBeginImageContext(sizeImage)
    
    let areaSize = CGRect(x: 0, y: 0, width: sizeImage.width, height: sizeImage.height)
    
    // background
    var background = UIImage(pixelBuffer: background)
    background = cropImageToSquare(image: background!)
    background?.draw(in: areaSize)
    // mask
    mask.draw(in: areaSize)
    
    let newImage:UIImage = UIGraphicsGetImageFromCurrentImageContext()!
    UIGraphicsEndImageContext()
    return newImage
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

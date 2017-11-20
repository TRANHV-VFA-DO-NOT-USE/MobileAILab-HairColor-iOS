import UIKit
import AVFoundation

extension UIDevice {

    /// Vidoe orientation for current device orientation
    var videoOrientation: AVCaptureVideoOrientation {
        let orientation: AVCaptureVideoOrientation

        switch self.orientation {
        case .portrait:
            orientation = .portrait
        case .portraitUpsideDown:
            orientation = .portraitUpsideDown
        case .landscapeLeft:
            orientation = .landscapeRight
        case .landscapeRight:
            orientation = .landscapeLeft
        default: orientation = .portrait
        }

        return orientation
    }

    /// Subscribes target to default NotificationCenter .UIDeviceOrientationDidChange
    class func subscribeToDeviceOrientationNotifications(_ target: AnyObject, selector: Selector) {
        let center = NotificationCenter.default
        let name = NSNotification.Name.UIDeviceOrientationDidChange
        let selector = selector
        center.addObserver(target, selector: selector, name: name, object: nil)
    }
}

//
//  AVCaptureDevice.swift
//  MLCamera
//
//  Created by Michael Inger on 13/06/2017.
//  Copyright © 2017 stringCode ltd. All rights reserved.
//

import Foundation
import AVFoundation

extension AVCaptureDevice {
    
    /// Requests permission for AVCaptureDevice video access
    /// - parameter completion: Called on the main queue
    class func requestAuthorization(completion: @escaping (_ granted: Bool)->() ) {
        AVCaptureDevice.requestAccess(for: .video) { (granted) in
            DispatchQueue.main.async {
                completion(granted)
            }
        }
    }
}

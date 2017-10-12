//
//  ViewController.swift
//  RealTimeCameraPractice
//
//  Created by TKang on 2017. 10. 12..
//  Copyright © 2017년 TKang. All rights reserved.
//

import UIKit
import AVFoundation
import GLKit

class ViewController: UIViewController {
    
    var videoDevice : AVCaptureDevice!
    var captureSession : AVCaptureSession!
    var captureSessionQueue : DispatchQueue!
    var videoPreviewView: GLKView!
    var ciContext: CIContext!
    var eaglContext: EAGLContext!
    var videoPreviewViewBounds: CGRect!

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    func start() {
        let videoDevices = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: AVMediaType.video, position: .back).devices
        
        videoDevice = videoDevices.first
        
        var videoDeviceInput : AVCaptureInput!
        do {
            videoDeviceInput =  try AVCaptureDeviceInput(device: videoDevice)
        } catch let error {
            print("Unable to obtain video device input, error: \(error)")
            return
        }
        
        let preset = AVCaptureSession.Preset.high
        captureSession = AVCaptureSession()
        captureSession.sessionPreset = preset
        
        // core image watns bgra pixel format
        let outputSetting = [String(kCVPixelBufferPixelFormatTypeKey): kCVPixelFormatType_32BGRA]
        // crate and configure video data output
        let videoDataOutput = AVCaptureVideoDataOutput()
        videoDataOutput.videoSettings = outputSetting
        
        // create the dispatch queue for handling capture session delegate method calls
        captureSessionQueue = DispatchQueue(label: "capture_session_queue")
        videoDataOutput.setSampleBufferDelegate(self, queue: captureSessionQueue)
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        
        captureSession.beginConfiguration()
        if !captureSession.canAddOutput(videoDataOutput) {
            print("Cannot add video data output")
            captureSession = nil
            return
        }
        
        captureSession.addInput(videoDeviceInput)
        captureSession.addOutput(videoDataOutput)
        
        captureSession.commitConfiguration()
        
        captureSession.startRunning()
    }

}

extension ViewController : AVCaptureVideoDataOutputSampleBufferDelegate {
    
}

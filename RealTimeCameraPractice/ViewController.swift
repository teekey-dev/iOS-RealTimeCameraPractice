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
import OpenGLES

class ViewController: UIViewController {
    
    var videoDevice : AVCaptureDevice!
    var captureSession : AVCaptureSession!
    var captureSessionQueue : DispatchQueue!
    var videoPreviewView: GLKView!
    var ciContext: CIContext!
    var eaglContext: EAGLContext!
    var videoPreviewViewBounds: CGRect = CGRect.zero

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        // remove the view's background color; this allows us not to use the opaque property (self.view.opaque = NO) since we remove the background color drawing altogether
        self.view.backgroundColor = UIColor.clear
        
        // setup the GLKView for video/image preview
        let window : UIView = UIApplication.shared.delegate!.window!!
        eaglContext = EAGLContext(api: .openGLES2)
        videoPreviewView = GLKView(frame: videoPreviewViewBounds, context: eaglContext)
        videoPreviewView.enableSetNeedsDisplay = false
        
        // because the native video image from the back camera is in UIDeviceOrientationLandscapeLeft (i.e. the home button is on the right), we need to apply a clockwise 90 degree transform so that we can draw the video preview as if we were in a landscape-oriented view; if you're using the front camera and you want to have a mirrored preview (so that the user is seeing themselves in the mirror), you need to apply an additional horizontal flip (by concatenating CGAffineTransformMakeScale(-1.0, 1.0) to the rotation transform)
        videoPreviewView.transform = CGAffineTransform(rotationAngle: CGFloat.pi/2.0)
        videoPreviewView.frame = window.bounds
        
        // we make our video preview view a subview of the window, and send it to the back; this makes ViewController's view (and its UI elements) on top of the video preview, and also makes video preview unaffected by device rotation
        window.addSubview(videoPreviewView)
        window.sendSubview(toBack: videoPreviewView)
        
        // bind the frame buffer to get the frame buffer width and height;
        // the bounds used by CIContext when drawing to a GLKView are in pixels (not points),
        // hence the need to read from the frame buffer's width and height;
        // in addition, since we will be accessing the bounds in another queue (_captureSessionQueue),
        // we want to obtain this piece of information so that we won't be
        // accessing _videoPreviewView's properties from another thread/queue
        videoPreviewView.bindDrawable()
        videoPreviewViewBounds = CGRect.zero
        videoPreviewViewBounds.size.width = CGFloat(videoPreviewView.drawableWidth)
        videoPreviewViewBounds.size.height = CGFloat(videoPreviewView.drawableHeight)
        
        // create the CIContext instance, note that this must be done after _videoPreviewView is properly set up
        ciContext = CIContext(eaglContext: eaglContext, options: [kCIContextWorkingColorSpace: NSNull()])
        
        if AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInDualCamera, .builtInTelephotoCamera, .builtInWideAngleCamera], mediaType: AVMediaType.video, position: .back).devices.count > 0 {
            start()
        } else {
            print("No device with AVMediaTypeVideo")
        }
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
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let imageBuffer : CVImageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)!
        let sourceImage = CIImage(cvImageBuffer: imageBuffer, options: nil)
        let sourceExtent = sourceImage.extent
        
        let vignetteFilter = CIFilter(name: "CIVignetteEffect", withInputParameters: nil)
        vignetteFilter?.setValue(sourceImage, forKey: kCIInputImageKey)
        vignetteFilter?.setValue(CIVector(x: sourceExtent.size.width/2.0, y: sourceExtent.size.height/2.0), forKey: kCIInputCenterKey)
        vignetteFilter?.setValue(sourceExtent.width/2.0, forKey: kCIInputRadiusKey)
        let filteredImage = vignetteFilter?.outputImage
        
        let sourceAspect = sourceExtent.width/sourceExtent.height
        let previewAspect = videoPreviewViewBounds.width/videoPreviewViewBounds.height
        
        // we want to maintain the aspect radio of the screen size, so we clip the video image
        var drawRect = sourceExtent
        if sourceAspect > previewAspect {
            // use full height of the video image, and center crop the width
            drawRect.origin.x += (drawRect.size.width - drawRect.size.height * previewAspect) / 2.0
            drawRect.size.width = drawRect.size.height * previewAspect
        } else {
            // use full width of the video image, and center crop the height
            drawRect.origin.y += (drawRect.size.height - drawRect.size.width / previewAspect) / 2.0;
            drawRect.size.height = drawRect.size.width / previewAspect;
        }
        
        videoPreviewView.bindDrawable()
        
        if eaglContext != EAGLContext.current() {
            EAGLContext.setCurrent(eaglContext)
        }
        print("current thread \(Thread.current)")
        // clear eagl view to grey
        glClearColor(0.5, 0.5, 0.5, 1.0);
        glClear(GLbitfield(GL_COLOR_BUFFER_BIT));
        
        // set the blend mode to "source over" so that CI will use that
        glEnable(GLenum(GL_BLEND));
        glBlendFunc(GLenum(GL_ONE), GLenum(GL_ONE_MINUS_SRC_ALPHA));
        
        if let filteredImage = filteredImage {
            ciContext.draw(filteredImage, in: videoPreviewViewBounds, from: drawRect)
        }
        
        videoPreviewView.display()
    }
}

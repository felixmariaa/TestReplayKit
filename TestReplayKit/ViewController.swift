//
//  ViewController.swift
//  TestReplayKit
//
//  Created by Felix Marianayagam on 3/28/20.
//  Copyright © 2020 SubhaFelix. All rights reserved.
//

import UIKit
import ReplayKit
import Photos
import Accelerate

class ViewController: UIViewController {

    @IBOutlet weak var btnStartRecording: UIButton!
    @IBOutlet weak var btnStopRecording: UIButton!
    @IBOutlet weak var yellowView: UIView!
    
    var videoWriter: AVAssetWriter?
    var videoWriterInput: AVAssetWriterInput?

    let recorder = RPScreenRecorder.shared()
    let authStatus: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus()
    let videoOutputURL: URL = {
        let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0] as NSString
        return URL(fileURLWithPath: documentsPath.appendingPathComponent("ScreenRecording.mp4"))
    }()
    
    @IBAction func startRecording(_ sender: UIButton) {
        startRecording()
    }
    
    @IBAction func stopRecording(_ sender: Any) {
        stopRecording()
    }
    
    func startRecording() {
        // Try deleting the file if it already exists.
        do {
            try FileManager.default.removeItem(at: videoOutputURL)
        } catch {}

        do {
            try self.videoWriter = AVAssetWriter(outputURL: videoOutputURL, fileType: AVFileType.mp4)
        } catch let writerError as NSError {
            print("Error opening video file", writerError)
            self.videoWriter = nil
            return
        }

        let videoSettings: [String : Any] = [
            AVVideoCodecKey : AVVideoCodecType.h264,
            AVVideoWidthKey : UIScreen.main.bounds.size.width,
            AVVideoHeightKey : UIScreen.main.bounds.size.height
        ]

        self.videoWriterInput = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: videoSettings)
        self.videoWriter!.add(videoWriterInput!)

        RPScreenRecorder.shared().startCapture(handler: { (cmSampleBuffer, rpSampleType, error) in
            guard error == nil else {
                print("Error starting capture")
                return
            }

            if rpSampleType == RPSampleBufferType.video {
                if self.videoWriter!.status == AVAssetWriter.Status.unknown {
                    if ((self.videoWriter?.startWriting ) != nil) {
                        self.videoWriter!.startWriting()
                        self.videoWriter!.startSession(atSourceTime:  CMSampleBufferGetPresentationTimeStamp(cmSampleBuffer))
                    }
                }
                else if self.videoWriter!.status == AVAssetWriter.Status.writing {
                    if (self.videoWriterInput!.isReadyForMoreMediaData == true) {
                        var timingInfo = CMSampleTimingInfo(duration: cmSampleBuffer.duration, presentationTimeStamp: cmSampleBuffer.presentationTimeStamp, decodeTimeStamp: cmSampleBuffer.decodeTimeStamp)
                        let imageBuffer: CVImageBuffer = CMSampleBufferGetImageBuffer(cmSampleBuffer)!

                        // MARK: ONLY the portion within START and END has issues and need help.
                        // MARK: START ...
                        
                        // Record only the yellow portion (UIView with UILabel and UITextView) and not the full screen. This is the height and width of the yellow UIView.
                        let cropWidth = Int(self.yellowView.bounds.width)
                        let cropHeight = Int(self.yellowView.bounds.height)
                        // Using the screen height and width for scale height. Not sure if this is correct.
                        let scaleWidth = Int(UIScreen.main.bounds.width)
                        let scaleHeight = Int(UIScreen.main.bounds.height)
                        
                        // ISSUE 1: Trying to crop the pixel buffer and it returns but fails during writing
                        guard let destBuffer: CVImageBuffer = self.cropPixelBuffer(imageBuffer, cropX: 0, cropY: 0, cropWidth: cropWidth, cropHeight: cropHeight, scaleWidth: scaleWidth, scaleHeight: scaleHeight) else {
                            return
                        }
                        var cmSampleBufferOut: CMSampleBuffer?
                        // ISSUE 2: The destBuffer results in error here as I guess it's not using the right video format or size.
                        CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: destBuffer, formatDescription: cmSampleBuffer.formatDescription!, sampleTiming: &timingInfo, sampleBufferOut: &cmSampleBufferOut)
                        if let cmSampleBufferOut = cmSampleBufferOut {
                            if self.videoWriterInput!.append(cmSampleBufferOut) == false {
                                print("Error appending to video writer.")
                            }
                        }
                        // MARK: END ...
                        
                        // Uncomment this for full screen recording.
                        /*
                        if self.videoWriterInput!.append(cmSampleBuffer) == false {
                            print("Error appending to video writer.")
                        }
                        */
                    }
                }
            }
        })
    }

    func stopRecording() {
        RPScreenRecorder.shared().stopCapture( handler: { (error) in
            print("stopping recording")
        })

        self.videoWriterInput!.markAsFinished()
        self.videoWriter!.finishWriting {
            print("finished writing video")
            
            // Save the video to the Photo library
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: self.videoOutputURL)
            }) { saved, error in
                guard error == nil else {
                    print(String(format: "Error saving video - %@", error.debugDescription))
                    return
                }
                if saved {
                    print("Screen recording was successfully saved to photo library.")
                }
            }
        }
    }
    
    // The below code was taken from    https://github.com/hollance/CoreMLHelpers/blob/master/CoreMLHelpers/CVPixelBuffer%2BHelpers.swift
    // Tested this code using a UIImage and it worked. Assumed, that this will also work with the video buffer which I assume is having two planes. Therefore, modified it for working with planes. But it doesn't seem to work.
    func cropPixelBuffer(_ srcPixelBuffer: CVPixelBuffer, cropX: Int, cropY: Int, cropWidth: Int, cropHeight: Int, scaleWidth: Int, scaleHeight: Int) -> CVPixelBuffer? {
        
        let flags = CVPixelBufferLockFlags(rawValue: 0)
        guard kCVReturnSuccess == CVPixelBufferLockBaseAddress(srcPixelBuffer, flags) else {
            return nil
        }
        defer { CVPixelBufferUnlockBaseAddress(srcPixelBuffer, flags) }

        guard let srcData = CVPixelBufferGetBaseAddressOfPlane(srcPixelBuffer, 0) else {
            print("Error: could not get pixel buffer base address")
            return nil
        }
        let srcBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(srcPixelBuffer, 0)
        let offset = cropY*srcBytesPerRow + cropX*4
        var srcBuffer = vImage_Buffer(data: srcData.advanced(by: offset),
                                      height: vImagePixelCount(cropHeight),
                                      width: vImagePixelCount(cropWidth),
                                      rowBytes: srcBytesPerRow)

        let destBytesPerRow = scaleWidth * 4
        guard let destData = malloc(scaleHeight*destBytesPerRow) else {
            print("Error: out of memory")
            return nil
        }
        var destBuffer = vImage_Buffer(data: destData,
                                       height: vImagePixelCount(scaleHeight),
                                       width: vImagePixelCount(scaleWidth),
                                       rowBytes: destBytesPerRow)

        let error = vImageScale_ARGB8888(&srcBuffer, &destBuffer, nil, vImage_Flags(0))
        if error != kvImageNoError {
            print("Error:", error)
            free(destData)
            return nil
        }

        let releaseCallback: CVPixelBufferReleaseBytesCallback = { _, ptr in
            if let ptr = ptr {
                free(UnsafeMutableRawPointer(mutating: ptr))
            }
        }

        let pixelFormat = CVPixelBufferGetPixelFormatType(srcPixelBuffer)
        var dstPixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreateWithBytes(nil, scaleWidth, scaleHeight,
                                                  pixelFormat, destData,
                                                  destBytesPerRow, releaseCallback,
                                                  nil, nil, &dstPixelBuffer)
        if status != kCVReturnSuccess {
            print("Error: could not create new pixel buffer")
            free(destData)
            return nil
        }
        return dstPixelBuffer
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view
        
        if (authStatus == PHAuthorizationStatus.notDetermined) {
            // Access has not been determined.
            PHPhotoLibrary.requestAuthorization({ (newStatus) in
                if (newStatus == PHAuthorizationStatus.authorized) {
                    print("Authorized.")
                }
            })
        }
    }
}

extension ViewController: RPPreviewViewControllerDelegate {
    func previewControllerDidFinish(_ previewController: RPPreviewViewController) {
        dismiss(animated: true)
    }
}

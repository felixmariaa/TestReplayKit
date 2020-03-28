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

class ViewController: UIViewController {

    @IBOutlet weak var btnStartRecording: UIButton!
    @IBOutlet weak var btnStopRecording: UIButton!
  
    var videoWriter: AVAssetWriter?
    var videoWriterInput: AVAssetWriterInput?

    let recorder = RPScreenRecorder.shared()
    let authStatus: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus()
    let videoOutputURL: URL = {
        //Create the file path to write to
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
        do {
            try self.videoWriter = AVAssetWriter(outputURL: videoOutputURL, fileType: AVFileType.mp4)
        }
        catch let writerError as NSError {
            print("Unable to create Asset writer.", writerError)
            return
        }

        let videoSettings: [String : Any] = [
            AVVideoCodecKey : AVVideoCodecType.h264,
            AVVideoWidthKey : UIScreen.main.bounds.size.width,
            AVVideoHeightKey : UIScreen.main.bounds.size.height
        ]

        self.videoWriterInput = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: videoSettings)
        self.videoWriter!.add(videoWriterInput!)

        //Tell the screen recorder to start capturing and to call the handler when it has a sample
        RPScreenRecorder.shared().startCapture(handler: { (cmSampleBuffer, rpSampleType, error) in
            guard error == nil else {
                print("Error starting capture")
                return
            }

            if rpSampleType == RPSampleBufferType.video {
                if self.videoWriter!.status == AVAssetWriter.Status.unknown {
                    if self.videoWriter!.startWriting != nil {
                        self.videoWriter!.startWriting()
                        self.videoWriter!.startSession(atSourceTime:  CMSampleBufferGetPresentationTimeStamp(cmSampleBuffer))
                    }
                }
                else if self.videoWriter!.status == AVAssetWriter.Status.writing {
                    if (self.videoWriterInput!.isReadyForMoreMediaData == true) {
                        if !self.videoWriterInput!.append(cmSampleBuffer) {
                            print("Error while appending cmSampleBuffer")
                        }
                    }
                }
            }
        })
    }

    func stopRecording() {
        //Stop Recording the screen
        RPScreenRecorder.shared().stopCapture( handler: { (error) in
            print("stopping recording")
        })

        self.videoWriterInput!.markAsFinished()
        self.videoWriter!.finishWriting {
            print("finished writing video")
            
            //Now save the video
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

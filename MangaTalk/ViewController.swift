//
//  ViewController.swift
//  MangaTalk
//
//  Created by Muyao Xu & Peixuan Liu on 2019/1/12.
//  Copyright © 2019 MangaTalk. All rights reserved.
//
// Citation:
// https://github.com/jen2/Speech-Recognition-Demo
// https://www.youtube.com/redirect?v=FEqBW3cKF2k&redir_token=3IKoyx99byE5rSiAXeAjlVpxcPh8MTU0NzQzMDIxM0AxNTQ3MzQzODEz&event=video_description&q=https%3A%2F%2Fgithub.com%2Fbrianadvent%2F3DObjectScanningAndDetection
// https://www.youtube.com/redirect?v=R8U8rGdMop4&redir_token=cZ6S1keSH66Lesj5ADdwfxvErSJ8MTU0NzQzMDI0OEAxNTQ3MzQzODQ4&event=video_description&q=https%3A%2F%2Fgithub.com%2Fbrianadvent%2FSimple-ARKit-Game

import UIKit
import ARKit
import Vision
import Speech

class ViewController: UIViewController, SFSpeechRecognizerDelegate {
    
    @IBOutlet weak var faceWarningLabel: UILabel!
    @IBOutlet weak var sceneView: ARSCNView!
    @IBOutlet weak var startButton: UIButton!
//    @IBOutlet weak var detectedTextLabel: UILabel!
    
    var plane = SCNPlane()
    
    let audioEngine = AVAudioEngine()
    let speechRecognizer: SFSpeechRecognizer? = SFSpeechRecognizer()
    let request = SFSpeechAudioBufferRecognitionRequest()
    var recognitionTask: SFSpeechRecognitionTask?
    var isRecording = false
    var hasDetectedFace = false
    
    private var scannedFaceViews = [UIView]()
    
    //get the orientation of the image that correspond's to the current device orientation
    private var imageOrientation: CGImagePropertyOrientation {
        switch UIDevice.current.orientation {
        case .portrait: return .right
        case .landscapeRight: return .down
        case .portraitUpsideDown: return .left
        case .unknown: fallthrough
        case .faceUp: fallthrough
        case .faceDown: fallthrough
        case .landscapeLeft: return .up
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.requestSpeechAuthorization()
        
        let scene = SCNScene()
        sceneView.scene = scene
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        let configuration = ARWorldTrackingConfiguration()
        sceneView.session.run(configuration)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        sceneView.session.pause()
    }
    
    @objc
    private func scanForFaces() {
        
        //remove the test views and empty the array that was keeping a reference to them
        _ = scannedFaceViews.map { $0.removeFromSuperview() }
        scannedFaceViews.removeAll()
        
        //get the captured image of the ARSession's current frame
        guard let capturedImage = sceneView.session.currentFrame?.capturedImage else { return }
        
        let image = CIImage.init(cvPixelBuffer: capturedImage)
        
        let detectFaceRequest = VNDetectFaceRectanglesRequest { (request, error) in
            
            DispatchQueue.main.async {
                //Loop through the resulting faces and add a red UIView on top of them.
                if let faces = request.results as? [VNFaceObservation] {
                    if faces.count == 0 {
                        print("No face in the frame")
                        self.faceWarningLabel.isHidden = false
                        self.hasDetectedFace = false
                    }
                    else {
                        self.faceWarningLabel.isHidden = true
                        self.startButton.setTitle("tap to listen", for: [])
                        self.hasDetectedFace = true
                        self.plane = SCNPlane(width: 0.5, height: 0.125)
                        
                        self.plane.cornerRadius = self.plane.width / 8
                        
                        let spriteKitScene = SKScene(fileNamed: "dialog")
                        
                        self.plane.firstMaterial?.diffuse.contents = spriteKitScene
                        self.plane.firstMaterial?.isDoubleSided = true
                        self.plane.firstMaterial?.diffuse.contentsTransform = SCNMatrix4Translate(SCNMatrix4MakeScale(1, -1, 1), 0, 1, 0)
                        //
                        let planeNode = SCNNode(geometry: self.plane)
                        planeNode.position = SCNVector3Make(0.0, 0.05, -1)
                        
                        self.sceneView.scene.rootNode.addChildNode(planeNode)
                    }
                }
            }
        }
        
        DispatchQueue.global().async {
            try? VNImageRequestHandler(ciImage: image, orientation: self.imageOrientation).perform([detectFaceRequest])
        }
    }
    
    private func faceFrame(from boundingBox: CGRect) -> CGRect {
        
        //translate camera frame to frame inside the ARSKView
        let origin = CGPoint(x: boundingBox.minX * sceneView.bounds.width, y: (1 - boundingBox.maxY) * sceneView.bounds.height)
        let size = CGSize(width: boundingBox.width * sceneView.bounds.width, height: boundingBox.height * sceneView.bounds.height)
        
        return CGRect(origin: origin, size: size)
    }
    
    @IBAction func startButtonTapped(_ sender: Any) {
        if hasDetectedFace == false {
            
            scanForFaces()
            if hasDetectedFace == false {
                print("why false")
                return
            }
        }
        if isRecording == true {
            print("ended recording")
            audioEngine.stop()
            recognitionTask?.cancel()
            isRecording = false
            startButton.setTitle("tap to listen", for: [])
            startButton.setTitleColor(UIColor(red: 146/255.0, green: 94/255.0, blue: 35/255.0, alpha: 1), for: [])
            startButton.backgroundColor = UIColor(red: 255/255.0, green: 217/255.0, blue: 120/255.0, alpha: 1)

        }
        else {
            print("started recording")
            self.recordAndRecognizeSpeech()
            isRecording = true
            startButton.setTitle("listening", for: [])
            startButton.setTitleColor(UIColor.white, for: [])
            startButton.backgroundColor = UIColor(red: 233/255.0, green: 78/255.0, blue: 63/255.0, alpha: 1)
        }
    }
    
    func cancelRecording() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionTask?.cancel()
    }
    
    //MARK: - Recognize Speech
    
    func recordAndRecognizeSpeech() {
        let node = audioEngine.inputNode
        //        guard let node = audioEngine.inputNode else { return }
        let recordingFormat = node.outputFormat(forBus: 0)
        node.removeTap(onBus: 0)
        node.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            self.request.append(buffer)
        }
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            return print(error)
        }
        guard let myRecognizer = SFSpeechRecognizer() else {
             return
        }
        if !myRecognizer.isAvailable {
            // Recognizer is not available right now
            return
        }
        recognitionTask = speechRecognizer?.recognitionTask(with: request, resultHandler: { result, error in
            if let result = result {
                
                let bestString = result.bestTranscription.formattedString
                
                let spriteKitScene = SKScene(fileNamed: "dialog")
                
                let displayString = String(bestString.suffix(20))
                
                if var label = spriteKitScene?.childNode(withName: "body") as? SKLabelNode {
                    label.text = displayString
                }
                self.plane.firstMaterial?.diffuse.contents = spriteKitScene
//                self.detectedTextLabel.text = bestString
                var lastString: String = ""
                for segment in result.bestTranscription.segments {
                    let indexTo = bestString.index(bestString.startIndex, offsetBy: segment.substringRange.location)
                    lastString = bestString.substring(from: indexTo)
                }
            }
        })
    }
    
    //MARK: - Check Authorization Status
    
    func requestSpeechAuthorization() {
        SFSpeechRecognizer.requestAuthorization { authStatus in
            OperationQueue.main.addOperation {
                if authStatus == .authorized {
                    self.startButton.isEnabled = true
                }
            }
        }
    }
    
}

extension ViewController: ARSCNViewDelegate {
    //implement ARSCNViewDelegate functions for things like error tracking
}



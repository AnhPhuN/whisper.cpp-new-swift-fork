//
//  ViewController.swift
//  whisper.objc
//
//  Created by Phu Nguyen on 8/25/23.
//

import UIKit
import AVFoundation

class ViewController: UIViewController {
    let NUM_BYTES_PER_BUFFER = 16 * 1024
    let NUM_BUFFERS = 3
    let MAX_AUDIO_SEC = 30
    let SAMPLE_RATE = 16000
    let WHISPER_SAMPLE_RATE = 16000
    
    struct whisper_context {}
    
    let wrapper = WhisperWrapper()

    
    var stateInp: StateInp?

    @IBOutlet weak var labelStatusInp: UILabel!
    @IBOutlet weak var buttonToggleCapture: UIButton!
    @IBOutlet weak var buttonTranscribe: UIButton!
    @IBOutlet weak var buttonRealtime: UIButton!
    @IBOutlet weak var textviewResult: UITextView!

    // Define stateInp structure and other variables here
    struct StateInp {
        var ctx: UnsafeMutablePointer<whisper_context>? // Replace with the correct type for the whisper context
        var dataFormat: AudioStreamBasicDescription
        var n_samples: Int
        var audioBufferI16: UnsafeMutablePointer<Int16>?
        var audioBufferF32: UnsafeMutablePointer<Float>?
        var isTranscribing: Bool
        var isRealtime: Bool
        var isCapturing: Bool
        var queue: AudioQueueRef?
        var buffers: [AudioQueueBufferRef?]
        weak var vc: ViewController?
    }
    


    
    override func viewDidLoad() {
        super.viewDidLoad()

        // whisper.cpp initialization
        // Load the model
        if let modelPath = Bundle.main.path(forResource: "ggml-base.en", ofType: "bin"),
           FileManager.default.fileExists(atPath: modelPath) {
            print("Loading model from \(modelPath)")

            // Create ggml context
            // Replace with the correct function to initialize the whisper context
            stateInp?.ctx = whisper_init_from_file(modelPath)


            // Check if the model was loaded successfully
            if stateInp?.ctx == nil {
                print("Failed to load model")
                return
            }
        } else {
            print("Model file not found")
            return
        }

        // Initialize audio format and buffers
        setupAudioFormat(&stateInp!.dataFormat)

        stateInp?.n_samples = 0
        stateInp?.audioBufferI16 = malloc(MAX_AUDIO_SEC * SAMPLE_RATE * MemoryLayout<Int16>.size).assumingMemoryBound(to: Int16.self)
        stateInp?.audioBufferF32 = malloc(MAX_AUDIO_SEC * SAMPLE_RATE * MemoryLayout<Float>.size).assumingMemoryBound(to: Float.self)

        stateInp?.isTranscribing = false
        stateInp?.isRealtime = false
    }


    func setupAudioFormat(_ format: inout AudioStreamBasicDescription) {
        format.mSampleRate = Float64(WHISPER_SAMPLE_RATE)
        format.mFormatID = kAudioFormatLinearPCM
        format.mFramesPerPacket = 1
        format.mChannelsPerFrame = 1
        format.mBytesPerFrame = 2
        format.mBytesPerPacket = 2
        format.mBitsPerChannel = 16
        format.mReserved = 0
        format.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger
    }


    @IBAction func stopCapturing() {
        print("Stop capturing")

        labelStatusInp.text = "Status: Idle"
        buttonToggleCapture.setTitle("Start capturing", for: .normal)
        buttonToggleCapture.backgroundColor = UIColor.gray

        stateInp?.isCapturing = false

        AudioQueueStop(stateInp?.queue! ?? <#default value#>, true)
        for i in 0..<NUM_BUFFERS {
            AudioQueueFreeBuffer(stateInp?.queue! ?? <#default value#>, stateInp?.buffers[i] ?? <#default value#>)
        }

        AudioQueueDispose(stateInp?.queue! ?? <#default value#>, true)
    }

    @IBAction func toggleCapture(_ sender: Any) {
        if ((stateInp?.isCapturing) != nil) {
            // stop capturing
            stopCapturing()
            return
        }

        // initiate audio capturing
        print("Start capturing")

        stateInp?.n_samples = 0
        stateInp?.vc = self

        var status = AudioQueueNewInput((&stateInp?.dataFormat)!,
                                        AudioInputCallback,
                                        &stateInp,
                                        CFRunLoopGetCurrent(),
                                        CFRunLoopMode.commonModes.rawValue,
                                        0,
                                        &stateInp?.queue)

        if status == 0 {
            for i in 0..<NUM_BUFFERS {
                AudioQueueAllocateBuffer(stateInp?.queue! ?? <#default value#>, UInt32(NUM_BYTES_PER_BUFFER), &stateInp?.buffers[i])
                AudioQueueEnqueueBuffer((stateInp?.queue!)!, stateInp?.buffers[i]!!, 0, nil)
            }

            stateInp?.isCapturing = true
            status = AudioQueueStart(stateInp?.queue!, nil)
            if status == 0 {
                labelStatusInp.text = "Status: Capturing"
                (sender as! UIButton).setTitle("Stop Capturing", for: .normal)
                buttonToggleCapture.backgroundColor = UIColor.red
            }
        }

        if status != 0 {
            stopCapturing()
        }
    }

    @IBAction func onTranscribePrepare(_ sender: Any) {
        textviewResult.text = "Processing - please wait ..."

        if ((stateInp?.isRealtime) != nil) {
            onRealtime(sender)
        }

        if ((stateInp?.isCapturing) != nil) {
            stopCapturing()
        }
    }


    @IBAction func onRealtime(_ sender: Any) {
        stateInp?.isRealtime.toggle()

        if stateInp!.isRealtime {
            buttonRealtime.backgroundColor = UIColor.green
        } else {
            buttonRealtime.backgroundColor = UIColor.gray
        }

        print("Realtime: \(stateInp?.isRealtime ? "ON" : "OFF")")
    }

    @IBAction func onTranscribe(_ sender: Any) {
        if stateInp?.isTranscribing == true {
            return
        }

        print("Processing \(stateInp?.n_samples ?? 0) samples")

        stateInp?.isTranscribing = true

        // Dispatch the model to a background thread
        DispatchQueue.global(qos: .default).async {
            // Process captured audio
            // Convert I16 to F32
            for i in 0..<(self.stateInp?.n_samples ?? 0) {
                self.stateInp?.audioBufferF32?[i] = Float(self.stateInp?.audioBufferI16?[i] ?? 0) / 32768.0
            }

            // Run the model
            var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)

            // Get maximum number of threads on this device (max 8)
            let max_threads = min(8, ProcessInfo.processInfo.processorCount)

            params.print_realtime = true
            params.print_progress = false
            params.print_timestamps = true
            params.print_special = false
            params.translate = false
            params.language = "en"
            params.n_threads = max_threads
            params.offset_ms = 0
            params.no_context = true
            params.single_segment = self.stateInp?.isRealtime ?? false

            let startTime = CACurrentMediaTime()

            whisper_reset_timings(self.stateInp?.ctx)

            if whisper_full(self.stateInp?.ctx, params, self.stateInp?.audioBufferF32, self.stateInp?.n_samples ?? 0) != 0 {
                print("Failed to run the model")
                DispatchQueue.main.async {
                    self.textviewResult.text = "Failed to run the model"
                }
                return
            }

            whisper_print_timings(self.stateInp?.ctx)

            let endTime = CACurrentMediaTime()

            print("\nProcessing time: \(endTime - startTime), on \(params.n_threads) threads")

            // Result text
            var result = ""

            let n_segments = whisper_full_n_segments(self.stateInp?.ctx ?? nil)
            for i in 0..<n_segments {
                if let text_cur = whisper_full_get_segment_text(self.stateInp?.ctx, i) {
                    // Append the text to the result
                    result += String(cString: text_cur)
                }
            }

            let tRecording = Float(self.stateInp?.n_samples ?? 0) / Float(self.stateInp?.dataFormat.mSampleRate ?? 0)

            // Append processing time
            result += "\n\n[recording time:  \(tRecording) s]"
            result += "  \n[processing time: \(endTime - startTime) s]"

            // Dispatch the result to the main thread
            DispatchQueue.main.async {
                self.textviewResult.text = result
                self.stateInp?.isTranscribing = false
            }
        }
    }


    func AudioInputCallback(inUserData: UnsafeMutableRawPointer?,
                            inAQ: AudioQueueRef,
                            inBuffer: AudioQueueBufferRef,
                            inStartTime: UnsafePointer<AudioTimeStamp>,
                            inNumberPacketDescriptions: UInt32,
                            inPacketDescs: UnsafePointer<AudioStreamPacketDescription>?) {
        guard let userData = inUserData else {
            print("Not capturing, ignoring audio")
            return
        }

        var stateInp = userData.assumingMemoryBound(to: StateInp.self).pointee

        if !stateInp.isCapturing {
            print("Not capturing, ignoring audio")
            return
        }

        let n = Int(inBuffer.pointee.mAudioDataByteSize) / 2

        print("Captured \(n) new samples")

        if stateInp.n_samples + n > MAX_AUDIO_SEC * SAMPLE_RATE {
            print("Too much audio data, ignoring")

            DispatchQueue.main.async {
                let vc = Unmanaged<ViewController>.fromOpaque(userData).takeUnretainedValue()
                vc.stopCapturing()
            }

            return
        }

        let audioData = inBuffer.pointee.mAudioData.assumingMemoryBound(to: Int16.self)

        for i in 0..<n {
            stateInp.audioBufferI16?[stateInp.n_samples + i] = audioData[i]
        }

        stateInp.n_samples += n

        // Put the buffer back in the queue
        AudioQueueEnqueueBuffer(stateInp.queue!, inBuffer, 0, nil)

        if stateInp.isRealtime {
            // Dispatch onTranscribe() to the main thread
            DispatchQueue.main.async {
                let vc = Unmanaged<ViewController>.fromOpaque(userData).takeUnretainedValue()
                vc.onTranscribe(nil)
            }
        }
    }


}

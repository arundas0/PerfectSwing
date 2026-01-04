import AVFoundation
import UIKit

class RingBuffer {
    private var buffers: [CMSampleBuffer] = []
    private let maxDuration: TimeInterval
    private let queue = DispatchQueue(label: "com.swingsync.ringBufferQueue")
    
    init(maxDuration: TimeInterval = 4.0) {
        self.maxDuration = maxDuration
    }
    
    func append(_ sampleBuffer: CMSampleBuffer) {
        queue.async {
            self.buffers.append(sampleBuffer)
            self.trim()
        }
    }
    
    private func trim() {
        guard let lastBuffer = buffers.last,
              let firstBuffer = buffers.first else { return }
        
        let lastTime = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(lastBuffer))
        let firstTime = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(firstBuffer))
        
        if (lastTime - firstTime) > maxDuration {
            buffers.removeFirst()
            trim() // Recursively trim if still too long (rare if appended one by one)
        }
    }
    
    func save(to url: URL, completion: @escaping (Result<URL, Error>) -> Void) {
        queue.async {
            guard !self.buffers.isEmpty else {
                completion(.failure(NSError(domain: "RingBuffer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Buffer empty"])))
                return
            }
            
            // Create AVAssetWriter
            do {
                let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
                
                // Get settings from first buffer
                let firstBuffer = self.buffers[0]
                guard let formatDescription = CMSampleBufferGetFormatDescription(firstBuffer) else {
                     completion(.failure(NSError(domain: "RingBuffer", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid format description"])))
                     return
                }
                
                let videoSettings: [String: Any] = [
                    AVVideoCodecKey: AVVideoCodecType.h264,
                    AVVideoWidthKey: CMVideoFormatDescriptionGetDimensions(formatDescription).width,
                    AVVideoHeightKey: CMVideoFormatDescriptionGetDimensions(formatDescription).height
                ]
                
                let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
                input.expectsMediaDataInRealTime = false
                
                if writer.canAdd(input) {
                    writer.add(input)
                    writer.startWriting()
                    writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(firstBuffer))
                    
                    for buffer in self.buffers {
                        if input.isReadyForMoreMediaData {
                            input.append(buffer)
                        } else {
                            // Simple spin wait or drop? For file writing usually it's fast enough. 
                            // In prod, use requestMediaDataWhenReadyOnQueue but for short clips this often works.
                             while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.001) }
                             input.append(buffer)
                        }
                    }
                    
                    input.markAsFinished()
                    writer.finishWriting {
                        if writer.status == .completed {
                            completion(.success(url))
                        } else {
                            completion(.failure(writer.error ?? NSError(domain: "RingBuffer", code: -3, userInfo: [NSLocalizedDescriptionKey: "Writer failed"])))
                        }
                    }
                } else {
                    completion(.failure(NSError(domain: "RingBuffer", code: -4, userInfo: [NSLocalizedDescriptionKey: "Cannot add input"])))
                }
                
            } catch {
                completion(.failure(error))
            }
        }
    }
    
    func clear() {
        queue.async {
            self.buffers.removeAll()
        }
    }
}

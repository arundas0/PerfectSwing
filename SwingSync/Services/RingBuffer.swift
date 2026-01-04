import AVFoundation
import UIKit
import CoreVideo

/// A frame stored in the ring buffer with copied pixel data
struct CapturedFrame {
    let pixelBuffer: CVPixelBuffer
    let presentationTime: CMTime
}

class RingBuffer {
    private var frames: [CapturedFrame] = []
    private let maxDuration: TimeInterval
    private let queue = DispatchQueue(label: "com.swingsync.ringBufferQueue")
    
    // Pixel buffer pool for efficient allocation
    private var pixelBufferPool: CVPixelBufferPool?
    private var poolWidth: Int32 = 0
    private var poolHeight: Int32 = 0
    
    init(maxDuration: TimeInterval = 4.0) {
        self.maxDuration = maxDuration
    }
    
    func append(_ sampleBuffer: CMSampleBuffer) {
        // Copy the pixel buffer synchronously before the sample buffer is recycled
        guard let sourcePixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        
        // Copy pixel buffer to our own buffer
        guard let copiedBuffer = copyPixelBuffer(sourcePixelBuffer) else {
            print("⚠️ RingBuffer: Failed to copy pixel buffer")
            return
        }
        
        let frame = CapturedFrame(pixelBuffer: copiedBuffer, presentationTime: presentationTime)
        
        queue.async {
            self.frames.append(frame)
            self.trim()
        }
    }
    
    private func copyPixelBuffer(_ source: CVPixelBuffer) -> CVPixelBuffer? {
        let width = CVPixelBufferGetWidth(source)
        let height = CVPixelBufferGetHeight(source)
        let pixelFormat = CVPixelBufferGetPixelFormatType(source)
        
        // Create or update pool if dimensions changed
        if pixelBufferPool == nil || poolWidth != Int32(width) || poolHeight != Int32(height) {
            createPixelBufferPool(width: width, height: height, pixelFormat: pixelFormat)
            poolWidth = Int32(width)
            poolHeight = Int32(height)
        }
        
        var destinationBuffer: CVPixelBuffer?
        
        if let pool = pixelBufferPool {
            let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &destinationBuffer)
            if status != kCVReturnSuccess {
                print("⚠️ RingBuffer: Pool allocation failed, creating standalone buffer")
                destinationBuffer = nil
            }
        }
        
        // Fallback to standalone allocation if pool failed
        if destinationBuffer == nil {
            let attributes: [String: Any] = [
                kCVPixelBufferCGImageCompatibilityKey as String: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
            ]
            let status = CVPixelBufferCreate(
                nil,
                width,
                height,
                pixelFormat,
                attributes as CFDictionary,
                &destinationBuffer
            )
            if status != kCVReturnSuccess {
                return nil
            }
        }
        
        guard let dest = destinationBuffer else { return nil }
        
        // Lock and copy
        CVPixelBufferLockBaseAddress(source, .readOnly)
        CVPixelBufferLockBaseAddress(dest, [])
        defer {
            CVPixelBufferUnlockBaseAddress(source, .readOnly)
            CVPixelBufferUnlockBaseAddress(dest, [])
        }
        
        // Copy plane by plane
        let planeCount = CVPixelBufferGetPlaneCount(source)
        if planeCount == 0 {
            // Non-planar format
            if let srcBase = CVPixelBufferGetBaseAddress(source),
               let dstBase = CVPixelBufferGetBaseAddress(dest) {
                let bytesPerRow = CVPixelBufferGetBytesPerRow(source)
                memcpy(dstBase, srcBase, bytesPerRow * height)
            }
        } else {
            // Planar format (e.g., YUV)
            for plane in 0..<planeCount {
                if let srcBase = CVPixelBufferGetBaseAddressOfPlane(source, plane),
                   let dstBase = CVPixelBufferGetBaseAddressOfPlane(dest, plane) {
                    let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(source, plane)
                    let planeHeight = CVPixelBufferGetHeightOfPlane(source, plane)
                    memcpy(dstBase, srcBase, bytesPerRow * planeHeight)
                }
            }
        }
        
        return dest
    }
    
    private func createPixelBufferPool(width: Int, height: Int, pixelFormat: OSType) {
        let poolAttributes: [String: Any] = [
            kCVPixelBufferPoolMinimumBufferCountKey as String: 120 // ~4 seconds at 30fps
        ]
        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferPixelFormatTypeKey as String: pixelFormat,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        
        CVPixelBufferPoolCreate(
            nil,
            poolAttributes as CFDictionary,
            pixelBufferAttributes as CFDictionary,
            &pixelBufferPool
        )
    }
    
    private func trim() {
        guard let lastFrame = frames.last,
              let firstFrame = frames.first else { return }
        
        let lastTime = CMTimeGetSeconds(lastFrame.presentationTime)
        let firstTime = CMTimeGetSeconds(firstFrame.presentationTime)
        
        if (lastTime - firstTime) > maxDuration {
            frames.removeFirst()
            trim()
        }
    }
    
    func save(to url: URL, completion: @escaping (Result<URL, Error>) -> Void) {
        queue.async {
            guard !self.frames.isEmpty else {
                completion(.failure(NSError(domain: "RingBuffer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Buffer empty"])))
                return
            }
            
            print("💾 RingBuffer: Saving \(self.frames.count) frames...")
            
            do {
                // Remove existing file if present
                try? FileManager.default.removeItem(at: url)
                
                let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
                
                let firstFrame = self.frames[0]
                let width = CVPixelBufferGetWidth(firstFrame.pixelBuffer)
                let height = CVPixelBufferGetHeight(firstFrame.pixelBuffer)
                
                let videoSettings: [String: Any] = [
                    AVVideoCodecKey: AVVideoCodecType.h264,
                    AVVideoWidthKey: width,
                    AVVideoHeightKey: height
                ]
                
                let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
                input.expectsMediaDataInRealTime = false
                
                let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                    assetWriterInput: input,
                    sourcePixelBufferAttributes: nil
                )
                
                guard writer.canAdd(input) else {
                    completion(.failure(NSError(domain: "RingBuffer", code: -4, userInfo: [NSLocalizedDescriptionKey: "Cannot add input"])))
                    return
                }
                
                writer.add(input)
                writer.startWriting()
                writer.startSession(atSourceTime: firstFrame.presentationTime)
                
                for frame in self.frames {
                    while !input.isReadyForMoreMediaData {
                        Thread.sleep(forTimeInterval: 0.001)
                    }
                    adaptor.append(frame.pixelBuffer, withPresentationTime: frame.presentationTime)
                }
                
                input.markAsFinished()
                writer.finishWriting {
                    if writer.status == .completed {
                        print("✅ RingBuffer: Saved \(self.frames.count) frames to \(url.lastPathComponent)")
                        completion(.success(url))
                    } else {
                        let error = writer.error ?? NSError(domain: "RingBuffer", code: -3, userInfo: [NSLocalizedDescriptionKey: "Writer failed"])
                        print("❌ RingBuffer: Write failed - \(error)")
                        completion(.failure(error))
                    }
                }
                
            } catch {
                print("❌ RingBuffer: Exception - \(error)")
                completion(.failure(error))
            }
        }
    }
    
    func clear() {
        queue.async {
            self.frames.removeAll()
        }
    }
    
    var frameCount: Int {
        var count = 0
        queue.sync {
            count = frames.count
        }
        return count
    }
}

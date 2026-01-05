# SwingSync 🏌️

**The AI Golf Coach** - Real-time golf swing analysis powered by MediaPipe pose detection.

![iOS 17.0+](https://img.shields.io/badge/iOS-17.0+-blue.svg)
![Swift 5](https://img.shields.io/badge/Swift-5-orange.svg)
![License](https://img.shields.io/badge/License-MIT-green.svg)

## Overview

SwingSync uses computer vision to capture and analyze your golf swing in real-time. The app detects your body pose using MediaPipe, tracks swing phases, and automatically saves swing videos to your Photos library for review.

## Features

- **📷 Real-Time Pose Detection** - MediaPipe Pose Landmarker tracks 33 body landmarks at 30fps
- **🦴 Skeleton Overlay** - Visual skeleton rendered on the camera feed
- **🎯 Automatic Swing Detection** - Detects golf address position and swing phases
- **📹 Video Capture** - Automatically saves 4-second swing clips when a swing is detected
- **💾 Photos Integration** - Videos saved directly to your Photo Library with friendly names
- **✨ Beautiful UI** - Animated splash screen and delightful save confirmation

## Swing Detection Phases

The app recognizes these swing stages:
1. **Idle** - Waiting for golfer to take position
2. **Address** - Golfer is in stance, holding still
3. **Backswing** - Club going back
4. **Downswing** - Club coming through
5. **Finish** - Swing complete, video saved

## Architecture

```
SwingSync/
├── SwingSyncApp.swift          # App entry point
├── Views/
│   ├── SplashView.swift        # Animated launch screen
│   ├── CameraView.swift        # Main camera + skeleton overlay
│   ├── SkeletonOverlay.swift   # Pose visualization
│   └── SwingSavedView.swift    # Save confirmation UI
├── Services/
│   ├── CameraService.swift     # AVCapture session management
│   ├── SwingLogic.swift        # Swing phase state machine
│   └── RingBuffer.swift        # Rolling video frame buffer
├── Vision/
│   └── PoseDetector.swift      # MediaPipe pose detection
└── pose_landmarker.task        # MediaPipe model file
```

## Requirements

- iOS 17.0+
- Xcode 15+
- CocoaPods
- Physical iPhone (camera required)

## Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/arundas0/PerfectSwing.git
   cd PerfectSwing
   ```

2. **Install dependencies**
   ```bash
   pod install
   ```

3. **Generate Xcode project** (if using XcodeGen)
   ```bash
   xcodegen generate
   pod install
   ```

4. **Open the workspace**
   ```bash
   open SwingSync.xcworkspace
   ```

5. **Build and run** on a physical device

## Dependencies

- **[MediaPipeTasksVision](https://developers.google.com/mediapipe)** - On-device pose detection

## Permissions

The app requires:
- **Camera** - To capture video and detect poses
- **Photos** - To save swing videos to your library

## How It Works

1. **Camera captures frames** → sent to PoseDetector
2. **MediaPipe analyzes each frame** → extracts 33 body landmarks
3. **SwingLogic processes landmarks** → detects swing phases
4. **RingBuffer stores last 4 seconds** → rolling video buffer
5. **On swing detection** → saves video to Photos

## Configuration

Key parameters in `SwingLogic.swift`:
```swift
addressThreshold = 45    // Frames to hold still (~1.5s at 30fps)
steadyThreshold = 0.10   // Max jitter allowed
backswingTrigger = 0.15  // Wrist movement to trigger backswing
```

## Future Roadmap

- [ ] AI swing analysis with Gemini Vision
- [ ] Swing phase annotations on video
- [ ] Technique tips and feedback
- [ ] Comparison with pro swings
- [ ] Swing history and progress tracking

## License

MIT License - see [LICENSE](LICENSE) for details.

## Author

 [Arun Das](https://github.com/arundas0)

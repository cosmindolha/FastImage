# FastImage

FastImage is a tiny native SwiftUI image viewer for macOS. It opens images quickly, keeps the interface out of the way, and has no third-party dependencies.

<img src="FastImage app.jpg" width="512" alt="FastImage app screenshot"/>

## Features

- Sony RAW (`.arw`) support
- Standard image formats supported by macOS, including JPEG, PNG, TIFF, HEIC, GIF, BMP, and WebP
- Open from Finder or drag and drop into the window
- Browse every supported image in the current folder with the left and right arrow keys
- Zoom, pan, and double-click to reset the view
- Background image decoding and folder scanning keep the interface responsive
- Strict three-image cache keeps navigation fast without letting memory usage drift upward

## Sony RAW support

Sony `.arw` files are decoded with Apple's built-in ImageIO framework. FastImage uses the camera's embedded preview when available, so a large RAW file opens quickly without bundling a heavyweight RAW library or performing a full-resolution demosaic just to fit the image on screen.

This is intentionally a fast viewing path, not a RAW development or editing pipeline.

## Controls

- `Left Arrow` / `Right Arrow`: previous or next image
- Zoom slider: change image size
- `Space`: switch between hand and scroll-wheel zoom modes
- Drag: pan a zoomed image
- Double-click: reset zoom and position

## Requirements

- macOS 13 or newer
- Xcode 14 or newer to build from source

## Build

Open `FastImage.xcodeproj` in Xcode and build the `FastImage` scheme. The project uses only macOS system frameworks.

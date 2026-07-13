# FastImage

FastImage is a tiny native SwiftUI image viewer for macOS. It opens images quickly, keeps the interface out of the way, and has no third-party dependencies.

<img src="FastImage app.jpg" width="512" alt="FastImage app screenshot"/>

## Features

- Sony RAW (`.arw`) support
- Standard image formats supported by macOS, including JPEG, PNG, TIFF, HEIC, GIF, BMP, and WebP
- Open from Finder or drag and drop into the window
- Browse every supported image in the current folder with the left and right arrow keys
- Point-anchored mouse-wheel zoom, direct mouse dragging, and double-click fit-to-window
- Lightweight crop tool with draggable edge/corner handles and rule-of-thirds guides
- One-command overwrite save for writable image formats
- Background image decoding and folder scanning keep the interface responsive
- Strict three-image cache keeps navigation fast without letting memory usage drift upward

## Sony RAW support

Sony `.arw` files are decoded with Apple's built-in ImageIO framework. FastImage uses the camera's embedded preview when available, so a large RAW file opens quickly without bundling a heavyweight RAW library or performing a full-resolution demosaic just to fit the image on screen.

This is intentionally a fast viewing path, not a RAW development or editing pipeline. Sony RAW files are read-only in FastImage; replacing an `.arw` with its embedded preview would destroy the original RAW data.

## Crop and save

Press `K` to enter crop mode. Drag any edge or corner handle, drag inside the selection to move it, or drag outside it to draw a new selection. Press `Enter` to apply the crop or `Esc` to cancel it.

The toolbar save button and `Command-S` atomically overwrite the original writable image without a confirmation dialog. The edited image is encoded in its original file format.

## Controls

- `Left Arrow` / `Right Arrow`: previous or next image
- Click an image point, then use the mouse wheel: zoom around that point
- Drag: pan the image at any zoom level
- Double-click: fit the image to the window
- `K`: enter or cancel crop mode
- `Enter`: apply the crop
- `Esc`: cancel the crop
- `Command-S`: overwrite the original image with applied edits

## Requirements

- macOS 13 or newer
- Xcode 14 or newer to build from source

## Build

Open `FastImage.xcodeproj` in Xcode and build the `FastImage` scheme. The project uses only macOS system frameworks.

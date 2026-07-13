//  Created by Cosmin Dolha on 22.10.2022.
import AppKit
import Combine
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

private enum ImageSupport {
    private static let writableTypeIdentifiers = Set(
        CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
    )

    static func supports(_ url: URL) -> Bool {
        guard url.isFileURL,
              let type = UTType(filenameExtension: url.pathExtension) else {
            return false
        }
        return type.conforms(to: .image)
    }

    static func isCameraRaw(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .rawImage) == true
    }

    static func canWrite(_ url: URL) -> Bool {
        guard !isCameraRaw(url),
              let type = UTType(filenameExtension: url.pathExtension) else {
            return false
        }
        return writableTypeIdentifiers.contains(type.identifier)
    }

    static func images(in directory: URL) -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isReadableKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return urls
            .filter { url in
                let values = try? url.resourceValues(forKeys: Set(keys))
                return values?.isRegularFile != false
                    && values?.isReadable != false
                    && supports(url)
            }
            .sorted {
                $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
            }
    }
}

final class ImageLoader: ObservableObject {
    @Published private(set) var image: NSImage?
    @Published private(set) var failedFilename: String?
    @Published private(set) var hasUnsavedChanges = false
    @Published private(set) var isSaving = false
    @Published private(set) var saveErrorMessage: String?

    private let decodeQueue = DispatchQueue(label: "com.cosmindolha.FastImage.decode", qos: .userInitiated)
    private let requestLock = NSLock()
    private let cacheLock = NSLock()
    private var requestGeneration = 0
    private var imageCache: [URL: NSImage] = [:]
    private var cacheOrder: [URL] = []
    private let cacheCountLimit = 3
    private var displayedURL: URL?

    func load(_ url: URL) {
        let generation = beginRequest()
        displayedURL = url
        failedFilename = nil
        hasUnsavedChanges = false
        saveErrorMessage = nil

        if let cachedImage = cachedImage(for: url) {
            image = cachedImage
            return
        }

        decodeQueue.async { [weak self] in
            guard let self, self.isCurrent(generation) else { return }

            let decodedImage = autoreleasepool {
                Self.decode(url)
            }
            if let decodedImage {
                self.storeInCache(decodedImage, for: url)
            }

            guard self.isCurrent(generation) else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isCurrent(generation) else { return }
                self.image = decodedImage
                self.failedFilename = decodedImage == nil ? url.lastPathComponent : nil
            }
        }
    }

    func display(_ droppedImage: NSImage) {
        _ = beginRequest()
        displayedURL = nil
        image = droppedImage
        failedFilename = nil
        hasUnsavedChanges = false
        saveErrorMessage = nil
    }

    func reportUnsupported(_ url: URL) {
        _ = beginRequest()
        displayedURL = nil
        image = nil
        failedFilename = url.lastPathComponent
        hasUnsavedChanges = false
        saveErrorMessage = nil
    }

    @discardableResult
    func crop(to normalizedRect: CGRect) -> Bool {
        guard let image,
              let cgImage = Self.cgImage(from: image) else {
            return false
        }

        let rect = normalizedRect.standardized.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard rect.width > 0, rect.height > 0 else { return false }

        let minX = max(0, floor(rect.minX * CGFloat(cgImage.width)))
        let minY = max(0, floor(rect.minY * CGFloat(cgImage.height)))
        let maxX = min(CGFloat(cgImage.width), ceil(rect.maxX * CGFloat(cgImage.width)))
        let maxY = min(CGFloat(cgImage.height), ceil(rect.maxY * CGFloat(cgImage.height)))
        let pixelRect = CGRect(
            x: minX,
            y: minY,
            width: maxX - minX,
            height: maxY - minY
        )

        guard pixelRect.width >= 1,
              pixelRect.height >= 1,
              let croppedImage = cgImage.cropping(to: pixelRect) else {
            return false
        }

        self.image = NSImage(
            cgImage: croppedImage,
            size: NSSize(width: croppedImage.width, height: croppedImage.height)
        )
        hasUnsavedChanges = true
        saveErrorMessage = nil
        return true
    }

    func save(to url: URL) {
        guard !isSaving,
              displayedURL == url,
              ImageSupport.canWrite(url),
              let image,
              let cgImage = Self.cgImage(from: image) else {
            return
        }

        isSaving = true
        saveErrorMessage = nil

        decodeQueue.async { [weak self] in
            let didSave = Self.write(cgImage, to: url)

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isSaving = false

                if didSave {
                    self.storeInCache(image, for: url)
                    if self.displayedURL == url, self.image === image {
                        self.hasUnsavedChanges = false
                    }
                } else if self.displayedURL == url {
                    self.saveErrorMessage = "Couldn’t overwrite \(url.lastPathComponent)"
                }
            }
        }
    }

    private func beginRequest() -> Int {
        requestLock.lock()
        defer { requestLock.unlock() }
        requestGeneration += 1
        return requestGeneration
    }

    private func isCurrent(_ generation: Int) -> Bool {
        requestLock.lock()
        defer { requestLock.unlock() }
        return requestGeneration == generation
    }

    private func cachedImage(for url: URL) -> NSImage? {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        guard let cachedImage = imageCache[url] else { return nil }
        cacheOrder.removeAll { $0 == url }
        cacheOrder.append(url)
        return cachedImage
    }

    private func storeInCache(_ image: NSImage, for url: URL) {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        imageCache[url] = image
        cacheOrder.removeAll { $0 == url }
        cacheOrder.append(url)

        while cacheOrder.count > cacheCountLimit {
            imageCache.removeValue(forKey: cacheOrder.removeFirst())
        }
    }

    private static func decode(_ url: URL) -> NSImage? {
        let hasSecurityAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard ImageSupport.isCameraRaw(url) else {
            return NSImage(contentsOf: url)
        }

        let sourceOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: false
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions as CFDictionary) else {
            return nil
        }

        // Camera RAW files usually contain a camera-rendered JPEG preview. ImageIO uses it
        // first and only renders the RAW data when a preview is absent, keeping open time low.
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 4096,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            thumbnailOptions as CFDictionary
        ) else {
            return nil
        }

        return NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height)
        )
    }

    private static func cgImage(from image: NSImage) -> CGImage? {
        var proposedRect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil)
    }

    private static func write(_ image: CGImage, to url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension),
              ImageSupport.canWrite(url) else {
            return false
        }

        let hasSecurityAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let temporaryURL = url.deletingLastPathComponent().appendingPathComponent(
            ".\(url.lastPathComponent).fastimage-\(UUID().uuidString).tmp"
        )
        defer {
            try? FileManager.default.removeItem(at: temporaryURL)
        }

        guard let destination = CGImageDestinationCreateWithURL(
            temporaryURL as CFURL,
            type.identifier as CFString,
            1,
            nil
        ) else {
            return false
        }

        let properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 1.0
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return false }

        do {
            _ = try FileManager.default.replaceItemAt(
                url,
                withItemAt: temporaryURL,
                backupItemName: nil,
                options: []
            )
            return true
        } catch {
            return false
        }
    }
}

struct ContentView: View, DropDelegate {
    @StateObject private var imageLoader = ImageLoader()
    @State private var colorRectBorder: Color = .gray
    @State private var imagesInDirectory: [URL] = []
    @State private var imageIterator = 0
    @State private var currentImageURL: URL?
    @State private var geometrySize: CGSize = .zero
    @State private var zoomScale: CGFloat = 1
    @State private var zoomAnchorInImage: UnitPoint?
    @State private var imageOffset: CGSize = .zero
    @State private var dragTranslation: CGSize = .zero
    @State private var isCropping = false
    @State private var cropRect = CGRect(x: 0.05, y: 0.05, width: 0.9, height: 0.9)

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Rectangle()
                    .foregroundColor(Color.black.opacity(0.1))
                    .border(colorRectBorder.opacity(0.1), width: 3)

                if let image = imageLoader.image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(
                            width: max(1, geometry.size.width),
                            height: max(1, geometry.size.height)
                        )
                        .scaleEffect(zoomScale)
                        .offset(
                            x: imageOffset.width + dragTranslation.width,
                            y: imageOffset.height + dragTranslation.height
                        )
                        .allowsHitTesting(false)

                    if isCropping {
                        CropOverlayView(
                            cropRect: $cropRect,
                            imageRect: displayedImageRect(for: image, in: geometry.size)
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        CanvasInteractionView(
                            onClick: { point in
                                setZoomAnchor(at: point, for: image)
                            },
                            onDoubleClick: {
                                resetView(to: geometry.size)
                            },
                            onDragChanged: { translation in
                                dragTranslation = translation
                            },
                            onDragEnded: { translation in
                                imageOffset = CGSize(
                                    width: imageOffset.width + translation.width,
                                    height: imageOffset.height + translation.height
                                )
                                dragTranslation = .zero
                            },
                            onScroll: { deltaY, hasPreciseDeltas in
                                zoom(
                                    by: deltaY,
                                    hasPreciseDeltas: hasPreciseDeltas,
                                    image: image
                                )
                            }
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else if let failedFilename = imageLoader.failedFilename {
                    Text("Couldn’t open \(failedFilename)")
                        .foregroundStyle(.secondary)
                }

                if let saveErrorMessage = imageLoader.saveErrorMessage {
                    VStack {
                        Spacer()
                        Text(saveErrorMessage)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.regularMaterial, in: Capsule())
                            .padding()
                    }
                    .allowsHitTesting(false)
                }
            }
            .clipped()
            .onAppear {
                geometrySize = geometry.size
            }
            .onOpenURL { url in
                openImage(at: url)
            }
            .onDrop(of: [.fileURL, .image], delegate: self)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: showPreviousImage) {
                        Image(systemName: "chevron.left")
                    }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                    .disabled(imagesInDirectory.count < 2)
                }

                ToolbarItem(placement: .primaryAction) {
                    Button(action: showNextImage) {
                        Image(systemName: "chevron.right")
                    }
                    .keyboardShortcut(.rightArrow, modifiers: [])
                    .disabled(imagesInDirectory.count < 2)
                }

                ToolbarItem(placement: .primaryAction) {
                    Button(action: toggleCrop) {
                        Image(systemName: "crop")
                    }
                    .help(isCropping ? "Cancel Crop (K)" : "Crop (K)")
                    .disabled(!canCropCurrentImage && !isCropping)
                }

                if isCropping {
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: cancelCrop) {
                            Image(systemName: "xmark")
                        }
                        .help("Cancel Crop (Esc)")
                    }

                    ToolbarItem(placement: .primaryAction) {
                        Button(action: applyCrop) {
                            Image(systemName: "checkmark")
                        }
                        .help("Apply Crop (Enter)")
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button(action: saveCurrentImage) {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .help("Save and Overwrite (Command-S)")
                    .disabled(!canSaveCurrentImage)
                }
            }
            .onChange(of: geometry.size) { newSize in
                geometrySize = newSize
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .fastImageSave)) { _ in
            saveCurrentImage()
        }
        .onReceive(NotificationCenter.default.publisher(for: .fastImageToggleCrop)) { _ in
            toggleCrop()
        }
        .onReceive(NotificationCenter.default.publisher(for: .fastImageApplyCrop)) { _ in
            applyCrop()
        }
        .onReceive(NotificationCenter.default.publisher(for: .fastImageCancelCrop)) { _ in
            cancelCrop()
        }
    }

    private var canCropCurrentImage: Bool {
        guard imageLoader.image != nil,
              !imageLoader.isSaving,
              let currentImageURL else {
            return false
        }
        return ImageSupport.canWrite(currentImageURL)
    }

    private var canSaveCurrentImage: Bool {
        canCropCurrentImage
            && imageLoader.hasUnsavedChanges
            && !isCropping
    }

    private func showPreviousImage() {
        navigate(by: -1)
    }

    private func showNextImage() {
        navigate(by: 1)
    }

    private func navigate(by change: Int) {
        guard !imagesInDirectory.isEmpty else { return }

        let currentIndex = currentImageURL.flatMap { imagesInDirectory.firstIndex(of: $0) } ?? imageIterator
        imageIterator = (currentIndex + change + imagesInDirectory.count) % imagesInDirectory.count
        displayImage(at: imagesInDirectory[imageIterator])
    }

    private func openImage(at url: URL) {
        let imageURL = url.standardizedFileURL
        guard ImageSupport.supports(imageURL) else {
            isCropping = false
            imageLoader.reportUnsupported(imageURL)
            return
        }

        displayImage(at: imageURL)
        scanDirectory(containing: imageURL)
    }

    private func displayImage(at url: URL) {
        isCropping = false
        currentImageURL = url
        resetView(to: geometrySize)
        imageLoader.load(url)
    }

    private func scanDirectory(containing openedURL: URL) {
        let directory = openedURL.deletingLastPathComponent()
        DispatchQueue.global(qos: .utility).async {
            var imageURLs = ImageSupport.images(in: directory)
            if !imageURLs.contains(openedURL) {
                imageURLs.append(openedURL)
                imageURLs.sort {
                    $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
                }
            }

            DispatchQueue.main.async {
                guard currentImageURL == openedURL else { return }
                imagesInDirectory = imageURLs
                imageIterator = imageURLs.firstIndex(of: openedURL) ?? 0
            }
        }
    }

    private func resetView(to size: CGSize) {
        geometrySize = size
        zoomScale = 1
        zoomAnchorInImage = nil
        imageOffset = .zero
        dragTranslation = .zero
    }

    private func toggleCrop() {
        if isCropping {
            cancelCrop()
        } else {
            beginCrop()
        }
    }

    private func beginCrop() {
        guard canCropCurrentImage else { return }
        resetView(to: geometrySize)
        cropRect = CGRect(x: 0.05, y: 0.05, width: 0.9, height: 0.9)
        isCropping = true
    }

    private func cancelCrop() {
        isCropping = false
    }

    private func applyCrop() {
        guard isCropping,
              imageLoader.crop(to: cropRect) else {
            return
        }
        isCropping = false
        resetView(to: geometrySize)
    }

    private func saveCurrentImage() {
        guard canSaveCurrentImage, let currentImageURL else { return }
        imageLoader.save(to: currentImageURL)
    }

    private func setZoomAnchor(at point: CGPoint, for image: NSImage) {
        guard let fittedSize = fittedImageSize(for: image, in: geometrySize) else { return }

        let displayedOffset = CGSize(
            width: imageOffset.width + dragTranslation.width,
            height: imageOffset.height + dragTranslation.height
        )
        let center = CGPoint(x: geometrySize.width / 2, y: geometrySize.height / 2)
        let pointInFittedImage = CGPoint(
            x: (point.x - center.x - displayedOffset.width) / zoomScale + fittedSize.width / 2,
            y: (point.y - center.y - displayedOffset.height) / zoomScale + fittedSize.height / 2
        )

        guard pointInFittedImage.x >= 0,
              pointInFittedImage.x <= fittedSize.width,
              pointInFittedImage.y >= 0,
              pointInFittedImage.y <= fittedSize.height else {
            return
        }

        zoomAnchorInImage = UnitPoint(
            x: pointInFittedImage.x / fittedSize.width,
            y: pointInFittedImage.y / fittedSize.height
        )
    }

    private func zoom(by deltaY: CGFloat, hasPreciseDeltas: Bool, image: NSImage) {
        guard deltaY != 0,
              zoomScale > 0,
              let fittedSize = fittedImageSize(for: image, in: geometrySize) else {
            return
        }

        let sensitivity: CGFloat = hasPreciseDeltas ? 0.012 : 0.12
        let boundedDelta = min(max(deltaY, -20), 20)
        let scaleFactor = CGFloat(exp(Double(boundedDelta * sensitivity)))
        let newScale = min(max(zoomScale * scaleFactor, 0.1), 32)
        guard newScale != zoomScale else { return }

        let displayedOffset = CGSize(
            width: imageOffset.width + dragTranslation.width,
            height: imageOffset.height + dragTranslation.height
        )
        let anchorVector: CGSize
        if let zoomAnchorInImage {
            anchorVector = CGSize(
                width: (zoomAnchorInImage.x - 0.5) * fittedSize.width,
                height: (zoomAnchorInImage.y - 0.5) * fittedSize.height
            )
        } else {
            // Until the user selects an image point, keep the viewport center fixed.
            anchorVector = CGSize(
                width: -displayedOffset.width / zoomScale,
                height: -displayedOffset.height / zoomScale
            )
        }

        let scaleDifference = zoomScale - newScale
        let zoomedDisplayedOffset = CGSize(
            width: displayedOffset.width + scaleDifference * anchorVector.width,
            height: displayedOffset.height + scaleDifference * anchorVector.height
        )
        imageOffset = CGSize(
            width: zoomedDisplayedOffset.width - dragTranslation.width,
            height: zoomedDisplayedOffset.height - dragTranslation.height
        )
        zoomScale = newScale
    }

    private func fittedImageSize(for image: NSImage, in viewport: CGSize) -> CGSize? {
        guard image.size.width > 0,
              image.size.height > 0,
              viewport.width > 0,
              viewport.height > 0 else {
            return nil
        }

        let fitScale = min(
            viewport.width / image.size.width,
            viewport.height / image.size.height
        )
        return CGSize(
            width: image.size.width * fitScale,
            height: image.size.height * fitScale
        )
    }

    private func displayedImageRect(for image: NSImage, in viewport: CGSize) -> CGRect {
        guard let fittedSize = fittedImageSize(for: image, in: viewport) else {
            return .zero
        }

        let displayedSize = CGSize(
            width: fittedSize.width * zoomScale,
            height: fittedSize.height * zoomScale
        )
        let displayedOffset = CGSize(
            width: imageOffset.width + dragTranslation.width,
            height: imageOffset.height + dragTranslation.height
        )
        return CGRect(
            x: (viewport.width - displayedSize.width) / 2 + displayedOffset.width,
            y: (viewport.height - displayedSize.height) / 2 + displayedOffset.height,
            width: displayedSize.width,
            height: displayedSize.height
        )
    }

    func performDrop(info: DropInfo) -> Bool {
        colorRectBorder = .gray

        if let provider = info.itemProviders(for: [.fileURL]).first {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                DispatchQueue.main.async {
                    openImage(at: url)
                }
            }
            return true
        }

        guard let provider = info.itemProviders(for: [.image]).first,
              let typeIdentifier = provider.registeredTypeIdentifiers.first(where: {
                  UTType($0)?.conforms(to: .image) == true
              }) else {
            return false
        }

        provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, _ in
            guard let data else { return }
            DispatchQueue.global(qos: .userInitiated).async {
                guard let droppedImage = NSImage(data: data) else { return }
                DispatchQueue.main.async {
                    imagesInDirectory = []
                    currentImageURL = nil
                    imageIterator = 0
                    isCropping = false
                    resetView(to: geometrySize)
                    imageLoader.display(droppedImage)
                }
            }
        }
        return true
    }

    func validateDrop(info: DropInfo) -> Bool {
        !info.itemProviders(for: [.fileURL, .image]).isEmpty
    }

    func dropEntered(info: DropInfo) {
        colorRectBorder = .white
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .copy)
    }

    func dropExited(info: DropInfo) {
        colorRectBorder = .gray
    }
}

private struct CanvasInteractionView: NSViewRepresentable {
    let onClick: (CGPoint) -> Void
    let onDoubleClick: () -> Void
    let onDragChanged: (CGSize) -> Void
    let onDragEnded: (CGSize) -> Void
    let onScroll: (CGFloat, Bool) -> Void

    func makeNSView(context: Context) -> InteractionNSView {
        let view = InteractionNSView()
        configure(view)
        return view
    }

    func updateNSView(_ nsView: InteractionNSView, context: Context) {
        configure(nsView)
    }

    private func configure(_ view: InteractionNSView) {
        view.onClick = onClick
        view.onDoubleClick = onDoubleClick
        view.onDragChanged = onDragChanged
        view.onDragEnded = onDragEnded
        view.onScroll = onScroll
    }

    final class InteractionNSView: NSView {
        var onClick: (CGPoint) -> Void = { _ in }
        var onDoubleClick: () -> Void = { }
        var onDragChanged: (CGSize) -> Void = { _ in }
        var onDragEnded: (CGSize) -> Void = { _ in }
        var onScroll: (CGFloat, Bool) -> Void = { _, _ in }

        private var dragOrigin: CGPoint?
        private var isHandlingDoubleClick = false

        override var isFlipped: Bool { true }
        override var acceptsFirstResponder: Bool { true }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
        }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .openHand)
        }

        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)

            if event.clickCount >= 2 {
                dragOrigin = nil
                isHandlingDoubleClick = true
                onDragChanged(.zero)
                onDoubleClick()
                return
            }

            isHandlingDoubleClick = false
            dragOrigin = convert(event.locationInWindow, from: nil)
            onDragChanged(.zero)
        }

        override func mouseDragged(with event: NSEvent) {
            guard !isHandlingDoubleClick, let dragOrigin else { return }
            onDragChanged(translation(from: dragOrigin, to: event))
        }

        override func mouseUp(with event: NSEvent) {
            guard !isHandlingDoubleClick, let dragOrigin else {
                isHandlingDoubleClick = false
                return
            }

            let location = convert(event.locationInWindow, from: nil)
            let translation = CGSize(
                width: location.x - dragOrigin.x,
                height: location.y - dragOrigin.y
            )
            self.dragOrigin = nil

            if hypot(translation.width, translation.height) < 3 {
                onDragEnded(.zero)
                onClick(location)
            } else {
                onDragEnded(translation)
            }
        }

        override func scrollWheel(with event: NSEvent) {
            onScroll(event.scrollingDeltaY, event.hasPreciseScrollingDeltas)
        }

        private func translation(from origin: CGPoint, to event: NSEvent) -> CGSize {
            let location = convert(event.locationInWindow, from: nil)
            return CGSize(
                width: location.x - origin.x,
                height: location.y - origin.y
            )
        }
    }
}

private struct CropOverlayView: NSViewRepresentable {
    @Binding var cropRect: CGRect
    let imageRect: CGRect

    func makeNSView(context: Context) -> CropNSView {
        let view = CropNSView()
        configure(view)
        return view
    }

    func updateNSView(_ nsView: CropNSView, context: Context) {
        configure(nsView)
    }

    private func configure(_ view: CropNSView) {
        view.cropRect = cropRect
        view.imageRect = imageRect
        view.onCropChanged = { cropRect = $0 }
        view.needsDisplay = true
        view.window?.invalidateCursorRects(for: view)
    }

    final class CropNSView: NSView {
        var cropRect = CGRect(x: 0.05, y: 0.05, width: 0.9, height: 0.9)
        var imageRect = CGRect.zero
        var onCropChanged: (CGRect) -> Void = { _ in }

        private var dragTarget: DragTarget?
        private var dragOrigin = CGPoint.zero
        private var initialCropRect = CGRect.zero

        override var isFlipped: Bool { true }
        override var acceptsFirstResponder: Bool { true }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
        }

        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)
            guard imageRect.width > 0, imageRect.height > 0 else { return }

            let cropRectOnScreen = screenRect(for: cropRect)
            let shade = NSBezierPath(rect: bounds)
            shade.append(NSBezierPath(rect: cropRectOnScreen))
            shade.windingRule = .evenOdd
            NSColor.black.withAlphaComponent(0.52).setFill()
            shade.fill()

            NSColor.white.setStroke()
            let border = NSBezierPath(rect: cropRectOnScreen.insetBy(dx: 0.5, dy: 0.5))
            border.lineWidth = 1
            border.stroke()

            drawGrid(in: cropRectOnScreen)
            drawHandles(in: cropRectOnScreen)
        }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .crosshair)
            addCursorRect(screenRect(for: cropRect), cursor: .openHand)
        }

        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
            let location = convert(event.locationInWindow, from: nil)
            let cropRectOnScreen = screenRect(for: cropRect)

            dragTarget = DragTarget.resizeTargets.first {
                hitRect(for: $0, in: cropRectOnScreen).contains(location)
            }
            if dragTarget == nil, cropRectOnScreen.contains(location) {
                dragTarget = .move
            }
            if dragTarget == nil, imageRect.contains(location) {
                dragTarget = .create
            }

            guard dragTarget != nil else { return }
            dragOrigin = location
            initialCropRect = cropRect
        }

        override func mouseDragged(with event: NSEvent) {
            guard let dragTarget,
                  imageRect.width > 0,
                  imageRect.height > 0 else {
                return
            }

            let location = convert(event.locationInWindow, from: nil)
            let delta = CGSize(
                width: (location.x - dragOrigin.x) / imageRect.width,
                height: (location.y - dragOrigin.y) / imageRect.height
            )
            let minimumSize = CGSize(
                width: min(0.25, max(0.005, 12 / imageRect.width)),
                height: min(0.25, max(0.005, 12 / imageRect.height))
            )

            let updatedRect: CGRect
            switch dragTarget {
            case .move:
                updatedRect = movedRect(by: delta)
            case .create:
                updatedRect = createdRect(to: location, minimumSize: minimumSize)
            default:
                updatedRect = resizedRect(
                    for: dragTarget,
                    by: delta,
                    minimumSize: minimumSize
                )
            }
            onCropChanged(updatedRect)
        }

        override func mouseUp(with event: NSEvent) {
            dragTarget = nil
        }

        private func movedRect(by delta: CGSize) -> CGRect {
            CGRect(
                x: min(max(initialCropRect.minX + delta.width, 0), 1 - initialCropRect.width),
                y: min(max(initialCropRect.minY + delta.height, 0), 1 - initialCropRect.height),
                width: initialCropRect.width,
                height: initialCropRect.height
            )
        }

        private func createdRect(to location: CGPoint, minimumSize: CGSize) -> CGRect {
            let origin = normalizedPoint(dragOrigin)
            let current = normalizedPoint(location)
            var minX = min(origin.x, current.x)
            var maxX = max(origin.x, current.x)
            var minY = min(origin.y, current.y)
            var maxY = max(origin.y, current.y)

            if maxX - minX < minimumSize.width {
                maxX = min(1, minX + minimumSize.width)
                minX = max(0, maxX - minimumSize.width)
            }
            if maxY - minY < minimumSize.height {
                maxY = min(1, minY + minimumSize.height)
                minY = max(0, maxY - minimumSize.height)
            }
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        }

        private func resizedRect(
            for target: DragTarget,
            by delta: CGSize,
            minimumSize: CGSize
        ) -> CGRect {
            var minX = initialCropRect.minX
            var maxX = initialCropRect.maxX
            var minY = initialCropRect.minY
            var maxY = initialCropRect.maxY

            if target.movesLeft {
                minX = min(max(initialCropRect.minX + delta.width, 0), maxX - minimumSize.width)
            }
            if target.movesRight {
                maxX = max(min(initialCropRect.maxX + delta.width, 1), minX + minimumSize.width)
            }
            if target.movesTop {
                minY = min(max(initialCropRect.minY + delta.height, 0), maxY - minimumSize.height)
            }
            if target.movesBottom {
                maxY = max(min(initialCropRect.maxY + delta.height, 1), minY + minimumSize.height)
            }

            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        }

        private func screenRect(for normalizedRect: CGRect) -> CGRect {
            CGRect(
                x: imageRect.minX + normalizedRect.minX * imageRect.width,
                y: imageRect.minY + normalizedRect.minY * imageRect.height,
                width: normalizedRect.width * imageRect.width,
                height: normalizedRect.height * imageRect.height
            )
        }

        private func normalizedPoint(_ point: CGPoint) -> CGPoint {
            CGPoint(
                x: min(max((point.x - imageRect.minX) / imageRect.width, 0), 1),
                y: min(max((point.y - imageRect.minY) / imageRect.height, 0), 1)
            )
        }

        private func drawGrid(in rect: CGRect) {
            let grid = NSBezierPath()
            for fraction: CGFloat in [1 / 3, 2 / 3] {
                let x = rect.minX + rect.width * fraction
                grid.move(to: CGPoint(x: x, y: rect.minY))
                grid.line(to: CGPoint(x: x, y: rect.maxY))

                let y = rect.minY + rect.height * fraction
                grid.move(to: CGPoint(x: rect.minX, y: y))
                grid.line(to: CGPoint(x: rect.maxX, y: y))
            }
            grid.lineWidth = 1
            NSColor.white.withAlphaComponent(0.42).setStroke()
            grid.stroke()
        }

        private func drawHandles(in rect: CGRect) {
            for target in DragTarget.resizeTargets {
                let handle = handleRect(for: target, in: rect)
                NSColor.white.setFill()
                handle.fill()
                NSColor.black.withAlphaComponent(0.7).setStroke()
                let outline = NSBezierPath(rect: handle.insetBy(dx: 0.5, dy: 0.5))
                outline.lineWidth = 1
                outline.stroke()
            }
        }

        private func handleRect(for target: DragTarget, in rect: CGRect) -> CGRect {
            let center = handleCenter(for: target, in: rect)
            return CGRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10)
        }

        private func hitRect(for target: DragTarget, in rect: CGRect) -> CGRect {
            handleRect(for: target, in: rect).insetBy(dx: -6, dy: -6)
        }

        private func handleCenter(for target: DragTarget, in rect: CGRect) -> CGPoint {
            switch target {
            case .topLeft:
                return CGPoint(x: rect.minX, y: rect.minY)
            case .top:
                return CGPoint(x: rect.midX, y: rect.minY)
            case .topRight:
                return CGPoint(x: rect.maxX, y: rect.minY)
            case .right:
                return CGPoint(x: rect.maxX, y: rect.midY)
            case .bottomRight:
                return CGPoint(x: rect.maxX, y: rect.maxY)
            case .bottom:
                return CGPoint(x: rect.midX, y: rect.maxY)
            case .bottomLeft:
                return CGPoint(x: rect.minX, y: rect.maxY)
            case .left:
                return CGPoint(x: rect.minX, y: rect.midY)
            case .move, .create:
                return .zero
            }
        }

        private enum DragTarget: CaseIterable {
            case move
            case create
            case topLeft
            case top
            case topRight
            case right
            case bottomRight
            case bottom
            case bottomLeft
            case left

            static let resizeTargets: [DragTarget] = [
                .topLeft, .top, .topRight, .right,
                .bottomRight, .bottom, .bottomLeft, .left
            ]

            var movesLeft: Bool {
                self == .topLeft || self == .bottomLeft || self == .left
            }

            var movesRight: Bool {
                self == .topRight || self == .bottomRight || self == .right
            }

            var movesTop: Bool {
                self == .topLeft || self == .topRight || self == .top
            }

            var movesBottom: Bool {
                self == .bottomLeft || self == .bottomRight || self == .bottom
            }
        }
    }
}

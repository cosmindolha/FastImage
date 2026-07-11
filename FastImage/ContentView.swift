//  Created by Cosmin Dolha on 22.10.2022.
import AppKit
import Combine
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

private enum ImageSupport {
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

    private let decodeQueue = DispatchQueue(label: "com.cosmindolha.FastImage.decode", qos: .userInitiated)
    private let requestLock = NSLock()
    private let cacheLock = NSLock()
    private var requestGeneration = 0
    private var imageCache: [URL: NSImage] = [:]
    private var cacheOrder: [URL] = []
    private let cacheCountLimit = 3

    func load(_ url: URL) {
        let generation = beginRequest()
        failedFilename = nil

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
        image = droppedImage
        failedFilename = nil
    }

    func reportUnsupported(_ url: URL) {
        _ = beginRequest()
        image = nil
        failedFilename = url.lastPathComponent
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
}

struct ContentView: View, DropDelegate {
    @StateObject private var imageLoader = ImageLoader()
    @State private var colorRectBorder: Color = .gray
    @State private var imagesInDirectory: [URL] = []
    @State private var imageIterator = 0
    @State private var currentImageURL: URL?
    @State private var currentScreenSize: CGSize = .zero
    @State private var sliderValue: CGFloat = 0
    @State private var geometrySize: CGSize = .zero
    @State private var imageOffset: CGSize = .zero
    @State private var dragOriginOffset: CGSize = .zero
    @State private var handModeEnabled = true

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Rectangle()
                    .foregroundColor(Color.black.opacity(0.1))
                    .border(colorRectBorder.opacity(0.1), width: 3)

                if let image = imageLoader.image {
                    ScrollView([.horizontal, .vertical]) {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(
                                width: max(1, currentScreenSize.width + sliderValue),
                                height: max(1, currentScreenSize.height + sliderValue)
                            )
                            .onTapGesture(count: 2) {
                                resetView(to: geometry.size)
                            }
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        imageOffset = CGSize(
                                            width: dragOriginOffset.width + value.translation.width,
                                            height: dragOriginOffset.height + value.translation.height
                                        )
                                    }
                                    .onEnded { _ in
                                        dragOriginOffset = imageOffset
                                    }
                            )
                            .offset(imageOffset)
                    }

                    if !handModeEnabled {
                        ScrollWheelView(sliderValue: $sliderValue)
                    }
                } else if let failedFilename = imageLoader.failedFilename {
                    Text("Couldn’t open \(failedFilename)")
                        .foregroundStyle(.secondary)
                }
            }
            .onAppear {
                geometrySize = geometry.size
                currentScreenSize = geometry.size
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
                    Slider(value: $sliderValue, in: -600...2500) {
                        Text("Zoom")
                    } minimumValueLabel: {
                        Image(systemName: "minus.magnifyingglass")
                    } maximumValueLabel: {
                        Image(systemName: "plus.magnifyingglass")
                    }
                    .frame(width: 400)
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        handModeEnabled.toggle()
                    } label: {
                        Image(systemName: handModeEnabled ? "hand.point.up.left.fill" : "plus.magnifyingglass")
                    }
                    .keyboardShortcut(.space, modifiers: [])
                }
            }
            .onChange(of: geometry.size) { newSize in
                geometrySize = newSize
                currentScreenSize = newSize
            }
        }
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
            imageLoader.reportUnsupported(imageURL)
            return
        }

        displayImage(at: imageURL)
        scanDirectory(containing: imageURL)
    }

    private func displayImage(at url: URL) {
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
        currentScreenSize = size
        sliderValue = 0
        imageOffset = .zero
        dragOriginOffset = .zero
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

struct ScrollWheelView: NSViewRepresentable {
    @Binding var sliderValue: CGFloat
    let min: CGFloat = -600
    let max: CGFloat = 2500

    func makeNSView(context: Context) -> NSView {
        let view = CustomNSView()
        view.onScroll = { deltaY in
            let newValue = sliderValue + deltaY
            sliderValue = Swift.min(Swift.max(newValue, min), max)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
    }

    class CustomNSView: NSView {
        var onScroll: ((CGFloat) -> Void)?

        override func scrollWheel(with event: NSEvent) {
            super.scrollWheel(with: event)
            onScroll?(event.scrollingDeltaY)
        }
    }
}

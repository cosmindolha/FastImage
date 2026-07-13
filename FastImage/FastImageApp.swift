//
//  FastImageApp.swift
//  FastImage
//
//  Created by Cosmin Dolha on 22.10.2022.
//

import SwiftUI

extension Notification.Name {
    static let fastImageSave = Notification.Name("FastImage.save")
    static let fastImageToggleCrop = Notification.Name("FastImage.toggleCrop")
    static let fastImageApplyCrop = Notification.Name("FastImage.applyCrop")
    static let fastImageCancelCrop = Notification.Name("FastImage.cancelCrop")
}

private struct FastImageCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .saveItem) {
            Button("Save") {
                NotificationCenter.default.post(name: .fastImageSave, object: nil)
            }
            .keyboardShortcut("s", modifiers: .command)
        }

        CommandMenu("Image") {
            Button("Crop") {
                NotificationCenter.default.post(name: .fastImageToggleCrop, object: nil)
            }
            .keyboardShortcut("k", modifiers: [])

            Divider()

            Button("Apply Crop") {
                NotificationCenter.default.post(name: .fastImageApplyCrop, object: nil)
            }
            .keyboardShortcut(.return, modifiers: [])

            Button("Cancel Crop") {
                NotificationCenter.default.post(name: .fastImageCancelCrop, object: nil)
            }
            .keyboardShortcut(.escape, modifiers: [])
        }
    }
}


@main
struct FastImageApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView().preferredColorScheme(.dark)
                .handlesExternalEvents(preferring: Set(arrayLiteral: "pause"), allowing: Set(arrayLiteral: "*"))
                .frame(minWidth: 300, minHeight: 300)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem, addition: { })
            FastImageCommands()
        }
        .handlesExternalEvents(matching: Set(arrayLiteral: "*"))
    }
}

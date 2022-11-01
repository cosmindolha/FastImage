//
//  FastImageApp.swift
//  FastImage
//
//  Created by Cosmin Dolha on 22.10.2022.
//

import SwiftUI



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
        }.handlesExternalEvents(matching: Set(arrayLiteral: "*"))
    }
}

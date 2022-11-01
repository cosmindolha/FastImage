//  Created by Cosmin Dolha on 22.10.2022.
import SwiftUI
import UniformTypeIdentifiers


// to do - zoom with mouse wheel, and trackpad, when the SwiftUI zoom bug is fixed

struct ContentView: View, DropDelegate {
    @State var image:NSImage?
    @State var colorRect:Color = .black
    @State var colorRectBorder:Color = .gray
    @State var imagesInDirectory:Array<String> = []
    @State var imageIterator:Int = 0
    @State var imageDirectory:URL?
    @State var currentImageFilename = ""
    @State var currentScreenSize:CGSize = CGSize()

    @State var slidervalue:CGFloat = 0.0

    
    @State var geomSize:CGSize = CGSize()

    var body: some View {
         GeometryReader { geometry in
            VStack {
                ZStack{
                    Rectangle().foregroundColor(colorRect.opacity(0.1)).border(colorRectBorder.opacity(0.1), width: 3)
                    if let imagew = image {
                        ScrollView([.horizontal, .vertical]) {
                            VStack{
                                Image(nsImage: imagew)
                                    .resizable().scaledToFit()
                                    .frame(width: currentScreenSize.width+slidervalue,
                                           height: currentScreenSize.height+slidervalue)
                                   .onTapGesture(count: 2, perform: {
                                        geomSize =  geometry.size
                                        currentScreenSize = geometry.size
                                       slidervalue = 0
                                    })
                            }
                        }
                        .onAppear(perform: {
                            geomSize = geometry.size
                            currentScreenSize = geometry.size
                        })
                    }
                }
            }
            .onOpenURL(){ url in
                if let imageData = try? Data(contentsOf: url) {
                    readDirectory(at: url)
                    DispatchQueue.main.async {
                        image = NSImage(data: imageData)
                    }
                }
            }.onDrop(of: [.image, .url], delegate: self)
                .toolbar {
                    
                    ToolbarItem(placement: .primaryAction) {
                        Link("Created by CosminDolha.com", destination: URL(string: "https://cosmindolha.com")!).foregroundColor(.gray).font(.caption)
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: {
                            getPrevImage()
                        }, label: {
                            Image(systemName: "chevron.left")
                        }).keyboardShortcut(KeyEquivalent.leftArrow, modifiers: [])
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: {
                            getNextImage()
                        }, label: {
                            Image(systemName: "chevron.right")
                        }).keyboardShortcut(KeyEquivalent.rightArrow, modifiers: [])
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Slider(value: $slidervalue, in: -600...2500) {
                                           Text("Zoom")
                                       } minimumValueLabel: {
                                           Image(systemName: "minus.magnifyingglass")
                                       } maximumValueLabel: {
                                           Image(systemName: "plus.magnifyingglass")
                                       }
                                       .frame(width: 400)
                                }
                    }
                .onChange(of: geometry.size) { newSize in
                    geomSize = newSize
                    currentScreenSize = newSize
                }
        }
    }

    func getPrevImage(){
        if(imagesInDirectory.count > 0){
            if(imageIterator > 0){
                imageIterator -= 1
            }else{
                imageIterator = imagesInDirectory.count-1
            }
        }
        loadImage()
    }
    func getNextImage(){
            if(imagesInDirectory.count > 0){
                if(imageIterator < imagesInDirectory.count-1){
                    imageIterator += 1
                }else{
                    imageIterator = 0
                }
            loadImage()
        }
    }
    func loadImage(){
        currentScreenSize = geomSize
        if let nextImagePath = imageDirectory?.appendingPathComponent(imagesInDirectory[imageIterator]).absoluteString {
                if let tempUrl = URL(string: nextImagePath){
                let imageURL = tempUrl
                let data = try? Data(contentsOf: imageURL)
                if let data = data {
                    DispatchQueue.main.async {
                        self.image = NSImage(data: data)
                    }
                }
            }
        }
    }
    func readDirectory(at url: URL) {
        imagesInDirectory = []
        currentImageFilename = String(url.relativePath.split(separator: "/").last ?? "")
        imageDirectory = url.deletingLastPathComponent()
        let indexPosition = imagesInDirectory.firstIndex(of: currentImageFilename)
        if let indexPositionTemp = indexPosition {
             imageIterator = indexPositionTemp
        }
        let fileManager = FileManager.default
        let path = url.deletingLastPathComponent().relativePath
        let items:Array<String>? = try? fileManager.contentsOfDirectory(atPath: path)
        let fileFilter:Array<String> = ["jpg", "jpeg", "png", "gif", "bmp", "heif", "heic", "tif", "webp", "tiff", "ARW"]
        if let itemsInDirectory = items {
            for item in itemsInDirectory {
                if let extensionInFile = item.split(separator: ".").last {
                    let realString = String(extensionInFile).lowercased()
                        if fileFilter.contains(realString) {
                            imagesInDirectory.append(item)
                        }
                }
            }
        }
    }
    func performDrop(info: DropInfo) -> Bool {
        let types: [UTType] = [.image, .png, .jpeg, .tiff, .gif, .icns, .ico, .rawImage, .bmp, .svg, .webP]
        
        let itemsURL = info.itemProviders(for: ["public.url"])
        for item in itemsURL {
                   _ = item.loadObject(ofClass: URL.self) { data, error in
                       if let url = data {
                           readDirectory(at: url)
                }
            }
        }
        if info.hasItemsConforming(to: types) {
            let providers = info.itemProviders(for: types)
            for type in types {
                for provider in providers {
                    if provider.registeredTypeIdentifiers.contains(type.identifier) {
                        provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, error in
                            if let data = data {
                                DispatchQueue.main.async {
                                    self.image = NSImage(data: data)
                                }
                            }
                        }
                        return true
                    }
                }
            }
        }
        return false
    }
    func validateDrop(info: DropInfo) -> Bool {
        return true
    }
    func dropEntered(info: DropInfo) {
        colorRectBorder = .white
    }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        return nil
    }
    func dropExited(info: DropInfo) {
        colorRectBorder = .gray
    }
}

/*
struct ContentView2: View, DropDelegate {
    @State var image:NSImage?
    @State var colorRect:Color = .black
    @State var colorRectBorder:Color = .gray
    @State var imagesInDirectory:Array<String> = []
    @State var imageIterator:Int = 0
    @State var imageDirectory:URL?
    @State var currentImageFilename = ""
    @State var currentScreenSize:CGSize = CGSize()
    //scale

    @State var fuptade:Bool = false
    
    @State  var currentAmount = 0.0
    @State  var finalAmount = 0.0
    
    @State var forceUpdate:Bool = false
    
    @State var geomSize:CGSize = CGSize()
    
    let zoomAmount = 3.0
    
    var body: some View {
         GeometryReader { geometry in
            VStack {
                ZStack{
                    Rectangle().foregroundColor(colorRect.opacity(0.1)).border(colorRectBorder.opacity(0.1), width: 3)
                    if let imagew = image {
                        ScrollView([.horizontal, .vertical]) {
                            VStack{
                                Image(nsImage: imagew)
                                    .resizable().scaledToFit()
                                    .frame(width: currentScreenSize.width > 100 ? currentScreenSize.width : 101,
                                           height: currentScreenSize.height)
                                    .gesture(
                                        MagnificationGesture(minimumScaleDelta: 0.1)
                                            .onChanged { amount in
                                                
                                                    if(amount > currentAmount){
                                                        zoomIn()
                                                    }else{
                                                        zoomOut()
                                                    }
                                                    currentAmount = amount
                                                    finalAmount = currentAmount
                                                
                                            }
                                            .onEnded({ val in
                                                forceUpdate.toggle()
                                            })
                                    ).onTapGesture(count: 2, perform: {
                                        geomSize =  geometry.size
                                        currentScreenSize = geometry.size
                                        finalAmount = 1.0
                                        currentAmount = 0.0
                                    })
                            }.id(forceUpdate)
                        }
                        .onTapGesture(perform: {
                            forceUpdate.toggle()
                        })
                        .onAppear(perform: {
                            geomSize = geometry.size
                            currentScreenSize = geometry.size
                        })
                    }
                }
            }
            .onOpenURL(){ url in
                if let imageData = try? Data(contentsOf: url) {
                    readDirectory(at: url)
                    DispatchQueue.main.async {
                        image = NSImage(data: imageData)
                    }
                }
            }.onDrop(of: [.image, .url], delegate: self)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: {
                            getPrevImage()
                        }, label: {
                            Image(systemName: "chevron.left")
                        }).keyboardShortcut(KeyEquivalent.leftArrow, modifiers: [])
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: {
                            getNextImage()
                        }, label: {
                            Image(systemName: "chevron.right")
                        }).keyboardShortcut(KeyEquivalent.rightArrow, modifiers: [])
                    }
                }.onTapGesture(perform: {
                    forceUpdate.toggle()
                   // print("update from rectangle")
                })
                .onChange(of: geometry.size) { newSize in
                        
                    geomSize = newSize
                    currentScreenSize = newSize
                }
        }
    }
    func zoomIn(){
        currentScreenSize.width = currentScreenSize.width + zoomAmount
        currentScreenSize.height = currentScreenSize.height + zoomAmount
    }
    func zoomOut(){
        if(currentScreenSize.width > 200){
            
            currentScreenSize.width = currentScreenSize.width - zoomAmount
            currentScreenSize.height = currentScreenSize.height - zoomAmount
            
        }else{
            currentScreenSize.width = 200
            currentScreenSize.height = 200
        }
    }
    func getPrevImage(){
        if(imagesInDirectory.count > 0){
            if(imageIterator > 0){
                imageIterator -= 1
            }else{
                imageIterator = imagesInDirectory.count-1
            }
        }
        loadImage()
    }
    func getNextImage(){
            if(imagesInDirectory.count > 0){
                if(imageIterator < imagesInDirectory.count-1){
                    imageIterator += 1
                }else{
                    imageIterator = 0
                }
            loadImage()
        }
    }
    func loadImage(){
        
        forceUpdate.toggle()
        currentScreenSize = geomSize
        finalAmount = 1.0
        currentAmount = 0.0
        
        if let nextImagePath = imageDirectory?.appendingPathComponent(imagesInDirectory[imageIterator]).absoluteString {
                if let tempUrl = URL(string: nextImagePath){
                let imageURL = tempUrl
                let data = try? Data(contentsOf: imageURL)
                if let data = data {
                    DispatchQueue.main.async {
                        self.image = NSImage(data: data)
                    }
                }
            }
        }
    }
    func readDirectory(at url: URL) {
        imagesInDirectory = []
        currentImageFilename = String(url.relativePath.split(separator: "/").last ?? "")
        imageDirectory = url.deletingLastPathComponent()
        let indexPosition = imagesInDirectory.firstIndex(of: currentImageFilename)
        if let indexPositionTemp = indexPosition {
             imageIterator = indexPositionTemp
        }
        let fileManager = FileManager.default
        let path = url.deletingLastPathComponent().relativePath
        let items:Array<String>? = try? fileManager.contentsOfDirectory(atPath: path)
        let fileFilter:Array<String> = ["jpg", "jpeg", "png", "gif", "bmp", "heif", "heic", "tif", "webp", "tiff"]
        if let itemsInDirectory = items {
            for item in itemsInDirectory {
                if let extensionInFile = item.split(separator: ".").last {
                    let realString = String(extensionInFile).lowercased()
                        if fileFilter.contains(realString) {
                            imagesInDirectory.append(item)
                        }
                }
            }
        }
    }
    func performDrop(info: DropInfo) -> Bool {
        let types: [UTType] = [.image, .png, .jpeg, .tiff, .gif, .icns, .ico, .rawImage, .bmp, .svg, .webP]
        let itemsURL = info.itemProviders(for: ["public.url"])
        for item in itemsURL {
                   _ = item.loadObject(ofClass: URL.self) { data, error in
                       if let url = data {
                           readDirectory(at: url)
                }
            }
        }
        if info.hasItemsConforming(to: [.image, .jpeg, .tiff, .gif, .png, .icns, .bmp, .ico, .rawImage, .svg]) {
            let providers = info.itemProviders(for: [.image, .jpeg, .tiff, .gif, .png, .icns, .bmp, .ico, .rawImage, .svg])
            for type in types {
                for provider in providers {
                    if provider.registeredTypeIdentifiers.contains(type.identifier) {
                        provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, error in
                            if let data = data {
                                DispatchQueue.main.async {
                                    self.image = NSImage(data: data)
                                }
                            }
                        }
                        return true
                    }
                }
            }
        }
        return false
    }
    func validateDrop(info: DropInfo) -> Bool {
        return true
    }
    func dropEntered(info: DropInfo) {
        colorRectBorder = .white
    }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        return nil
    }
    func dropExited(info: DropInfo) {
        colorRectBorder = .gray
    }
}
*/

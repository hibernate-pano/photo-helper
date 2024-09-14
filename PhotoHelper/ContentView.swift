//
//  ContentView.swift
//  PhotoHelper
//
//  Created by panbo on 2024/9/13.
//

import SwiftUI
import Photos
import Vision
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var images: [PHAsset] = []
    @State private var currentIndex = 0
    @State private var offset: CGSize = .zero
    @State private var currentImageClassification: String = ""
    @State private var showingImportMenu = false
    @State private var showingFilePicker = false
    @State private var showingEndMessage = false
    @State private var showingPermissionAlert = false
    @State private var permissionAlertMessage = ""
    @State private var showingGridView = false

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                
                VStack {
                    if !images.isEmpty {
                        AssetImage(asset: images[currentIndex])
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 400)
                            .cornerRadius(20)
                            .shadow(radius: 10)
                            .offset(y: offset.height)
                            .gesture(
                                DragGesture()
                                    .onChanged { gesture in
                                        self.offset = gesture.translation
                                    }
                                    .onEnded { _ in
                                        if self.offset.height < -100 {
                                            self.moveToTrash()
                                        } else if self.offset.height > 100 {
                                            self.nextImage()
                                        }
                                        self.offset = .zero
                                    }
                            )
                        
                        Text(currentImageClassification)
                            .foregroundColor(.white)
                            .padding()
                        
                        Text("上滑删除，下滑下一张")
                            .foregroundColor(.white)
                            .padding()
                    } else {
                        Text("没有更多图片")
                            .foregroundColor(.white)
                    }
                }
                
                if showingEndMessage {
                    Text("到底了")
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(10)
                        .transition(.opacity)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                withAnimation {
                                    showingEndMessage = false
                                }
                            }
                        }
                }
            }
            .navigationTitle("照片管理")
            .navigationBarItems(trailing: HStack {
                Button(action: {
                    showingGridView.toggle()
                }) {
                    Image(systemName: "square.grid.2x2")
                        .font(.title)
                        .foregroundColor(.white)
                }
                Button(action: {
                    showingImportMenu.toggle()
                }) {
                    Image(systemName: "plus")
                        .font(.title)
                        .foregroundColor(.white)
                }
            })
            .onAppear(perform: loadImages)
            .sheet(isPresented: $showingImportMenu) {
                ImportMenuView(isPresented: $showingImportMenu, importFromAlbum: requestPhotoLibraryAccess, showFilePicker: $showingFilePicker)
            }
            .fileImporter(isPresented: $showingFilePicker, allowedContentTypes: [.folder], onCompletion: handleFolderSelection)
            .alert(isPresented: $showingPermissionAlert) {
                Alert(title: Text("权限请求"), message: Text(permissionAlertMessage), dismissButton: .default(Text("确定")))
            }
            .sheet(isPresented: $showingGridView) {
                GridView(images: images, showingGridView: $showingGridView)
            }
        }
    }
    
    func loadImages() {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let fetchResult = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        
        fetchResult.enumerateObjects { (asset, _, _) in
            self.images.append(asset)
        }
        
        if !images.isEmpty {
            classifyImage(asset: images[currentIndex])
        }
    }
    
    func moveToTrash() {
        PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets([self.images[self.currentIndex]] as NSFastEnumeration)
        } completionHandler: { success, error in
            if success {
                DispatchQueue.main.async {
                    self.images.remove(at: self.currentIndex)
                    if self.images.isEmpty {
                        self.currentIndex = 0
                    } else if self.currentIndex >= self.images.count {
                        self.currentIndex = self.images.count - 1
                    }
                    if !self.images.isEmpty {
                        self.classifyImage(asset: self.images[self.currentIndex])
                    }
                }
            }
        }
    }
    
    func nextImage() {
        currentIndex = (currentIndex + 1) % images.count
        // 强制视图更新
        self.images = Array(self.images)
        classifyImage(asset: images[currentIndex])
    }
    
    func classifyImage(asset: PHAsset) {
        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.deliveryMode = .highQualityFormat
        
        manager.requestImage(for: asset, targetSize: CGSize(width: 224, height: 224), contentMode: .aspectFit, options: options) { image, _ in
            guard let image = image else { return }
            
            guard let ciImage = CIImage(image: image) else { return }
            
            guard let model = try? VNCoreMLModel(for: MobileNetV2().model) else { return }
            
            let request = VNCoreMLRequest(model: model) { request, error in
                guard let results = request.results as? [VNClassificationObservation] else { return }
                if let firstResult = results.first {
                    DispatchQueue.main.async {
                        self.currentImageClassification = "分类: \(translateToChineseCategory(firstResult.identifier)) (置信度: \(String(format: "%.2f", firstResult.confidence)))"
                    }
                }
            }
            
            try? VNImageRequestHandler(ciImage: ciImage, options: [:]).perform([request])
        }
    }
    
    func importFromAlbum() {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let fetchResult = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        
        var newImages: [PHAsset] = []
        fetchResult.enumerateObjects { (asset, _, _) in
            if !self.images.contains(where: { $0.localIdentifier == asset.localIdentifier }) {
                newImages.append(asset)
            }
        }
        
        self.images.append(contentsOf: newImages)
        if !self.images.isEmpty {
            self.classifyImage(asset: self.images[self.currentIndex])
        }
    }
    
    func handleFolderSelection(result: Result<URL, Error>) {
        showingFilePicker = false
        switch result {
        case .success(let folderURL):
            requestFolderAccess(for: folderURL)
        case .failure(let error):
            print("Error selecting folder: \(error.localizedDescription)")
            showPermissionAlert(message: "选择文件夹时出错：\(error.localizedDescription)")
        }
    }
    
    func requestFolderAccess(for folderURL: URL) {
        let manager = FileManager.default
        if manager.isReadableFile(atPath: folderURL.path) {
            importImagesFromFolder(folderURL)
        } else {
            folderURL.startAccessingSecurityScopedResource()
            if manager.isReadableFile(atPath: folderURL.path) {
                importImagesFromFolder(folderURL)
                folderURL.stopAccessingSecurityScopedResource()
            } else {
                showPermissionAlert(message: "无法访问选择的文件夹，请检查权限设置。")
            }
        }
    }
    
    func showPermissionAlert(message: String) {
        DispatchQueue.main.async {
            self.permissionAlertMessage = message
            self.showingPermissionAlert = true
        }
    }
    
    func requestPhotoLibraryAccess() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .authorized, .limited:
            importFromAlbum()
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
                if newStatus == .authorized || newStatus == .limited {
                    DispatchQueue.main.async {
                        self.importFromAlbum()
                    }
                } else {
                    self.showPermissionAlert(message: "需要访问相册权限才能导入照片。")
                }
            }
        case .denied, .restricted:
            showPermissionAlert(message: "请在设置中允许访问相册权限。")
        @unknown default:
            showPermissionAlert(message: "无法访问相册，请检查权限设置。")
        }
    }

    func importImagesFromFolder(_ folderURL: URL) {
    let fileManager = FileManager.default
    guard let enumerator = fileManager.enumerator(at: folderURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
        return
    }
    
    for case let fileURL as URL in enumerator {
        do {
            let fileAttributes = try fileURL.resourceValues(forKeys:[.isRegularFileKey])
            if fileAttributes.isRegularFile!, UTType(filenameExtension: fileURL.pathExtension)?.conforms(to: .image) ?? false {
                if let image = UIImage(contentsOfFile: fileURL.path) {
                    PHPhotoLibrary.shared().performChanges {
                        PHAssetChangeRequest.creationRequestForAsset(from: image)
                    } completionHandler: { success, error in
                        if success {
                            DispatchQueue.main.async {
                                self.loadImages()
                            }
                        } else if let error = error {
                            print("Error saving image to photo library: \(error.localizedDescription)")
                        }
                    }
                }
            }
        } catch {
            print("Error reading file attributes: \(error.localizedDescription)")
        }
    }
}
}

func translateToChineseCategory(_ englishCategory: String) -> String {
    // 这里可以添加更多的翻译
    let translations = [
        "dog": "狗",
        "cat": "猫",
        "bird": "鸟",
        "fish": "鱼",
        "flower": "花",
        "tree": "树",
        "mountain": "山",
        "beach": "海滩",
        "car": "汽车",
        "airplane": "飞机"
    ]
    
    return translations[englishCategory.lowercased()] ?? englishCategory
}

struct AssetImage: View {
    let asset: PHAsset
    @State private var image: UIImage?
    var isGridView: Bool = false
    
    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: isGridView ? .fill : .fit)
            } else {
                Color.gray
            }
        }
        .onAppear(perform: loadImage)
    }
    
    private func loadImage() {
        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        options.isSynchronous = false
        
        let targetSize = isGridView ? CGSize(width: 300, height: 300) : PHImageManagerMaximumSize
        
        manager.requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFit, options: options) { result, _ in
            if let result = result {
                self.image = result
            }
        }
    }
}

struct ImportMenuView: View {
    @Binding var isPresented: Bool
    var importFromAlbum: () -> Void
    @Binding var showFilePicker: Bool
    
    var body: some View {
        NavigationView {
            List {
                Button("导入相册") {
                    importFromAlbum()
                    isPresented = false
                }
                Button("导入指定的文件夹") {
                    showFilePicker = true
                    isPresented = false
                }
            }
            .navigationTitle("导入选项")
            .navigationBarItems(trailing: Button("关闭") {
                isPresented = false
            })
        }
    }
}

struct GridView: View {
    let images: [PHAsset]
    @Binding var showingGridView: Bool

    let columns = [
        GridItem(.adaptive(minimum: 100, maximum: 150), spacing: 2)
    ]

    var body: some View {
        NavigationView {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(images, id: \.localIdentifier) { asset in
                        AssetImage(asset: asset, isGridView: true)
                            .aspectRatio(CGFloat(asset.pixelWidth) / CGFloat(asset.pixelHeight), contentMode: .fit)
                            .frame(minHeight: 100, maxHeight: 150)
                            .clipped()
                    }
                }
                .padding(2)
            }
            .navigationTitle("全局视图")
            .navigationBarItems(trailing: Button("关闭") {
                showingGridView = false
            })
        }
    }
}

#Preview {
    ContentView()
}

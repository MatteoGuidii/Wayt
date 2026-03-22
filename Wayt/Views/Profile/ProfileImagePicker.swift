import SwiftUI
import PhotosUI
import UIKit

struct ProfileImagePicker: View {

    @Binding var imageData: Data?
    @Environment(\.dismiss) private var dismiss

    @State private var selectedItem: PhotosPickerItem?
    @State private var isProcessing = false

    var body: some View {
        PhotosPicker(
            selection: $selectedItem,
            matching: .images,
            photoLibrary: .shared()
        ) {
            EmptyView()
        }
        .photosPickerStyle(.inline)
        .photosPickerDisabledCapabilities(.selectionActions)
        .onChange(of: selectedItem) { _, newItem in
            guard let newItem else { return }
            isProcessing = true
            Task {
                await processImage(newItem)
                isProcessing = false
                dismiss()
            }
        }
        .overlay {
            if isProcessing {
                ZStack {
                    Color.black.opacity(0.3)
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.2)
                }
            }
        }
    }

    private func processImage(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let uiImage = UIImage(data: data) else {
            return
        }

        // Resize to max 400x400
        let resized = resizeImage(uiImage, maxSize: 400)

        // Compress to JPEG
        imageData = resized.jpegData(compressionQuality: 0.7)
    }

    private func resizeImage(_ image: UIImage, maxSize: CGFloat) -> UIImage {
        let size = image.size
        let ratio = min(maxSize / size.width, maxSize / size.height)
        guard ratio < 1 else { return image }

        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

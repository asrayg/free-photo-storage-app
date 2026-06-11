import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

// MARK: - Edit pipeline

struct EditSettings: Equatable {
    var brightness: Double = 0      // -0.5...0.5
    var contrast: Double = 1        // 0.5...1.5
    var saturation: Double = 1      // 0...2
    var exposure: Double = 0        // -2...2
    var filter: FilterPreset = .none
    var rotation: Int = 0           // degrees clockwise, multiple of 90
    var cropAspect: CropAspect = .original

    var isIdentity: Bool { self == EditSettings() }
}

enum FilterPreset: String, CaseIterable, Identifiable {
    case none = "Original"
    case vivid = "Vivid"
    case mono = "Mono"
    case noir = "Noir"
    case fade = "Fade"
    case chrome = "Chrome"
    case instant = "Instant"
    case process = "Process"

    var id: String { rawValue }

    var ciName: String? {
        switch self {
        case .none: return nil
        case .vivid: return nil           // handled via saturation boost
        case .mono: return "CIPhotoEffectMono"
        case .noir: return "CIPhotoEffectNoir"
        case .fade: return "CIPhotoEffectFade"
        case .chrome: return "CIPhotoEffectChrome"
        case .instant: return "CIPhotoEffectInstant"
        case .process: return "CIPhotoEffectProcess"
        }
    }
}

enum CropAspect: String, CaseIterable, Identifiable {
    case original = "Original"
    case square = "1:1"
    case fourThree = "4:3"
    case threeFour = "3:4"
    case sixteenNine = "16:9"

    var id: String { rawValue }

    /// width / height, or nil to keep the source aspect.
    var ratio: CGFloat? {
        switch self {
        case .original: return nil
        case .square: return 1
        case .fourThree: return 4.0 / 3.0
        case .threeFour: return 3.0 / 4.0
        case .sixteenNine: return 16.0 / 9.0
        }
    }
}

enum ImageEditor {
    static let context = CIContext()

    static func apply(_ settings: EditSettings, to input: CIImage) -> CIImage {
        var image = input

        // Rotation (any multiple of 90)
        if settings.rotation % 360 != 0 {
            let radians = CGFloat(settings.rotation) * .pi / 180
            image = image.transformed(by: CGAffineTransform(rotationAngle: -radians))
            image = image.transformed(by: CGAffineTransform(translationX: -image.extent.origin.x, y: -image.extent.origin.y))
        }

        // Crop to aspect (centered)
        if let ratio = settings.cropAspect.ratio {
            let e = image.extent
            var w = e.width, h = e.height
            if w / h > ratio { w = h * ratio } else { h = w / ratio }
            let rect = CGRect(x: e.midX - w / 2, y: e.midY - h / 2, width: w, height: h)
            image = image.cropped(to: rect)
            image = image.transformed(by: CGAffineTransform(translationX: -image.extent.origin.x, y: -image.extent.origin.y))
        }

        // Color adjustments
        let color = CIFilter.colorControls()
        color.inputImage = image
        color.brightness = Float(settings.brightness)
        color.contrast = Float(settings.contrast)
        color.saturation = Float(settings.saturation * (settings.filter == .vivid ? 1.4 : 1))
        if let out = color.outputImage { image = out }

        if settings.exposure != 0 {
            let exposure = CIFilter.exposureAdjust()
            exposure.inputImage = image
            exposure.ev = Float(settings.exposure)
            if let out = exposure.outputImage { image = out }
        }

        if let name = settings.filter.ciName, let preset = CIFilter(name: name) {
            preset.setValue(image, forKey: kCIInputImageKey)
            if let out = preset.outputImage { image = out }
        }

        return image
    }

    /// Renders settings against a source image into a UIImage.
    static func render(_ settings: EditSettings, from source: CIImage) -> UIImage? {
        let output = apply(settings, to: source)
        guard let cg = context.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

// MARK: - View

@MainActor
struct PhotoEditorView: View {
    let store: PhotoStore
    let photo: Photo
    let original: UIImage

    @Environment(\.dismiss) private var dismiss
    @State private var settings = EditSettings()
    @State private var tab: Tab = .adjust
    @State private var preview: UIImage?
    @State private var isSaving = false

    /// A downscaled CIImage for fast live preview; full-res is rendered on save.
    private let previewSource: CIImage
    private let fullSource: CIImage

    enum Tab: String, CaseIterable { case adjust = "Adjust", filters = "Filters", crop = "Crop" }

    init(store: PhotoStore, photo: Photo, original: UIImage) {
        self.store = store
        self.photo = photo
        self.original = original
        let ci = CIImage(image: original) ?? CIImage()
        self.fullSource = ci
        // Cap the preview's long edge so slider drags stay smooth.
        let maxEdge: CGFloat = 1400
        let longEdge = max(ci.extent.width, ci.extent.height)
        if longEdge > maxEdge {
            let scale = maxEdge / longEdge
            self.previewSource = ci.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        } else {
            self.previewSource = ci
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                imageArea
                controls
            }
            .background(.black)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.tint(.white)
                }
                ToolbarItem(placement: .principal) {
                    Text("Edit").foregroundStyle(.white).font(.headline)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isSaving {
                        ProgressView().tint(.white)
                    } else {
                        Button("Save") { save() }
                            .tint(EditorAccent.cyan)
                            .disabled(settings.isIdentity)
                            .fontWeight(.semibold)
                    }
                }
            }
        }
        .onChange(of: settings) { _, _ in renderPreview() }
        .onAppear { renderPreview() }
    }

    private var imageArea: some View {
        ZStack {
            Color.black
            if let preview {
                Image(uiImage: preview)
                    .resizable()
                    .scaledToFit()
                    .padding()
            } else {
                ProgressView().tint(.white)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var controls: some View {
        VStack(spacing: 16) {
            Picker("", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            Group {
                switch tab {
                case .adjust: adjustControls
                case .filters: filterControls
                case .crop: cropControls
                }
            }
            .frame(height: 150)
        }
        .padding(.vertical)
        .background(Color(red: 0.07, green: 0.07, blue: 0.09))
    }

    private var adjustControls: some View {
        VStack(spacing: 10) {
            slider("Brightness", value: $settings.brightness, range: -0.5...0.5)
            slider("Contrast", value: $settings.contrast, range: 0.5...1.5)
            slider("Saturation", value: $settings.saturation, range: 0...2)
            slider("Exposure", value: $settings.exposure, range: -2...2)
        }
        .padding(.horizontal)
    }

    private func slider(_ label: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.white.opacity(0.7)).frame(width: 84, alignment: .leading)
            Slider(value: value, in: range).tint(EditorAccent.cyan)
        }
    }

    private var filterControls: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(FilterPreset.allCases) { preset in
                    Button {
                        settings.filter = preset
                    } label: {
                        VStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(.white.opacity(0.08))
                                .overlay {
                                    if let thumb = filterThumb(preset) {
                                        Image(uiImage: thumb).resizable().scaledToFill()
                                    }
                                }
                                .frame(width: 76, height: 76)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(settings.filter == preset ? EditorAccent.cyan : .clear, lineWidth: 2)
                                }
                            Text(preset.rawValue).font(.caption2)
                                .foregroundStyle(settings.filter == preset ? EditorAccent.cyan : .white.opacity(0.7))
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    private var cropControls: some View {
        VStack(spacing: 20) {
            HStack(spacing: 12) {
                ForEach(CropAspect.allCases) { aspect in
                    Button(aspect.rawValue) { settings.cropAspect = aspect }
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(settings.cropAspect == aspect ? EditorAccent.cyan.opacity(0.25) : .white.opacity(0.08),
                                    in: Capsule())
                        .foregroundStyle(settings.cropAspect == aspect ? EditorAccent.cyan : .white)
                }
            }
            Button {
                settings.rotation = (settings.rotation + 90) % 360
            } label: {
                Label("Rotate 90°", systemImage: "rotate.right")
            }
            .buttonStyle(.bordered)
            .tint(.white)
        }
        .padding(.horizontal)
    }

    // MARK: Rendering

    private func renderPreview() {
        let settings = settings
        let source = previewSource
        Task.detached(priority: .userInitiated) {
            let image = ImageEditor.render(settings, from: source)
            await MainActor.run { self.preview = image }
        }
    }

    private func filterThumb(_ preset: FilterPreset) -> UIImage? {
        var s = EditSettings()
        s.filter = preset
        return ImageEditor.render(s, from: previewSource)
    }

    private func save() {
        isSaving = true
        let settings = settings
        let source = fullSource
        Task {
            let rendered = await Task.detached(priority: .userInitiated) { () -> Data? in
                guard let image = ImageEditor.render(settings, from: source) else { return nil }
                return image.jpegData(compressionQuality: 0.92)
            }.value

            guard let data = rendered else {
                store.errorMessage = "Couldn't render the edited photo."
                isSaving = false
                return
            }
            await store.replace(photo, withFullData: data)
            isSaving = false
            dismiss()
        }
    }
}

enum EditorAccent {
    static let cyan = Color(red: 0.20, green: 0.95, blue: 1.0)
}

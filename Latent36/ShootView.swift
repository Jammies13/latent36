import SwiftUI
import UIKit
import ImageIO

struct ShootView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.scenePhase) private var phase
    @StateObject private var camera = Camera()
    let isSelected: Bool
    @State private var options = CameraOptions()
    @State private var showControls = false
    @State private var showFilms = false
    @State private var confirmDevelop = false
    @State private var grid = true
    @State private var timerSeconds = 0
    @State private var countdown = 0
    @State private var shutterTask: Task<Void, Never>?

    @State private var selectedControl: Dial = .ev
    let openDarkroom: () -> Void
    private enum Dial: String, CaseIterable {
        case ev = "EV", iso = "ISO", shutter = "SPEED", focus = "FOCUS", wb = "WB", zoom = "ZOOM"
    }
    private var locked: Bool { model.busy || countdown > 0 }
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 10) {
                        header
                        viewfinder
                            .frame(height: min((min(geometry.size.width, 540) - 24) * 4 / 3, max(240, geometry.size.height - 260)))
                        controlDeck
                        shutterRow
                    }.padding(.horizontal, 12).padding(.bottom, 8)
                        .frame(maxWidth: 540).frame(maxWidth: .infinity)
                }.scrollIndicators(.hidden)
            }
            .background(Look.background)
            .toolbar(.hidden, for: .navigationBar)
            .toolbar(.hidden, for: .tabBar)
            .sheet(isPresented: $showFilms) { FilmPicker() }
            .sheet(isPresented: $showControls) {
                OptionsView(camera: camera, options: $options, grid: $grid, timerSeconds: $timerSeconds)
                    .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
            }
            .confirmationDialog("Start developing?", isPresented: $confirmDevelop, titleVisibility: .visible) {
                Button("Develop all 36 exposures") { if let roll = model.active { Task { await model.develop(roll) } } }
            } message: { Text("Your photographs will unlock 24 hours from now. You can close the app and shoot another roll while you wait.") }
        }
        .onAppear {
            UIDevice.current.beginGeneratingDeviceOrientationNotifications(); syncCamera()
            #if DEBUG
            let args = ProcessInfo.processInfo.arguments
            if args.contains("--show-film-picker") { showFilms = true }
            if args.contains("--show-options") { showControls = true }
            #endif
        }
        .onDisappear { cancelTimer(); camera.stop(); UIDevice.current.endGeneratingDeviceOrientationNotifications() }
        .onChange(of: options) { _, value in camera.apply(value) }
        .onChange(of: camera.selectedLens) { _, _ in
            options.iso = min(max(options.iso, camera.isoRange.lowerBound), camera.isoRange.upperBound)
            options.shutter = min(max(options.shutter, camera.shutterRange.lowerBound), camera.shutterRange.upperBound)
        }
        .onChange(of: isSelected) { _, _ in syncCamera() }
        .onChange(of: phase) { _, _ in syncCamera() }
    }
    private var header: some View {
        HStack(spacing: 10) {
            Text("LATENT /36").font(.system(size: 17, weight: .black, design: .monospaced)).tracking(-1)
            Spacer(minLength: 0)
            Button { showFilms = true } label: {
                HStack(spacing: 5) {
                    Circle().fill(model.active.map { Look.stock($0.stock) } ?? Look.accent).frame(width: 6, height: 6)
                    Text(model.active?.stock.name ?? "LOAD FILM").font(.system(size: 10, weight: .bold, design: .monospaced))
                }.frame(minHeight: 44)
            }.disabled(locked).accessibilityLabel("Choose or preview film")
            Button { showControls = true } label: {
                Image(systemName: "gearshape").font(.system(size: 19)).frame(width: 44, height: 44)
            }.disabled(locked).accessibilityLabel("Options")
        }.foregroundStyle(Look.paper)
    }
    private var viewfinder: some View {
        ZStack {
            Color.black
            CameraPreview(camera: camera)
            if grid {
                GeometryReader { geo in
                    Path { path in
                        for fraction in [CGFloat(1.0/3), CGFloat(2.0/3)] {
                            path.move(to: CGPoint(x: geo.size.width*fraction, y: 0))
                            path.addLine(to: CGPoint(x: geo.size.width*fraction, y: geo.size.height))
                            path.move(to: CGPoint(x: 0, y: geo.size.height*fraction))
                            path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height*fraction))
                        }
                    }.stroke(.white.opacity(0.22), lineWidth: 0.5)
                }.allowsHitTesting(false)
            }
            if !camera.ready {
                VStack(spacing: 16) {
                    Image(systemName: "camera.aperture").font(.largeTitle)
                    Text(camera.message ?? "Opening the viewfinder…").font(.callout).multilineTextAlignment(.center)
                    if camera.denied {
                        Button("Open Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                    } else if camera.message != nil { Button("Retry camera") { camera.start() } }
                }.padding(24)
            }
            if countdown > 0 { Text("\(countdown)").font(.system(size: 82, weight: .light, design: .monospaced)).shadow(radius: 8).allowsHitTesting(false) }
            VStack {
                HStack {
                    if timerSeconds > 0 { Label("\(timerSeconds)s", systemImage: "timer") }
                    if options.flash != "Off" && !options.manualExposure { Image(systemName: "bolt.fill") }
                    Spacer()
                    Text(options.manualExposure ? "M" : "AE")
                }.font(.system(size: 10, weight: .bold, design: .monospaced)).padding(12).shadow(radius: 3)
                Spacer()
                HStack(spacing: 6) {
                    ForEach(camera.lenses) { lens in
                        Button(lens.title) { options = CameraOptions(); camera.switchLens(lens.id) }
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .frame(minWidth: 44, minHeight: 44)
                            .background(.black.opacity(0.65), in: Circle())
                            .foregroundStyle(camera.selectedLens == lens.id ? Look.accent : Look.paper)
                    }
                }.disabled(locked || !camera.ready).padding(.bottom, 10)
            }
        }.clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Look.paper.opacity(0.2)))
    }
    private func value(_ dial: Dial) -> String {
        switch dial {
        case .ev: return options.manualExposure ? "—" : String(format: "%+.1f", options.ev)
        case .iso: return options.manualExposure ? "\(Int(options.iso))" : "AUTO"
        case .shutter: return options.manualExposure ? shutterLabel : "AUTO"
        case .focus: return options.manualFocus ? String(format: "%.2f", options.focus) : "AF"
        case .wb: return options.manualWB ? "\(Int(options.kelvin))" : "AWB"
        case .zoom: return String(format: "%.1f×", Double(options.zoom))
        }
    }
    private var shutterLabel: String { options.shutter >= 1 ? String(format: "%.1fs", options.shutter) : "1/\(Int((1/options.shutter).rounded()))" }
    private var controlDeck: some View {
        VStack(spacing: 4) {
            HStack(spacing: 0) {
                ForEach(Dial.allCases, id: \.self) { dial in
                    Button { selectedControl = dial } label: {
                        VStack(spacing: 5) {
                            Text(dial.rawValue).font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(.secondary)
                            Text(value(dial)).font(.system(size: 12, weight: .semibold, design: .monospaced)).minimumScaleFactor(0.7).lineLimit(1)
                            Rectangle().fill(selectedControl == dial ? Look.accent : .clear).frame(height: 2)
                        }.padding(.top, 8).frame(maxWidth: .infinity, minHeight: 48)
                    }.buttonStyle(.plain).foregroundStyle(selectedControl == dial ? Look.accent : Look.paper)
                        .accessibilityLabel("\(dial.rawValue), \(value(dial))")
                        .accessibilityAddTraits(selectedControl == dial ? .isSelected : [])
                }
            }
            adjustment.padding(.horizontal, 10).frame(minHeight: 46)
        }.background(Look.panel, in: RoundedRectangle(cornerRadius: 8)).disabled(locked || !camera.ready)
    }
    @ViewBuilder private var adjustment: some View {
        switch selectedControl {
        case .ev:
            HStack {
                if options.manualExposure {
                    Text("EV needs auto exposure").font(.caption)
                    Spacer()
                    Button("Use auto") { options.manualExposure = false }.font(.caption.bold())
                } else {
                    Text("−").font(.caption)
                    Slider(value: $options.ev, in: camera.evRange, step: 0.1).accessibilityLabel("Exposure compensation")
                    Text("+").font(.caption)
                }
            }
        case .iso:
            HStack {
                modeButton($options.manualExposure)
                Slider(value: $options.iso, in: camera.isoRange).disabled(!options.manualExposure).accessibilityLabel("ISO")
            }.disabled(!camera.supportsManual)
        case .shutter:
            HStack {
                modeButton($options.manualExposure)
                Slider(value: Binding(get: { log2(min(max(options.shutter, camera.shutterRange.lowerBound), camera.shutterRange.upperBound)) }, set: { options.shutter = pow(2, $0) }), in: log2(camera.shutterRange.lowerBound)...log2(camera.shutterRange.upperBound))
                    .disabled(!options.manualExposure).accessibilityLabel("Shutter speed")
            }.disabled(!camera.supportsManual)
        case .focus:
            HStack {
                modeButton($options.manualFocus)
                Text("Near").font(.caption2)
                Slider(value: $options.focus, in: 0...1).disabled(!options.manualFocus).accessibilityLabel("Focus distance")
                Text("Far").font(.caption2)
            }.disabled(!camera.supportsFocus)
        case .wb:
            HStack {
                modeButton($options.manualWB)
                Slider(value: $options.kelvin, in: 2500...9000, step: 50).disabled(!options.manualWB).accessibilityLabel("White balance temperature")
                Text("K").font(.caption2)
            }.disabled(!camera.supportsWB)
        case .zoom:
            HStack {
                Text("1×").font(.caption2)
                Slider(value: $options.zoom, in: 1...max(1.01, camera.maxZoom)).accessibilityLabel("Digital zoom")
                Text(String(format: "%.0f×", Double(camera.maxZoom))).font(.caption2)
            }
        }
    }
    private func modeButton(_ binding: Binding<Bool>) -> some View {
        Button { binding.wrappedValue.toggle() } label: {
            Text(binding.wrappedValue ? "M" : "AUTO").font(.system(size: 11, weight: .bold, design: .monospaced)).frame(width: 48, height: 44)
        }.accessibilityLabel(binding.wrappedValue ? "Switch to automatic" : "Switch to manual")
    }
    private var shutterRow: some View {
        HStack {
            Button(action: openDarkroom) {
                VStack(spacing: 6) {
                    Image(systemName: "film.stack").font(.system(size: 23))
                    Text("DARKROOM").font(.system(size: 8, weight: .medium, design: .monospaced))
                }.frame(width: 85, height: 76)
            }.disabled(locked)
            Spacer()
            Button {
                if !model.loaded { Task { await model.load() } }
                else if model.active == nil { showFilms = true }
                else if model.active?.canDevelop == true { confirmDevelop = true }
                else { shutter() }
            } label: {
                ZStack {
                    Circle().stroke(Look.paper.opacity(0.7), lineWidth: 1.5).frame(width: 76, height: 76)
                    Circle().fill(Look.paper).frame(width: 62, height: 62)
                    if model.busy { ProgressView().tint(.black) }
                    else if countdown > 0 { Image(systemName: "xmark").foregroundStyle(.black) }
                    else if model.active == nil || model.active?.canDevelop == true {
                        Text(model.active == nil ? "LOAD" : "DEV").font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(.black)
                    } else { Circle().fill(Look.accent).frame(width: 9, height: 9) }
                }
            }.disabled(model.busy || (model.active?.canShoot == true && !camera.ready))
                .accessibilityLabel(countdown > 0 ? "Cancel timer" : model.active == nil ? "Load film" : model.active?.canDevelop == true ? "Develop roll" : "Take photograph")
            Spacer()
            VStack(spacing: 5) {
                Text(String(format: "%02d", model.active?.frames.count ?? 0))
                    .font(.system(size: 28, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 10).padding(.vertical, 2).background(.black, in: RoundedRectangle(cornerRadius: 4))
                Text("/ 36").font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
            }.frame(width: 85).accessibilityLabel("\(model.active?.frames.count ?? 0) of 36 exposures")
        }.foregroundStyle(Look.paper)
    }
    private func syncCamera() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--show-film-picker") || ProcessInfo.processInfo.arguments.contains("--ui-smoke") { return }
        #endif
        if isSelected && phase == .active { camera.start() }
        else { cancelTimer(); camera.stop() }
    }
    private func cancelTimer() { shutterTask?.cancel(); shutterTask = nil; countdown = 0 }
    private func shutter() {
        if countdown > 0 { cancelTimer(); return }
        guard let roll = model.active, roll.canShoot, camera.ready, !model.busy else { return }
        shutterTask = Task { @MainActor in
            if timerSeconds > 0 {
                for value in stride(from: timerSeconds, through: 1, by: -1) {
                    countdown = value
                    do { try await Task.sleep(for: .seconds(1)) } catch { countdown = 0; return }
                }
            }
            countdown = 0
            guard !Task.isCancelled, phase == .active, isSelected, !model.busy else { return }
            model.busy = true
            let background = UIApplication.shared.beginBackgroundTask(withName: "Seal exposure")
            camera.capture(orientation: UIDevice.current.orientation) { result in
                Task { @MainActor in
                    await model.saveCapture(result, rollID: roll.id)
                    if background != .invalid { UIApplication.shared.endBackgroundTask(background) }
                }
            }
        }
    }
}

struct FilmPicker: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedStock: FilmStock = .daylight
    @State private var selectedGrain: FilmGrain = .classic
    @State private var sample: SampleScene = .clouds
    @State private var showOriginal = false
    @State private var rendered: UIImage?
    @State private var original: UIImage?
    @State private var previewError: String?
    @State private var renderedKey: String?
    private var previewKey: String { sample.rawValue + "/" + selectedStock.rawValue + "/" + selectedGrain.rawValue }
    init() {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        _selectedStock = State(initialValue: args.contains("--preview-noir") ? .noir : .daylight)
        _showOriginal = State(initialValue: args.contains("--preview-original"))
        _selectedGrain = State(initialValue: args.contains("--preview-heavy") ? .heavy : .classic)
        #endif
    }
    var body: some View {
        NavigationStack {
            ScrollViewReader { scroll in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("TRY THE FILM").font(.system(.caption, design: .monospaced)).tracking(2)
                                Spacer()
                                Text("\(FilmStock.allCases.count) STOCKS").font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary)
                            }
                            ZStack {
                                Look.panel
                                if renderedKey == previewKey, let displayed = showOriginal ? original : rendered {
                                    Image(uiImage: displayed).resizable().scaledToFit()
                                        .accessibilityLabel("\(sample.title) sample, \(showOriginal ? "original" : selectedStock.name)")
                                } else if let previewError {
                                    VStack { Image(systemName: "photo"); Text(previewError).font(.caption); Button("Retry") { Task { await loadPreview() } } }.padding()
                                } else { ProgressView("Rendering film…") }
                            }
                            .aspectRatio(4.0/3, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            Picker("Compare", selection: $showOriginal) {
                                Text("Film").tag(false); Text("Original").tag(true)
                            }.pickerStyle(.segmented)
                            Picker("Sample photograph", selection: $sample) {
                                ForEach(SampleScene.allCases) { scene in Text(scene.title).tag(scene) }
                            }.pickerStyle(.segmented)
                            Text("GRAIN").font(.system(.caption, design: .monospaced)).tracking(2)
                            Picker("Film grain", selection: $selectedGrain) {
                                ForEach(FilmGrain.allCases) { grain in Text(grain.name).tag(grain) }
                            }.pickerStyle(.segmented)
                            Text(selectedGrain.note).font(.caption).foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(selectedStock.name).font(.system(.title3, design: .monospaced)).bold().foregroundStyle(Look.stock(selectedStock))
                                Text(selectedStock.note).font(.caption).foregroundStyle(.secondary)
                            }
                            Text("Built-in samples use the same film processing as your photographs. Your shooting viewfinder stays natural.")
                                .font(.caption).foregroundStyle(.secondary)
                        }.id("preview")

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(FilmStock.allCases) { stock in
                                Button {
                                    selectedStock = stock
                                    showOriginal = false
                                    withAnimation { scroll.scrollTo("preview", anchor: .top) }
                                } label: {
                                    HStack(spacing: 8) {
                                        RoundedRectangle(cornerRadius: 3).fill(Look.stock(stock)).frame(width: 6)
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(stock.name).font(.system(size: 12, weight: .bold, design: .monospaced))
                                            Text(stock.note).font(.system(size: 10)).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                                        }.frame(maxWidth: .infinity, alignment: .leading)
                                        if stock == selectedStock { Image(systemName: "checkmark.circle.fill").foregroundStyle(Look.accent).font(.caption) }
                                    }.padding(12).frame(maxWidth: .infinity, minHeight: 90, alignment: .leading)
                                        .background(Look.panel, in: RoundedRectangle(cornerRadius: 10))
                                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(stock == selectedStock ? Look.accent : .clear, lineWidth: 1.5))
                                }.buttonStyle(.plain).accessibilityAddTraits(stock == selectedStock ? .isSelected : [])
                            }
                        }
                        Text("Choosing a preview does not load a roll. Tap Load film when you're ready. Stock and grain stay with all 36 exposures; stock numbers aren't a forced sensor ISO.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(18).frame(maxWidth: 600).frame(maxWidth: .infinity)
                }
                .background(Look.background)
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    let stock = selectedStock
                    let grain = selectedGrain
                    Task { await model.newRoll(stock, grain: grain); if model.active != nil { dismiss() } }
                } label: {
                    HStack { if model.busy { ProgressView() }; Text("Load \(selectedStock.name) · \(selectedGrain.name) grain").font(.subheadline.bold()) }
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                }.buttonStyle(.borderedProminent)
                    .disabled(model.busy || !model.loaded || model.active != nil)
                    .padding(.horizontal, 18).padding(.vertical, 10).background(.ultraThinMaterial)
            }
            .navigationTitle("Choose film").navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
            .task(id: previewKey) { await loadPreview() }
            .onChange(of: selectedGrain) { _, _ in showOriginal = false }
        }.tint(Look.accent)
    }

    @MainActor private func loadPreview() async {
        let key = previewKey
        let scene = sample
        let stock = selectedStock
        let grain = selectedGrain
        renderedKey = nil; previewError = nil
        do {
            let images = try await SamplePreviews.shared.images(scene: scene, stock: stock, grain: grain)
            guard !Task.isCancelled, previewKey == key else { return }
            original = images.original; rendered = images.film; renderedKey = key
        } catch {
            guard !Task.isCancelled, previewKey == key else { return }
            previewError = "Sample preview unavailable. Please retry."
        }
    }
}

enum SampleScene: String, CaseIterable, Identifiable {
    case clouds, river, aurora, motorsport
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

// Bounded, in-memory cache; previewing never touches a user's film library.
actor SamplePreviews {
    static let shared = SamplePreviews()
    struct Pair { let original: UIImage; let film: UIImage }
    private let processor = FilmProcessor()
    private let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 32 * 1024 * 1024
        cache.countLimit = 12
        return cache
    }()
    func images(scene: SampleScene, stock: FilmStock, grain: FilmGrain) throws -> Pair {
        try Task.checkCancellation()
        guard let url = Bundle.main.url(forResource: scene.rawValue, withExtension: "png", subdirectory: "PreviewSamples") else { throw RollError.invalidData }
        let key = "\(scene.rawValue)/\(stock.rawValue)/\(grain.rawValue)" as NSString
        let originalKey = "\(scene.rawValue)/original" as NSString
        return try autoreleasepool {
            let data = try Data(contentsOf: url)
            let original = try cache.object(forKey: originalKey) ?? thumbnail(data)
            cache.setObject(original, forKey: originalKey, cost: 1200 * 900 * 4)
            if let film = cache.object(forKey: key) { return Pair(original: original, film: film) }
            let processed = try processor.render(data, stock: stock, grain: grain)
            try Task.checkCancellation()
            let film = try thumbnail(processed)
            cache.setObject(film, forKey: key, cost: 1200 * 900 * 4)
            return Pair(original: original, film: film)
        }
    }
    private func thumbnail(_ data: Data) throws -> UIImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 1200,
            kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { throw RollError.invalidData }
        return UIImage(cgImage: cg)
    }
}

struct OptionsView: View {
    @ObservedObject var camera: Camera
    @Binding var options: CameraOptions
    @Binding var grid: Bool
    @Binding var timerSeconds: Int
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("Capture") {
                    Picker("Flash", selection: $options.flash) { ForEach(["Off", "Auto", "On"], id: \.self) { Text($0) } }
                        .disabled(!camera.supportsFlash || options.manualExposure)
                    if options.manualExposure { Text("Flash is unavailable with manual exposure.").font(.caption).foregroundStyle(.secondary) }
                    Picker("Self-timer", selection: $timerSeconds) {
                        Text("Off").tag(0); Text("3 seconds").tag(3); Text("10 seconds").tag(10)
                    }
                    Toggle("Viewfinder grid", isOn: $grid)
                }
                Section {
                    Button("Reset camera controls") { options = CameraOptions() }
                    NavigationLink("Field notes") { GuideView() }
                } footer: {
                    Text("Tap a control below the viewfinder to adjust it. AUTO / M switches between automatic and manual. Changing lenses resets camera settings.")
                }
            }.navigationTitle("Options").navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("Done") { dismiss() } }
        }.tint(Look.accent)
    }
}

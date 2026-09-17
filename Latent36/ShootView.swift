import SwiftUI
import UIKit

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

    var body: some View {
        NavigationStack {
            ZStack {
                Look.background.ignoresSafeArea()
                GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 16) {
                        header
                        ZStack {
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
                                        Button("Open Settings") {
                                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                                        }
                                    } else if camera.message != nil { Button("Retry camera") { camera.start() } }
                                }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity).background(.black.opacity(0.8))
                            }
                            if countdown > 0 { Text("\(countdown)").font(.system(size: 82, weight: .light, design: .monospaced)).shadow(radius: 8).allowsHitTesting(false) }
                            VStack { Spacer(); HStack {
                                Text("OPTICAL VIEW · FILM REVEALED AFTER DEVELOPMENT")
                                    .font(.system(size: 8, weight: .medium, design: .monospaced)).tracking(0.5)
                            }.padding(8).background(.black.opacity(0.55)) }.allowsHitTesting(false)
                        }
                        .aspectRatio(3.0/4, contentMode: .fit)
                        .frame(height: min((min(geometry.size.width, 480) - 36) * 4 / 3, max(220, geometry.size.height - 290)))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Look.paper.opacity(0.15)))

                        HStack(spacing: 8) {
                            ForEach(camera.lenses) { lens in
                                Button(lens.title) {
                                    options = CameraOptions()
                                    camera.switchLens(lens.id)
                                }
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12).padding(.vertical, 10)
                                .background(camera.selectedLens == lens.id ? Look.accent : Look.panel, in: Capsule())
                                .foregroundStyle(camera.selectedLens == lens.id ? .black : Look.paper)
                            }
                        }.disabled(model.busy || countdown > 0 || !camera.ready)

                        HStack {
                            Button { showControls = true } label: {
                                VStack(spacing: 5) { Image(systemName: "slider.horizontal.3").font(.title2); Text("Controls").font(.caption2) }.frame(width: 80)
                            }.disabled(model.busy || countdown > 0 || !camera.ready)
                            Spacer()
                            Button(action: shutter) {
                                ZStack {
                                    Circle().stroke(Look.paper.opacity(0.65), lineWidth: 2).frame(width: 78, height: 78)
                                    Circle().fill(model.active?.canShoot == true ? Look.accent : Look.panel).frame(width: 64, height: 64)
                                    if model.busy { ProgressView().tint(.black) }
                                    else { Image(systemName: countdown > 0 ? "xmark" : "camera.aperture").font(.title).foregroundStyle(.black) }
                                }
                            }
                            .accessibilityLabel(countdown > 0 ? "Cancel timer" : "Take photograph")
                            .disabled(model.busy || !camera.ready || model.active?.canShoot != true)
                            Spacer()
                            VStack(spacing: 5) {
                                Text(String(format: "%02d", model.active?.frames.count ?? 0)).font(.system(size: 28, weight: .medium, design: .monospaced))
                                Text("OF 36").font(.system(size: 9, design: .monospaced)).tracking(2)
                            }.frame(width: 80).accessibilityLabel("\(model.active?.frames.count ?? 0) of 36 exposures")
                        }
                        if !model.loaded {
                            Button("Retry opening film library") { Task { await model.load() } }
                        } else if model.active == nil {
                            Button("Load a new roll") { showFilms = true }.buttonStyle(.borderedProminent)
                        } else if model.active?.canDevelop == true {
                            Button("Develop roll · 24 hours") { confirmDevelop = true }.buttonStyle(.borderedProminent)
                        } else {
                            Text(model.busy ? "Sealing your exposure…" : "No previews. No retakes. Make it count.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(18).frame(maxWidth: 480).frame(maxWidth: .infinity)
                }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showFilms) { FilmPicker() }
            .sheet(isPresented: $showControls) {
                ControlsView(camera: camera, options: $options, grid: $grid, timerSeconds: $timerSeconds)
            }
            .confirmationDialog("Start developing?", isPresented: $confirmDevelop, titleVisibility: .visible) {
                Button("Develop all 36 exposures") { if let roll = model.active { Task { await model.develop(roll) } } }
            } message: { Text("Your photographs will unlock 24 hours from now. You can close the app and shoot another roll while you wait.") }
        }
        .onAppear {
            UIDevice.current.beginGeneratingDeviceOrientationNotifications(); syncCamera()
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--show-film-picker") { showFilms = true }
            #endif
        }
        .onDisappear { cancelTimer(); camera.stop(); UIDevice.current.endGeneratingDeviceOrientationNotifications() }
        .onChange(of: camera.selectedLens) { _, _ in
            options.iso = min(max(options.iso, camera.isoRange.lowerBound), camera.isoRange.upperBound)
            options.shutter = min(max(options.shutter, camera.shutterRange.lowerBound), camera.shutterRange.upperBound)
        }
        .onChange(of: isSelected) { _, _ in syncCamera() }
        .onChange(of: phase) { _, _ in syncCamera() }
    }
    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("LATENT / 36").font(.system(size: 22, weight: .black, design: .monospaced)).tracking(-1)
                Text("A LITTLE PATIENCE. A REAL MEMORY.").font(.system(size: 8, design: .monospaced)).tracking(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 5) {
                Circle().fill(model.active.map { Look.stock($0.stock) } ?? .gray).frame(width: 7, height: 7)
                Text(model.active?.stock.name ?? "NO FILM").font(.system(size: 10, weight: .bold, design: .monospaced))
            }
        }.foregroundStyle(Look.paper)
    }
    private func syncCamera() {
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
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Choose the look for all 36 exposures. Film is applied to your saved photos; the viewfinder stays natural.")
                }
                ForEach(FilmStock.allCases) { stock in
                    Button {
                        Task { await model.newRoll(stock); if model.active != nil { dismiss() } }
                    } label: {
                        HStack(spacing: 16) {
                            RoundedRectangle(cornerRadius: 7).fill(Look.stock(stock)).frame(width: 36, height: 52)
                                .overlay(Text("36").font(.system(.headline, design: .monospaced)).foregroundStyle(.black))
                            VStack(alignment: .leading, spacing: 6) {
                                Text(stock.name).font(.system(.headline, design: .monospaced)).foregroundStyle(Look.paper)
                                Text(stock.note).font(.caption).foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, 8)
                    }.disabled(model.busy || !model.loaded || model.active != nil)
                }
                Section { Text("Stock numbers describe the creative look, not a locked sensor ISO. Use camera controls to set the actual exposure.").font(.caption) }
            }.navigationTitle("Load film").toolbar { Button("Done") { dismiss() } }
        }.tint(Look.accent)
    }
}

struct ControlsView: View {
    @ObservedObject var camera: Camera
    @Binding var options: CameraOptions
    @Binding var grid: Bool
    @Binding var timerSeconds: Int
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("Exposure") {
                    Toggle("Manual ISO & shutter", isOn: $options.manualExposure).disabled(!camera.supportsManual)
                    if options.manualExposure {
                        slider("ISO", value: $options.iso, range: camera.isoRange, label: "\(Int(options.iso))")
                        VStack(alignment: .leading) {
                            Text("Shutter · \(shutterLabel)")
                            Slider(value: Binding(get: { log2(min(max(options.shutter, camera.shutterRange.lowerBound), camera.shutterRange.upperBound)) }, set: { options.shutter = pow(2, $0) }), in: log2(camera.shutterRange.lowerBound)...log2(camera.shutterRange.upperBound))
                        }
                        Text("Manual exposure disables flash and prioritizes your chosen shutter/ISO over computational photo processing.").font(.caption).foregroundStyle(.secondary)
                    } else { slider("Exposure compensation", value: $options.ev, range: camera.evRange, label: String(format: "%+.1f EV", options.ev)) }
                }
                Section("Focus") {
                    Toggle("Manual focus", isOn: $options.manualFocus).disabled(!camera.supportsFocus)
                    if options.manualFocus { slider("Near → Far", value: $options.focus, range: 0...1, label: String(format: "%.2f", options.focus)) }
                    else { Text("Tap the viewfinder to focus and meter. Tap again to move the focus point.").font(.caption).foregroundStyle(.secondary) }
                }
                Section("White balance") {
                    Toggle("Manual white balance", isOn: $options.manualWB).disabled(!camera.supportsWB)
                    if options.manualWB { slider("Temperature", value: $options.kelvin, range: 2500...9000, label: "\(Int(options.kelvin)) K") }
                }
                Section("Framing & capture") {
                    VStack(alignment: .leading) {
                        Text(String(format: "Digital zoom · %.1f×", Double(options.zoom)))
                        Slider(value: $options.zoom, in: 1...max(1.01, camera.maxZoom))
                    }
                    Picker("Flash", selection: $options.flash) { ForEach(["Off", "Auto", "On"], id: \.self) { Text($0) } }
                        .disabled(!camera.supportsFlash || options.manualExposure)
                    Toggle("Rule-of-thirds grid", isOn: $grid)
                    Picker("Self-timer", selection: $timerSeconds) {
                        Text("Off").tag(0); Text("3 seconds").tag(3); Text("10 seconds").tag(10)
                    }
                    Text("Switching lenses resets camera controls. Controls unavailable on the selected lens are disabled.").font(.caption).foregroundStyle(.secondary)
                }
                Button("Reset camera controls") { options = CameraOptions() }
            }
            .navigationTitle("Camera controls")
            .toolbar { Button("Done") { dismiss() } }
            .onChange(of: options.manualExposure) { _, _ in camera.apply(options) }
            .onChange(of: options.iso) { _, _ in camera.apply(options) }
            .onChange(of: options.shutter) { _, _ in camera.apply(options) }
            .onChange(of: options.ev) { _, _ in camera.apply(options) }
            .onChange(of: options.manualFocus) { _, _ in camera.apply(options) }
            .onChange(of: options.focus) { _, _ in camera.apply(options) }
            .onChange(of: options.manualWB) { _, _ in camera.apply(options) }
            .onChange(of: options.kelvin) { _, _ in camera.apply(options) }
            .onChange(of: options.flash) { _, _ in camera.apply(options) }
            .onChange(of: options.zoom) { _, _ in camera.apply(options) }
        }.tint(Look.accent)
    }
    private var shutterLabel: String { options.shutter >= 1 ? "1 s" : "1/\(Int((1/options.shutter).rounded())) s" }
    private func slider(_ title: String, value: Binding<Float>, range: ClosedRange<Float>, label: String) -> some View {
        VStack(alignment: .leading) { HStack { Text(title); Spacer(); Text(label).monospacedDigit().foregroundStyle(Look.accent) }; Slider(value: value, in: range) }
    }
}

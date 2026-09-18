import SwiftUI
import ImageIO

struct LabView: View {
    @EnvironmentObject var model: AppModel
    @State private var showFilms = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("GOOD THINGS\nTAKE A DAY.")
                        .font(.system(size: 34, weight: .black, design: .monospaced)).tracking(-1)
                        .foregroundStyle(Look.paper).padding(.top, 12)
                    Text("36 moments. One film. No peeking.").foregroundStyle(.secondary)
                    if model.rolls.isEmpty {
                        ContentUnavailableView("Your first roll awaits", systemImage: "film", description: Text("Load film in the camera. After 36 exposures, tap Develop to begin the 24-hour wait."))
                    }
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        VStack(spacing: 14) {
                            ForEach(model.rolls.reversed()) { roll in
                                if roll.isReady(at: context.date) {
                                    NavigationLink { ContactSheet(roll: roll) } label: { RollCard(roll: roll, now: context.date) }.buttonStyle(.plain)
                                } else { RollCard(roll: roll, now: context.date) }
                            }
                        }
                    }
                    if model.loaded && model.active == nil {
                        Button("Load another roll") { showFilms = true }.buttonStyle(.borderedProminent)
                        Text("You can shoot while other rolls develop.").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(22).frame(maxWidth: 600).frame(maxWidth: .infinity)
            }
            .background(Look.background)
            .navigationTitle("Darkroom").navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showFilms) { FilmPicker() }
        }
    }
}

struct RollCard: View {
    let roll: Roll
    let now: Date
    @EnvironmentObject var model: AppModel
    @State private var confirm = false
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(roll.stock.name, systemImage: "film").font(.system(.headline, design: .monospaced))
                Spacer()
                Text("\(roll.frames.count)/36").font(.system(.callout, design: .monospaced))
            }.foregroundStyle(Look.stock(roll.stock))
            Text(roll.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
            if let readyAt = roll.readyAt {
                if roll.isReady(at: now) {
                    HStack { Text("Developed. Open your photographs."); Spacer(); Image(systemName: "arrow.up.right") }.foregroundStyle(Look.paper)
                } else {
                    Text(remaining(readyAt)).font(.system(size: 30, weight: .light, design: .monospaced)).foregroundStyle(Look.paper)
                    ProgressView(value: max(0, min(1, 1 - readyAt.timeIntervalSince(now) / Roll.developmentTime))).tint(Look.accent)
                    Text("Ready \(readyAt.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                }
            } else if roll.canDevelop {
                Button("Develop · 24 hours") { confirm = true }.buttonStyle(.borderedProminent).disabled(model.busy)
            } else {
                Text("In the camera · \(36 - roll.frames.count) exposures left").font(.callout)
                ProgressView(value: Double(roll.frames.count), total: 36).tint(Look.accent)
            }
        }
        .padding(20).background(Look.panel, in: RoundedRectangle(cornerRadius: 14))
        .confirmationDialog("Develop this roll?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Start 24-hour development") { Task { await model.develop(roll) } }
        } message: { Text("All 36 photographs stay hidden until development finishes. The timer continues with the app closed.") }
    }
    private func remaining(_ date: Date) -> String {
        let seconds = Int(max(0, ceil(date.timeIntervalSince(now))))
        return String(format: "%02d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
    }
}

struct ContactSheet: View {
    @EnvironmentObject var model: AppModel
    let roll: Roll
    var body: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 16) {
                ForEach(Array(roll.frames.enumerated()), id: \.element) { index, frame in
                    NavigationLink { PhotoView(roll: roll, frame: frame, number: index + 1) } label: {
                        VStack(spacing: 5) {
                            FrameImage(rollID: roll.id, frame: frame, pixels: 420)
                                .aspectRatio(3.0/4, contentMode: .fit).clipped()
                            Text(String(format: "%02d", index + 1)).font(.system(.caption2, design: .monospaced)).foregroundStyle(Look.accent)
                        }
                    }.buttonStyle(.plain)
                }
            }.padding()
        }
        .background(Look.background)
        .navigationTitle(roll.stock.name).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button { Task { await model.saveToPhotos(roll, frames: roll.frames) } } label: {
                if model.busy { ProgressView() } else { Label("Save roll", systemImage: "square.and.arrow.down") }
            }.disabled(model.busy)
        }
    }
}

struct PhotoView: View {
    @EnvironmentObject var model: AppModel
    let roll: Roll
    let frame: String
    let number: Int
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            FrameImage(rollID: roll.id, frame: frame, pixels: 2400).aspectRatio(contentMode: .fit)
            Text("\(roll.stock.name) / FRAME \(number)").font(.system(.caption, design: .monospaced)).foregroundStyle(Look.accent)
            Spacer()
            Button {
                Task { await model.saveToPhotos(roll, frames: [frame]) }
            } label: {
                Label(model.busy ? "Saving…" : "Save full-resolution photo", systemImage: "square.and.arrow.down")
            }.buttonStyle(.borderedProminent).disabled(model.busy).padding(.bottom)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Look.background)
            .navigationTitle("Frame \(number)").navigationBarTitleDisplayMode(.inline)
    }
}

struct FrameImage: View {
    @EnvironmentObject var model: AppModel
    let rollID: UUID
    let frame: String
    let pixels: Int
    @State private var image: UIImage?
    @State private var failed = false
    var body: some View {
        ZStack {
            Look.panel
            if let image { Image(uiImage: image).resizable().scaledToFit() }
            else if failed { Image(systemName: "exclamationmark.triangle").accessibilityLabel("Photograph unavailable") }
            else { ProgressView() }
        }
        .task(id: frame) {
            do {
                let data = try await model.vault.photo(rollID: rollID, frame: frame)
                let decoded = await Task.detached(priority: .utility) { () -> UIImage? in
                    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                          let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                            kCGImageSourceCreateThumbnailFromImageAlways: true,
                            kCGImageSourceThumbnailMaxPixelSize: pixels,
                            kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { return nil }
                    return UIImage(cgImage: cg)
                }.value
                if !Task.isCancelled { image = decoded; failed = decoded == nil }
            } catch { failed = true }
        }
    }
}

struct GuideView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("The ritual") {
                    Text("1. Load a stock. Its look stays with the entire roll.\n\n2. Shoot 36 photographs. There are no previews, imports, or retakes.\n\n3. Tap Develop. Your 24-hour wait starts when you confirm—not when you take the last shot.\n\n4. Return to the Darkroom to see and save your photographs.")
                }
                Section("Camera notes") {
                    Text("Tap the viewfinder to focus and meter. Tap ISO, SPEED, FOCUS, WB, EV or ZOOM below the viewfinder to adjust it without leaving the camera. Tap AUTO / M for manual control. Open Options for flash, grid and timer. Available controls depend on the lens. Switching lenses resets camera settings.")
                    Text("Hold the phone sideways to take landscape photographs. The controls stay upright in portrait. A naturally colored viewfinder helps you judge exposure; film recipes are applied to the saved image.")
                    Text("Daylight is soft and warm. Amber adds golden tones and cool shadows. Chrome is punchy and saturated. Silver is monochrome with more grain. These are original digital recipes, not exact reproductions of commercial film stocks.")
                    Text("Meadow brings lush greens; Coast is cool and airy; Dusk pairs teal shadows with warm color; Faded is matte and pastel; Sepia is warm monochrome; Noir is bold black and white. Before loading a roll, try all ten stocks on four built-in samples and compare Film with Original. Sample browsing never exposes your own undeveloped photos.")
                }
                Section("LiveContainer & SideStore") {
                    Text("Use LiveContainer's normal full-screen launch. Allow camera access when prompted; iOS may show LiveContainer's name. To export developed photographs, allow Photos access too. No microphone, JIT, app extensions, or special entitlements are required.")
                    Text("If the preview remains black, check Camera permission for LiveContainer in iOS Settings, close other camera apps, then reopen. If it still fails, install the IPA directly through SideStore. A direct install uses its own app slot and needs refreshing, but has independent camera permissions and lifecycle.")
                    Text("Each installation has its own film library. Moving between LiveContainer and a direct installation does not transfer rolls. Keep the existing installation until all photographs are developed and exported.")
                }
                Section("Your photographs") {
                    Text("Photos stay on this device in encrypted app storage. Nothing is uploaded. Camera permission is needed to shoot; Photos permission is requested only when you export. There are no ads, analytics, accounts, or purchases.")
                    Text("Development continues while the app is closed using a saved deadline. Keep automatic date and time enabled. This offline wait is part of the experience, not a tamper-proof time lock.")
                    Text("Deleting this app or its LiveContainer data also deletes your rolls. Export developed photos before removing it. Repeated saves create additional copies in Photos.")
                }
            }.navigationTitle("Field notes")
        }
    }
}

import SwiftUI
import Photos
import ImageIO

@MainActor final class AppModel: ObservableObject {
    let vault = Vault()
    @Published var rolls: [Roll] = []
    @Published var loaded = false
    @Published var busy = false
    @Published var error: String?
    @Published var notice: String?
    var active: Roll? { rolls.first { $0.developStartedAt == nil } }

    func load() async {
        do { rolls = try await vault.load(); loaded = true }
        catch { self.error = "Your film library could not be opened. Nothing has been reset. \(error.localizedDescription)" }
    }
    func newRoll(_ stock: FilmStock) async {
        guard loaded, !busy else { return }
        busy = true; defer { busy = false }
        do { rolls = try await vault.newRoll(stock: stock) }
        catch { self.error = error.localizedDescription }
    }
    func develop(_ roll: Roll) async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        do { rolls = try await vault.develop(roll.id); notice = "Your roll is in the lab. Come back in 24 hours." }
        catch { self.error = error.localizedDescription }
    }
    func saveCapture(_ result: Result<Data, Error>, rollID: UUID) async {
        defer { busy = false }
        do {
            rolls = try await vault.capture(result.get(), rollID: rollID)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } catch { self.error = "Exposure not saved; your counter has not advanced. \(error.localizedDescription)" }
    }
    func saveToPhotos(_ roll: Roll, frames: [String]) async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            error = "Allow Photos access in iOS Settings to save developed pictures. Inside LiveContainer, check the host app's Photos permission."
            return
        }
        var saved = 0
        do {
            for frame in frames {
                let data = try await vault.photo(rollID: roll.id, frame: frame)
                try await PHPhotoLibrary.shared().performChanges {
                    let request = PHAssetCreationRequest.forAsset()
                    request.addResource(with: .photo, data: data, options: nil)
                }
                saved += 1
            }
            notice = "Saved \(saved) photograph\(saved == 1 ? "" : "s") to Photos."
        } catch { self.error = "Saved \(saved) of \(frames.count). \(error.localizedDescription)" }
    }
}

@main struct Latent36App: App {
    @StateObject private var model = AppModel()
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(model).preferredColorScheme(.dark)
                .task { await model.load() }
        }
    }
}

enum Look {
    static let background = Color(red: 0.065, green: 0.065, blue: 0.06)
    static let panel = Color(red: 0.12, green: 0.12, blue: 0.105)
    static let paper = Color(red: 0.94, green: 0.91, blue: 0.83)
    static let accent = Color(red: 0.96, green: 0.61, blue: 0.24)
    static func stock(_ stock: FilmStock) -> Color {
        switch stock { case .daylight: return .yellow; case .amber: return .orange
        case .chrome: return .mint; case .silver: return .gray }
    }
}

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @State private var selectedTab = 0
    var body: some View {
        TabView(selection: $selectedTab) {
            ShootView(isSelected: selectedTab == 0).tabItem { Label("Camera", systemImage: "camera") }.tag(0)
            LabView().tabItem { Label("Darkroom", systemImage: "film.stack") }.tag(1)
            GuideView().tabItem { Label("Field notes", systemImage: "book.closed") }.tag(2)
        }
        .tint(Look.accent)
        .alert("Something needs attention", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
        .alert("Latent 36", isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })) {
            Button("OK") { model.notice = nil }
        } message: { Text(model.notice ?? "") }
    }
}

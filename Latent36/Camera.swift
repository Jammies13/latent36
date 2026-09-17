import AVFoundation
import SwiftUI
import UIKit

struct CameraOptions {
    var manualExposure = false
    var iso: Float = 100
    var shutter: Double = 1.0 / 125
    var ev: Float = 0
    var manualFocus = false
    var focus: Float = 0.5
    var manualWB = false
    var kelvin: Float = 5500
    var flash = "Off"
    var zoom: CGFloat = 1
}

struct LensChoice: Identifiable {
    var id: String
    var title: String
}

final class Camera: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "latent36.camera", qos: .userInitiated)
    private let output = AVCapturePhotoOutput()
    private var input: AVCaptureDeviceInput?
    private var devices: [AVCaptureDevice] = []
    private var completion: ((Result<Data, Error>) -> Void)?
    private var photoData: Data?
    private var photoError: Error?
    private var observers: [NSObjectProtocol] = []
    private var wanted = false
    private var capturing = false
    private var options = CameraOptions()
    @Published var ready = false
    @Published var message: String?
    @Published var denied = false
    @Published var lenses: [LensChoice] = []
    @Published var selectedLens = ""
    @Published var isoRange: ClosedRange<Float> = 25...1600
    @Published var shutterRange: ClosedRange<Double> = (1.0/8000)...1
    @Published var evRange: ClosedRange<Float> = -3...3
    @Published var maxZoom: CGFloat = 5
    @Published var supportsManual = false
    @Published var supportsFocus = false
    @Published var supportsWB = false
    @Published var supportsFlash = false

    override init() {
        super.init()
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: nil) { [weak self] _ in
            self?.publish { $0.ready = false; $0.message = "Camera interrupted. Close other camera apps and return to full-screen mode." }
        })
        observers.append(nc.addObserver(forName: AVCaptureSession.interruptionEndedNotification, object: session, queue: nil) { [weak self] _ in self?.resume() })
        observers.append(nc.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil) { [weak self] note in
            let error = note.userInfo?[AVCaptureSessionErrorKey] as? AVError
            if error?.code == .mediaServicesWereReset { self?.resume() }
            else { self?.publish { $0.ready = false; $0.message = error?.localizedDescription ?? "Camera unavailable. Try reopening the app." } }
        })
    }
    deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    private func publish(_ action: @escaping (Camera) -> Void) {
        DispatchQueue.main.async { [weak self] in if let self { action(self) } }
    }
    func start() {
        queue.async { self.wanted = true }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: resume()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted { self?.resume() } else { self?.permissionDenied() }
            }
        default: permissionDenied()
        }
    }
    private func permissionDenied() {
        publish { $0.denied = true; $0.ready = false; $0.message = "Allow Camera in iOS Settings. In LiveContainer, permission may be listed under LiveContainer." }
    }
    private func resume() {
        queue.async {
            guard self.wanted else { return }
            do {
                if self.input == nil { try self.configure() }
                if !self.session.isRunning { self.session.startRunning() }
                self.publish { $0.denied = false; $0.ready = self.session.isRunning; $0.message = self.session.isRunning ? nil : "Camera unavailable. Try a full-screen launch or direct SideStore installation." }
            } catch { self.publish { $0.message = error.localizedDescription; $0.ready = false } }
        }
    }
    func stop() {
        queue.async {
            self.wanted = false
            if self.session.isRunning { self.session.stopRunning() }
            self.publish { $0.ready = false }
        }
    }
    private func configure() throws {
        devices = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .builtInUltraWideCamera, .builtInTelephotoCamera], mediaType: .video, position: .unspecified).devices
        guard let first = devices.first(where: { $0.position == .back && $0.deviceType == .builtInWideAngleCamera }) ?? devices.first else {
            throw NSError(domain: "Camera", code: 1, userInfo: [NSLocalizedDescriptionKey: "No camera is available on this device."])
        }
        let choices = devices.map { device in
            LensChoice(id: device.uniqueID, title: device.position == .front ? "Selfie" : (device.deviceType == .builtInUltraWideCamera ? "Ultra" : (device.deviceType == .builtInTelephotoCamera ? "Tele" : "Main")))
        }.sorted { $0.title < $1.title }
        publish { $0.lenses = choices }
        session.beginConfiguration()
        session.sessionPreset = .photo
        guard session.canAddOutput(output) else { session.commitConfiguration(); throw RollError.invalidData }
        session.addOutput(output)
        output.maxPhotoQualityPrioritization = .quality
        session.commitConfiguration()
        try install(first)
    }
    private func install(_ device: AVCaptureDevice) throws {
        let next = try AVCaptureDeviceInput(device: device)
        session.beginConfiguration()
        let old = input
        if let old { session.removeInput(old) }
        guard session.canAddInput(next) else {
            if let old, session.canAddInput(old) { session.addInput(old) }
            session.commitConfiguration()
            throw NSError(domain: "Camera", code: 2, userInfo: [NSLocalizedDescriptionKey: "This lens is unavailable."])
        }
        session.addInput(next)
        input = next
        // Prefer <= 12 MP. Larger modes can spike memory inside a guest process.
        let sizes = device.activeFormat.supportedMaxPhotoDimensions
        let candidates = sizes.filter { Int64($0.width) * Int64($0.height) <= 13_000_000 }
        if let dimensions = (candidates.isEmpty ? sizes : candidates).max(by: { Int64($0.width) * Int64($0.height) < Int64($1.width) * Int64($1.height) }) {
            output.maxPhotoDimensions = dimensions
        }
        session.commitConfiguration()
        options = CameraOptions()
        try configureDevice(options)
        let format = device.activeFormat
        let minimum = max(CMTimeGetSeconds(format.minExposureDuration), 1.0/10000)
        let maximum = max(minimum, min(CMTimeGetSeconds(format.maxExposureDuration), 1))
        publish {
            $0.selectedLens = device.uniqueID
            $0.isoRange = format.minISO...format.maxISO
            $0.shutterRange = minimum...maximum
            $0.evRange = max(-3, device.minExposureTargetBias)...min(3, device.maxExposureTargetBias)
            $0.maxZoom = min(6, device.activeFormat.videoMaxZoomFactor)
            $0.supportsManual = device.isExposureModeSupported(.custom)
            $0.supportsFocus = device.isLockingFocusWithCustomLensPositionSupported
            $0.supportsWB = device.isLockingWhiteBalanceWithCustomDeviceGainsSupported
            $0.supportsFlash = device.hasFlash
        }
    }
    func switchLens(_ id: String) {
        publish { $0.ready = false }
        queue.async {
            guard !self.capturing, let device = self.devices.first(where: { $0.uniqueID == id }) else { return }
            do { try self.install(device); self.publish { $0.ready = self.session.isRunning; $0.message = nil } }
            catch { self.publish { $0.message = error.localizedDescription; $0.ready = self.session.isRunning } }
        }
    }
    func apply(_ value: CameraOptions) {
        queue.async {
            guard !self.capturing else { return }
            do { try self.configureDevice(value); self.options = value }
            catch { self.publish { $0.message = error.localizedDescription } }
        }
    }
    private func configureDevice(_ value: CameraOptions) throws {
        guard let device = input?.device else { return }
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }
        let format = device.activeFormat
        if value.manualExposure && device.isExposureModeSupported(.custom) {
            let seconds = min(max(value.shutter, CMTimeGetSeconds(format.minExposureDuration)), CMTimeGetSeconds(format.maxExposureDuration))
            device.setExposureModeCustom(duration: CMTime(seconds: seconds, preferredTimescale: 1_000_000_000), iso: min(max(value.iso, format.minISO), format.maxISO), completionHandler: nil)
        } else if device.isExposureModeSupported(.continuousAutoExposure) {
            device.exposureMode = .continuousAutoExposure
            device.setExposureTargetBias(min(max(value.ev, device.minExposureTargetBias), device.maxExposureTargetBias), completionHandler: nil)
        }
        if value.manualFocus && device.isLockingFocusWithCustomLensPositionSupported {
            device.setFocusModeLocked(lensPosition: min(max(value.focus, 0), 1), completionHandler: nil)
        } else if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
        if value.manualWB && device.isLockingWhiteBalanceWithCustomDeviceGainsSupported {
            var gains = device.deviceWhiteBalanceGains(for: .init(temperature: value.kelvin, tint: 0))
            gains.redGain = min(max(gains.redGain, 1), device.maxWhiteBalanceGain)
            gains.greenGain = min(max(gains.greenGain, 1), device.maxWhiteBalanceGain)
            gains.blueGain = min(max(gains.blueGain, 1), device.maxWhiteBalanceGain)
            device.setWhiteBalanceModeLocked(with: gains, completionHandler: nil)
        } else if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) { device.whiteBalanceMode = .continuousAutoWhiteBalance }
        device.videoZoomFactor = min(max(value.zoom, 1), min(6, format.videoMaxZoomFactor))
        if device.isLowLightBoostSupported { device.automaticallyEnablesLowLightBoostWhenAvailable = !value.manualExposure }
    }
    func focus(at point: CGPoint) {
        queue.async {
            guard !self.capturing, let device = self.input?.device else { return }
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                if !self.options.manualFocus && device.isFocusPointOfInterestSupported && device.isFocusModeSupported(.autoFocus) {
                    device.focusPointOfInterest = point; device.focusMode = .autoFocus
                }
                if !self.options.manualExposure && device.isExposurePointOfInterestSupported && device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposurePointOfInterest = point; device.exposureMode = .continuousAutoExposure
                }
            } catch { self.publish { $0.message = error.localizedDescription } }
        }
    }
    func capture(orientation: UIDeviceOrientation, completion: @escaping (Result<Data, Error>) -> Void) {
        queue.async {
            guard self.session.isRunning, !self.session.isInterrupted, !self.capturing else {
                DispatchQueue.main.async { completion(.failure(RollError.busy)) }; return
            }
            self.capturing = true
            self.completion = completion
            self.photoData = nil; self.photoError = nil
            let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            settings.maxPhotoDimensions = self.output.maxPhotoDimensions
            settings.photoQualityPrioritization = self.options.manualExposure ? .speed : .quality
            let flash: AVCaptureDevice.FlashMode = self.options.flash == "On" ? .on : (self.options.flash == "Auto" ? .auto : .off)
            if !self.options.manualExposure && self.output.supportedFlashModes.contains(flash) { settings.flashMode = flash }
            if let connection = self.output.connection(with: .video) {
                let angle: CGFloat = orientation == .landscapeLeft ? 0 : (orientation == .landscapeRight ? 180 : (orientation == .portraitUpsideDown ? 270 : 90))
                if connection.isVideoRotationAngleSupported(angle) { connection.videoRotationAngle = angle }
                if connection.isVideoMirroringSupported { connection.isVideoMirrored = false }
            }
            self.output.capturePhoto(with: settings, delegate: self)
        }
    }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let data = photo.fileDataRepresentation()
        queue.async { self.photoData = data; self.photoError = error }
    }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        queue.async {
            let result: Result<Data, Error>
            if let error = error ?? self.photoError { result = .failure(error) }
            else if let data = self.photoData { result = .success(data) }
            else { result = .failure(RollError.invalidData) }
            let callback = self.completion
            self.completion = nil; self.photoData = nil; self.capturing = false
            DispatchQueue.main.async { callback?(result) }
        }
    }
}

final class PreviewSurface: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    var onFocus: ((CGPoint) -> Void)?
    private let reticle = UIView()
    override init(frame: CGRect) {
        super.init(frame: frame)
        preview.videoGravity = .resizeAspect
        backgroundColor = .black
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tap(_:))))
        reticle.layer.borderWidth = 1
        reticle.layer.borderColor = UIColor.systemYellow.cgColor
        reticle.isUserInteractionEnabled = false
        reticle.alpha = 0
        addSubview(reticle)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() {
        super.layoutSubviews()
        if let connection = preview.connection, connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
    }
    @objc private func tap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: self)
        onFocus?(preview.captureDevicePointConverted(fromLayerPoint: point))
        reticle.frame = CGRect(x: point.x - 27, y: point.y - 27, width: 54, height: 54)
        reticle.alpha = 1
        UIView.animate(withDuration: 0.7, delay: 0.6) { self.reticle.alpha = 0 }
    }
}
struct CameraPreview: UIViewRepresentable {
    let camera: Camera
    func makeUIView(context: Context) -> PreviewSurface {
        let view = PreviewSurface()
        view.preview.session = camera.session
        view.onFocus = { camera.focus(at: $0) }
        return view
    }
    func updateUIView(_ view: PreviewSurface, context: Context) { view.setNeedsLayout() }
}

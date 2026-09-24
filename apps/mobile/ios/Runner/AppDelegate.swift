import ARKit
import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // The self-test's AR and depth check. See DeviceProbePlugin below.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AlmanacDeviceProbe") {
      DeviceProbePlugin.register(with: registrar)
    }
  }
}

/// The self-test's AR surface and depth check (issue #4), on ARKit.
///
/// Runs one short world-tracking session with no view and reports what it
/// saw: whether ARKit is supported, how many planes it found, and — on phones
/// with LiDAR — whether scene depth frames arrived.
/// `lib/data/device/ar_probe.dart` turns those facts into pass / fail / not
/// supported. Every path answers with a map; nothing here throws into Flutter.
///
/// Lives in this file rather than its own because a new Swift file has to be
/// added to Runner.xcodeproj by hand, and a hand-edited project file is the
/// easiest thing in an iOS build to get subtly wrong.
final class DeviceProbePlugin: NSObject, FlutterPlugin, ARSessionDelegate {
  static let channelName = "za.co.almanac.app/device_probe"

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: channelName, binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(DeviceProbePlugin(), channel: channel)
  }

  // All state is touched on the main queue only: ARSession delivers delegate
  // calls there when its delegateQueue is left nil, and so does the timer.
  private var session: ARSession?
  private var pending: FlutterResult?
  private var timer: Timer?
  private var depthAvailable = false
  private var planes = Set<UUID>()
  private var depthFrames = 0
  private var trackingFrames = 0
  private var sessionError: String?

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "arProbe":
      let args = call.arguments as? [String: Any]
      let timeoutMs = (args?["timeoutMs"] as? NSNumber)?.intValue ?? 20000
      start(timeoutMs: timeoutMs, result: result)
    case "arCancel":
      // The self-test was left, or timed out: end the session now so it stops
      // holding the camera. Answers the pending probe with what it saw so far.
      finish()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func start(timeoutMs: Int, result: @escaping FlutterResult) {
    if pending != nil {
      result(["arAvailable": true, "error": "A check is already running."])
      return
    }
    guard ARWorldTrackingConfiguration.isSupported else {
      result([
        "arAvailable": false,
        "depthAvailable": false,
        "reason": "ARWorldTrackingConfiguration.isSupported is false",
      ])
      return
    }
    let status = AVCaptureDevice.authorizationStatus(for: .video)
    if status == .denied || status == .restricted {
      result([
        "arAvailable": true,
        "cameraPermission": false,
        "depthAvailable": ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth),
      ])
      return
    }

    let configuration = ARWorldTrackingConfiguration()
    configuration.planeDetection = [.horizontal, .vertical]
    depthAvailable = ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
    if depthAvailable {
      configuration.frameSemantics.insert(.sceneDepth)
    }

    planes = []
    depthFrames = 0
    trackingFrames = 0
    sessionError = nil
    pending = result

    let session = ARSession()
    session.delegate = self
    self.session = session
    session.run(configuration, options: [.resetTracking, .removeExistingAnchors])

    timer = Timer.scheduledTimer(
      withTimeInterval: Double(timeoutMs) / 1000, repeats: false
    ) { [weak self] _ in
      self?.finish()
    }
  }

  func session(_ session: ARSession, didUpdate frame: ARFrame) {
    if case .normal = frame.camera.trackingState {
      trackingFrames += 1
    }
    if frame.sceneDepth != nil {
      depthFrames += 1
    }
    if !planes.isEmpty && (!depthAvailable || depthFrames > 0) {
      finish()
    }
  }

  func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
    for anchor in anchors where anchor is ARPlaneAnchor {
      planes.insert(anchor.identifier)
    }
  }

  func session(_ session: ARSession, didFailWithError error: Error) {
    sessionError = error.localizedDescription
    finish()
  }

  private func finish() {
    guard let result = pending else { return }
    pending = nil
    timer?.invalidate()
    timer = nil
    session?.pause()
    session?.delegate = nil
    session = nil

    var facts: [String: Any] = [
      "arAvailable": true,
      "cameraPermission": true,
      "depthAvailable": depthAvailable,
      "planesDetected": planes.count,
      "depthFrames": depthFrames,
      "trackingFrames": trackingFrames,
    ]
    if let error = sessionError {
      facts["error"] = error
    }
    result(facts)
  }
}

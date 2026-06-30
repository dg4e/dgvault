import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  // A .kdbx opened before the Flutter engine is ready is stashed here and
  // handed over when Dart calls getInitialFile.
  private var pendingFile: [String: Any]?
  private var openFileChannel: FlutterMethodChannel?
  private var engineReady = false

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let messenger = engineBridge.pluginRegistry
      .registrar(forPlugin: "DgvaultOpenFile")?.messenger() {
      let channel = FlutterMethodChannel(
        name: "dgvault/open_file", binaryMessenger: messenger)
      channel.setMethodCallHandler { [weak self] call, result in
        if call.method == "getInitialFile" {
          self?.engineReady = true
          result(self?.pendingFile)
          self?.pendingFile = nil
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
      openFileChannel = channel
    }
  }

  /// Called by the SceneDelegate when the OS opens a .kdbx with dgvault.
  func handleOpenedFile(_ url: URL) {
    guard url.isFileURL else { return }
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    guard let data = try? Data(contentsOf: url) else { return }
    let payload: [String: Any] = [
      "name": url.lastPathComponent,
      "bytes": FlutterStandardTypedData(bytes: data),
    ]
    if engineReady, let channel = openFileChannel {
      channel.invokeMethod("openFile", arguments: payload)
    } else {
      pendingFile = payload
    }
  }
}

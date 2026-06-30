import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  // A .kdbx opened before the Flutter engine is ready is stashed here and
  // handed over when Dart calls getInitialFile.
  private var pendingFile: [String: Any]?
  private var openFileChannel: FlutterMethodChannel?
  private var engineReady = false // true once Dart has pulled the initial file

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    if let controller = NSApp.windows
      .compactMap({ $0.contentViewController as? FlutterViewController }).first {
      let channel = FlutterMethodChannel(
        name: "dgvault/open_file",
        binaryMessenger: controller.engine.binaryMessenger)
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
    super.applicationDidFinishLaunching(notification)
  }

  override func application(_ application: NSApplication, open urls: [URL]) {
    handleOpen(urls)
  }

  private func handleOpen(_ urls: [URL]) {
    let url = urls.first(where: { $0.pathExtension.lowercased() == "kdbx" })
      ?? urls.first
    guard let fileURL = url, let data = try? Data(contentsOf: fileURL) else { return }
    let payload: [String: Any] = [
      "name": fileURL.lastPathComponent,
      "bytes": FlutterStandardTypedData(bytes: data),
      "path": fileURL.path,
    ]
    if engineReady, let channel = openFileChannel {
      channel.invokeMethod("openFile", arguments: payload)
    } else {
      pendingFile = payload // not drained yet → Dart picks it up via getInitialFile
    }
  }
}

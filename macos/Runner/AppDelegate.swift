import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  // A .kdbx opened before the Flutter engine is ready is stashed here and
  // handed over when Dart calls getInitialFile.
  private var pendingFile: [String: Any]?
  private var openFileChannel: FlutterMethodChannel?
  private var documentsChannel: FlutterMethodChannel?
  private var engineReady = false // true once Dart has pulled the initial file
  private static let bookmarkPrefix = "bookmark:"

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

      // Security-scoped bookmarks let a sandboxed app reopen a file it was
      // granted access to (via the open/save panel) in a later session — e.g.
      // a "recent" vault on a network volume. A raw path would hit EPERM.
      let docs = FlutterMethodChannel(
        name: "dgvault/documents",
        binaryMessenger: controller.engine.binaryMessenger)
      docs.setMethodCallHandler { [weak self] call, result in
        self?.handleDocuments(call, result)
      }
      documentsChannel = docs
    }
    super.applicationDidFinishLaunching(notification)
  }

  private func handleDocuments(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    switch call.method {
    case "bookmark":
      // Turn a path we currently have access to into a persistable token.
      guard let path = args?["path"] as? String else {
        result(FlutterError(code: "bad_args", message: "path required", details: nil)); return
      }
      do {
        let data = try URL(fileURLWithPath: path).bookmarkData(
          options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        result(AppDelegate.bookmarkPrefix + data.base64EncodedString())
      } catch {
        result(nil) // caller falls back to storing the raw path
      }
    case "read":
      withBookmark(args?["uri"] as? String, result) { url in
        FlutterStandardTypedData(bytes: try Self.coordinatedRead(url))
      }
    case "write":
      guard let bytes = args?["bytes"] as? FlutterStandardTypedData else {
        result(FlutterError(code: "bad_args", message: "bytes required", details: nil)); return
      }
      withBookmark(args?["uri"] as? String, result) { url in
        try Self.coordinatedWrite(url, bytes.data)
        return nil
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Resolve a `bookmark:<base64>` token, run [body] while holding the security
  /// scope, and forward its value (or a Flutter error) to [result].
  private func withBookmark(
    _ token: String?, _ result: @escaping FlutterResult, _ body: (URL) throws -> Any?
  ) {
    guard let token = token, token.hasPrefix(AppDelegate.bookmarkPrefix),
      let data = Data(base64Encoded: String(token.dropFirst(AppDelegate.bookmarkPrefix.count)))
    else {
      result(FlutterError(code: "bad_token", message: "invalid bookmark", details: nil)); return
    }
    do {
      var stale = false
      let url = try URL(
        resolvingBookmarkData: data, options: [.withSecurityScope],
        relativeTo: nil, bookmarkDataIsStale: &stale)
      let scoped = url.startAccessingSecurityScopedResource()
      defer { if scoped { url.stopAccessingSecurityScopedResource() } }
      result(try body(url))
    } catch {
      result(FlutterError(code: "resolve_failed", message: error.localizedDescription, details: nil))
    }
  }

  // NSFileCoordinator keeps reads/writes safe across network volumes & iCloud.
  private static func coordinatedRead(_ url: URL) throws -> Data {
    var coordError: NSError?
    var payload: Result<Data, Error>?
    NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordError) { u in
      payload = Result { try Data(contentsOf: u) }
    }
    if let e = coordError { throw e }
    return try payload!.get()
  }

  private static func coordinatedWrite(_ url: URL, _ data: Data) throws {
    var coordError: NSError?
    var writeError: Error?
    NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordError) { u in
      do { try data.write(to: u, options: .atomic) } catch { writeError = error }
    }
    if let e = coordError { throw e }
    if let e = writeError { throw e }
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

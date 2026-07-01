import Flutter
import UIKit

/// In-place vault open/save on iOS via the OS document picker + security-scoped
/// bookmarks. Mirrors Android's SAF bridge over the same `dgvault/documents`
/// MethodChannel so Dart treats both platforms identically.
///
/// The location token handed back to Dart is `bookmark:<base64>` — the bookmark
/// data itself, so it is stateless and resolves back to the user's file (in the
/// Files app / iCloud / a provider) for later saves without any native registry.
final class DocumentPickerBridge: NSObject, UIDocumentPickerDelegate {
  private static let tokenPrefix = "bookmark:"

  private var pendingResult: FlutterResult?
  private var pendingMode: Mode = .none
  private enum Mode { case none, open, create }

  init(messenger: FlutterBinaryMessenger) {
    super.init()
    let channel = FlutterMethodChannel(
      name: "dgvault/documents", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result)
    }
  }

  // MARK: - Channel

  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    switch call.method {
    case "pickOpen":
      guard pendingResult == nil else {
        result(FlutterError(code: "busy", message: "picker in progress", details: nil)); return
      }
      pendingResult = result
      pendingMode = .open
      presentOpen()
    case "pickCreate":
      guard pendingResult == nil else {
        result(FlutterError(code: "busy", message: "picker in progress", details: nil)); return
      }
      let name = (call.arguments as? [String: Any])?["name"] as? String ?? "vault.kdbx"
      pendingResult = result
      pendingMode = .create
      presentCreate(name)
    case "read":
      let uri = (call.arguments as? [String: Any])?["uri"] as? String ?? ""
      readToken(uri, result)
    case "write":
      let args = call.arguments as? [String: Any]
      let uri = args?["uri"] as? String ?? ""
      let data = (args?["bytes"] as? FlutterStandardTypedData)?.data ?? Data()
      writeToken(uri, data, result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Pickers

  private func presentOpen() {
    // `.open` grants in-place access (a security-scoped URL) to the picked file.
    let picker = UIDocumentPickerViewController(
      documentTypes: ["org.keepass.kdbx", "public.data"], in: .open)
    picker.delegate = self
    picker.allowsMultipleSelection = false
    present(picker)
  }

  private func presentCreate(_ name: String) {
    // Write an empty placeholder to a temp file, then move it out to the
    // user-chosen location. Dart immediately overwrites it with the real
    // encrypted vault via `write`, so the empty file never persists.
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(name)
    do {
      try Data().write(to: tmp, options: .atomic)
    } catch {
      finish(FlutterError(code: "create_failed", message: error.localizedDescription, details: nil))
      return
    }
    let picker = UIDocumentPickerViewController(url: tmp, in: .moveToService)
    picker.delegate = self
    present(picker)
  }

  // MARK: - UIDocumentPickerDelegate

  func documentPicker(
    _ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]
  ) {
    guard let url = urls.first else { finish(nil); return }
    let mode = pendingMode
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    do {
      let token = Self.tokenPrefix + (try url.bookmarkData()).base64EncodedString()
      if mode == .open {
        let data = try coordinatedRead(url)
        finish([
          "uri": token,
          "name": url.lastPathComponent,
          "bytes": FlutterStandardTypedData(bytes: data),
        ])
      } else {
        finish(["uri": token, "name": url.lastPathComponent])
      }
    } catch {
      finish(FlutterError(code: "pick_failed", message: error.localizedDescription, details: nil))
    }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    finish(nil)
  }

  // MARK: - Read / write by token

  private func readToken(_ token: String, _ result: @escaping FlutterResult) {
    do {
      let url = try resolve(token)
      let scoped = url.startAccessingSecurityScopedResource()
      defer { if scoped { url.stopAccessingSecurityScopedResource() } }
      let data = try coordinatedRead(url)
      result(FlutterStandardTypedData(bytes: data))
    } catch {
      result(FlutterError(code: "read_failed", message: error.localizedDescription, details: nil))
    }
  }

  private func writeToken(_ token: String, _ data: Data, _ result: @escaping FlutterResult) {
    do {
      let url = try resolve(token)
      let scoped = url.startAccessingSecurityScopedResource()
      defer { if scoped { url.stopAccessingSecurityScopedResource() } }
      try coordinatedWrite(url, data)
      result(nil)
    } catch {
      result(FlutterError(code: "write_failed", message: error.localizedDescription, details: nil))
    }
  }

  private func resolve(_ token: String) throws -> URL {
    guard token.hasPrefix(Self.tokenPrefix),
      let data = Data(base64Encoded: String(token.dropFirst(Self.tokenPrefix.count)))
    else {
      throw NSError(domain: "dgvault", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "bad bookmark token"])
    }
    var stale = false
    return try URL(
      resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
  }

  // NSFileCoordinator keeps reads/writes safe across document providers & iCloud.
  private func coordinatedRead(_ url: URL) throws -> Data {
    var coordError: NSError?
    var payload: Result<Data, Error>?
    NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordError) { u in
      payload = Result { try Data(contentsOf: u) }
    }
    if let e = coordError { throw e }
    return try payload!.get()
  }

  private func coordinatedWrite(_ url: URL, _ data: Data) throws {
    var coordError: NSError?
    var writeError: Error?
    NSFileCoordinator().coordinate(
      writingItemAt: url, options: .forReplacing, error: &coordError
    ) { u in
      do { try data.write(to: u, options: .atomic) } catch { writeError = error }
    }
    if let e = coordError { throw e }
    if let e = writeError { throw e }
  }

  // MARK: - Presentation

  private func present(_ picker: UIDocumentPickerViewController) {
    guard let host = topViewController() else { finish(nil); return }
    DispatchQueue.main.async { host.present(picker, animated: true) }
  }

  private func topViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes
    let scene = scenes.first { $0.activationState == .foregroundActive } as? UIWindowScene
      ?? scenes.first as? UIWindowScene
    let windows = scene?.windows ?? []
    var vc = (windows.first { $0.isKeyWindow } ?? windows.first)?.rootViewController
    while let presented = vc?.presentedViewController { vc = presented }
    return vc
  }

  private func finish(_ value: Any?) {
    let result = pendingResult
    pendingResult = nil
    pendingMode = .none
    result?(value)
  }
}

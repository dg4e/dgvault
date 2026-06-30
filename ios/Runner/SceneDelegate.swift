import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  // Cold start: a .kdbx the app was launched to open arrives in connectionOptions.
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    forward(connectionOptions.urlContexts)
  }

  // Warm start: app already running, user opens another .kdbx with it.
  override func scene(
    _ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>
  ) {
    forward(URLContexts)
  }

  private func forward(_ contexts: Set<UIOpenURLContext>) {
    guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { return }
    for context in contexts where context.url.isFileURL {
      appDelegate.handleOpenedFile(context.url)
    }
  }
}

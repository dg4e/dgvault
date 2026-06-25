import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // Open at a comfortable size, centered, with a sane minimum.
    let defaultSize = NSSize(width: 1180, height: 760)
    self.minSize = NSSize(width: 720, height: 520)
    self.setContentSize(defaultSize)
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}

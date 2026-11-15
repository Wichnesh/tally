import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    // Open large and centred; don't allow shrinking below 1100 x 720
    // so the week and month calendars stay readable.
    self.minSize = NSSize(width: 1100, height: 720)
    self.setContentSize(NSSize(width: 1360, height: 860))
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}

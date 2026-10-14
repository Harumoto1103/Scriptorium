import Cocoa
import InputMethodKit

// An input method is a background app that vends an IMKServer; the system
// creates one InputController per text client.
let connection = Bundle.main.infoDictionary?["InputMethodConnectionName"] as! String
let server = IMKServer(name: connection, bundleIdentifier: Bundle.main.bundleIdentifier)
_ = server
NSApplication.shared.run()

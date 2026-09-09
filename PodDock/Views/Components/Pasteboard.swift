import Foundation
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Cross-platform clipboard write. Used by row context menus — rows must not
/// carry .textSelection because selectable text swallows clicks and breaks
/// List row selection on macOS.
func copyToPasteboard(_ string: String) {
  #if canImport(AppKit)
  NSPasteboard.general.clearContents()
  NSPasteboard.general.setString(string, forType: .string)
  #elseif canImport(UIKit)
  UIPasteboard.general.string = string
  #endif
}

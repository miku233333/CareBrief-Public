import UIKit

@MainActor
protocol AccessibilityAnnouncing: AnyObject {
  func announce(_ message: String)
}

@MainActor
final class SystemAccessibilityAnnouncer: AccessibilityAnnouncing {
  func announce(_ message: String) {
    UIAccessibility.post(notification: .announcement, argument: message)
  }
}

import UIKit

/// Base class for window covering views used for app snapshot protection.
///
/// Subclass and override `updateLayout(_:)` to add blur, placeholder content,
/// or branding that appears in the iOS task switcher when the app goes to background.
open class AetherWindowCoveringView: UIView {
    open func updateLayout(_ size: CGSize) {
    }
}

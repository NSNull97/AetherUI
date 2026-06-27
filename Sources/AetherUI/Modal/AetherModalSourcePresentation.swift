import UIKit

public protocol AetherModalSourcePresentation: AnyObject {
    var aetherModalSourceFrameInWindow: CGRect? { get set }
    var aetherModalSourceView: UIView? { get set }
}

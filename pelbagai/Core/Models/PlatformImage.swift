import Foundation

#if canImport(UIKit)
import UIKit
public typealias PlatformImage = UIImage
public typealias PlatformColor = UIColor
#elseif canImport(AppKit)
import AppKit
public typealias PlatformImage = NSImage
public typealias PlatformColor = NSColor

// Also provide the system names as internal aliases if they don't exist
// this allows code to use 'UIImage' and 'UIColor' everywhere.
public typealias UIImage = NSImage
public typealias UIColor = NSColor
#endif

import AppKit
import SwiftUI

@MainActor
enum BrandMark {
    static let logo: NSImage? = {
        loadImage(named: "EasyMacBordLogo")
    }()

    static let menuBarLogo: NSImage? = {
        guard let logo = loadImage(named: "EasyMacBordMenuBarTemplate") else {
            return nil
        }
        logo.size = NSSize(width: 18, height: 18)
        logo.isTemplate = true
        return logo
    }()

    static var image: Image {
        if let logo {
            return Image(nsImage: logo)
        }
        return Image(systemName: "keyboard")
    }

    static var menuBarImage: Image {
        if let menuBarLogo {
            return Image(nsImage: menuBarLogo)
        }
        return Image(systemName: "keyboard")
    }

    private static func loadImage(named name: String) -> NSImage? {
        guard let url = Bundle.module.url(forResource: name, withExtension: "png") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }
}

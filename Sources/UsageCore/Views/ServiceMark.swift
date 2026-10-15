import SwiftUI

public struct ServiceMark: View {
    public let service: UsageService

    public init(service: UsageService) { self.service = service }

    public var body: some View {
        Image(nsImage: mark)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .accessibilityHidden(true)
    }

    private var mark: NSImage {
        let resources = Bundle.main.resourceURL.flatMap {
            Bundle(url: $0.appendingPathComponent("UsageRings_UsageCore.bundle"))
        } ?? Bundle.module
        guard let url = resources.url(forResource: service.rawValue, withExtension: "svg", subdirectory: "Resources"),
              let image = NSImage(contentsOf: url) else { return NSImage() }
        return image
    }
}

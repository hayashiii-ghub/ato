import AppKit
import SwiftUI
import UsageCore

/// Renders the production ring view with synthetic data; never starts the host app or reads accounts.
@main
struct WidgetPreview {
    @MainActor static func main() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "dist/widget-preview.png")
        let renderer = ImageRenderer(content: PreviewSheet())
        renderer.scale = 2
        guard var image = renderer.cgImage else {
            throw NSError(domain: "WidgetPreview", code: 1, userInfo: [NSLocalizedDescriptionKey: "SwiftUI rendering failed"])
        }
        if CommandLine.arguments.count > 2 {
            guard let before = NSImage(contentsOfFile: CommandLine.arguments[2]) else {
                throw NSError(domain: "WidgetPreview", code: 3, userInfo: [NSLocalizedDescriptionKey: "Cannot read baseline image"])
            }
            let comparison = ImageRenderer(content: ComparisonSheet(before: before, after: NSImage(cgImage: image, size: .zero)))
            comparison.scale = 2
            guard let result = comparison.cgImage else { throw NSError(domain: "WidgetPreview", code: 4) }
            image = result
        }
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "WidgetPreview", code: 2)
        }
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: output)
        print(output.path)
    }
}

private struct ComparisonSheet: View {
    let before: NSImage
    let after: NSImage

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("ato? · Before / After").font(.title.bold())
            Text("Production SwiftUI views · synthetic fixtures · desktop compositing is not simulated")
                .font(.subheadline)
            HStack(alignment: .top, spacing: 24) {
                panel(before, title: "Before")
                panel(after, title: "After")
            }
        }
        .padding(24)
        .background(.background)
        .environment(\.colorScheme, .light)
    }

    private func panel(_ image: NSImage, title: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Image(nsImage: image).resizable().scaledToFit().frame(width: 880)
        }
    }
}

private enum Fixture: String, CaseIterable {
    case normal = "Normal", missing = "Missing", expired = "Expired", high = "High usage / exhausted"
    case customOrder = "Gemini / custom order / 5-hour selection"

    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    var snapshot: UsageSnapshot {
        if self == .missing { return .empty }
        let used: [Double] = self == .high ? [80, 90, 100, 95] : [24, 18, 59, 13]
        let order: [UsageService] = self == .customOrder
            ? [.gemini, .grokBot, .codex, .claude] : UsageSnapshot.defaultRingOrder
        return UsageSnapshot(services: zip(order, used).map { service, percent in
            let selectsFiveHours = self == .customOrder && service == .gemini
            var windows = [
                UsageWindow(id: service == .claude ? "five_hour" : "total", title: "Usage",
                            usedPercent: percent, resetsAt: nil, period: selectsFiveHours ? .fiveHours : nil)
            ]
            if selectsFiveHours {
                windows.append(UsageWindow(id: "gemini-weekly", title: "Week", usedPercent: 80,
                                           resetsAt: nil, period: .week))
            }
            return ServiceUsage(service: service, state: .ready, windows: windows,
                                updatedAt: Self.now.addingTimeInterval(self == .expired ? -UsageSnapshot.maximumAge : 0),
                                preferredPeriod: selectsFiveHours ? .fiveHours : nil)
        }, ringOrder: order)
    }
}

private struct PreviewSheet: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("ato? · SwiftUI render").font(.title2.bold())
            Text("Synthetic fixtures · small 170 × 170 / medium 360 × 170 pt · 2× scale")
                .font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 24) {
                column(.light)
                column(.dark)
            }
        }
        .padding(24)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.colorScheme, .light)
    }

    private func column(_ scheme: ColorScheme) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(scheme == .light ? "Light" : "Dark").font(.headline)
            ForEach(Fixture.allCases, id: \.self) { fixture in
                VStack(alignment: .leading, spacing: 6) {
                    Text(fixture.rawValue).font(.caption)
                    HStack(spacing: 12) {
                        card(fixture, compact: true)
                        card(fixture, compact: false)
                    }
                }
            }
        }
        .padding(16)
        .background(scheme == .light ? Color(white: 0.9) : Color(white: 0.12), in: RoundedRectangle(cornerRadius: 20))
        .environment(\.colorScheme, scheme)
    }

    private func card(_ fixture: Fixture, compact: Bool) -> some View {
        UsageRingsView(snapshot: fixture.snapshot, date: Fixture.now, compact: compact)
            .padding(compact ? 14 : 18)
            .frame(width: compact ? 170 : 360, height: 170)
            .background(.background, in: RoundedRectangle(cornerRadius: 22))
    }
}

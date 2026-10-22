import AppKit
import Foundation
import SwiftUI

@main
@MainActor
struct IconAssets {
    private static let macArtworkScale = 0.84
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static func main() throws {
        let source = try Data(contentsOf: root.appendingPathComponent("Assets/AppIcon.svg"))
        let document = try XMLDocument(data: source)
        guard let svg = document.rootElement(), svg.name == "svg",
              svg.attribute(forName: "viewBox") != nil else {
            throw AssetError.invalidSVG
        }
        let shapes = try ["track", "ring", "question", "dot"].reduce(into: [String: XMLElement]()) { result, id in
            let matches = (svg.children ?? []).compactMap { $0 as? XMLElement }
                .filter { $0.attribute(forName: "id")?.stringValue == id }
            guard matches.count == 1, let shape = matches.first else { throw AssetError.invalidSVG }
            result[id] = shape
        }
        let light = try Palette(scheme: .light)
        let dark = try Palette(scheme: .dark)
        let ids = ["track", "ring", "question", "dot"]
        let lightSVG = try svgData(svg, shapes: shapes, ids: ids, palette: light)
        let darkSVG = try svgData(svg, shapes: shapes, ids: ids, palette: dark)
        let faviconSVG = try faviconData(darkSVG)
        let faviconPNG = try png(faviconSVG, size: 32)
        var outputs: [(String, Data)] = [
            ("Assets/AppIcon.icon/Assets/light.svg", try svgData(svg, shapes: shapes, ids: ids, palette: light,
                                                              scale: macArtworkScale)),
            ("Assets/AppIcon.icon/Assets/dark.svg", try svgData(svg, shapes: shapes, ids: ids, palette: dark,
                                                             scale: macArtworkScale))
        ]
        let icon: [String: Any] = [
            "fill": ["solid": "extended-srgb:0,0,0,0"],
            "groups": [[
                "blend-mode": "normal", "lighting": "individual",
                "shadow": ["kind": "neutral", "opacity": 0],
                "translucency": ["enabled": false, "value": 0],
                // A native fill override fills stroke interiors; retain SVG paints in one appearance-specific image.
                "layers": [[
                    "image-name-specializations": [
                        ["value": "light.svg"],
                        ["appearance": "dark", "value": "dark.svg"]
                    ], "name": "ato", "glass": false, "hidden": false, "opacity": 1
                ]]
            ]],
            "supported-platforms": ["squares": ["macOS"]]
        ]
        var metadata = try JSONSerialization.data(withJSONObject: icon, options: [.prettyPrinted, .sortedKeys])
        metadata.append(0x0A)
        outputs.append(("Assets/AppIcon.icon/icon.json", metadata))

        let lightPNG = try png(lightSVG, size: 1024)
        outputs += [
            ("Assets/AppIcon.png", lightPNG),
            ("site/public/assets/AppIcon.png", lightPNG),
            ("site/public/assets/AppIcon-dark.png", try png(darkSVG, size: 1024)),
            ("site/public/assets/apple-touch-icon.png", try png(lightSVG, size: 180)),
            ("site/public/assets/favicon-32.png", faviconPNG),
            ("site/public/assets/favicon-32-dark.png", faviconPNG),
            ("site/public/assets/favicon.svg", faviconSVG),
            ("site/public/favicon.ico", try ico(faviconSVG))
        ]
        for (path, data) in outputs {
            let destination = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try data.write(to: destination, options: .atomic)
            print(path)
        }
    }

    private struct RGBA {
        let red, green, blue, alpha: CGFloat

        init(_ color: Color, environment: EnvironmentValues) throws {
            let resolved = color.resolve(in: environment)
            guard let value = NSColor(cgColor: resolved.cgColor)?.usingColorSpace(.sRGB) else {
                throw AssetError.colorResolution
            }
            red = value.redComponent
            green = value.greenComponent
            blue = value.blueComponent
            alpha = value.alphaComponent
        }

        var svgColor: String {
            "rgb(" + [red, green, blue].map { Self.decimal($0 * 255) }.joined(separator: ",") + ")"
        }

        var svgOpacity: String { Self.decimal(alpha) }

        private static func decimal(_ value: CGFloat) -> String {
            String(format: "%.9f", locale: Locale(identifier: "en_US_POSIX"), Double(value))
        }
    }

    private struct Palette {
        let track, ring, mark: RGBA

        init(scheme: ColorScheme) throws {
            var environment = EnvironmentValues()
            environment.colorScheme = scheme
            track = try RGBA(Color.primary.opacity(0.13), environment: environment)
            ring = try RGBA(Color.green, environment: environment)
            mark = try RGBA(Color.primary, environment: environment)
        }

        func color(for id: String) -> RGBA {
            switch id {
            case "track": return track
            case "ring": return ring
            default: return mark
            }
        }
    }

    private static func svgData(_ original: XMLElement, shapes: [String: XMLElement], ids: [String],
                                palette: Palette, scale: Double = 1) throws -> Data {
        let svg = original.copy() as! XMLElement
        for child in svg.children ?? [] { child.detach() }
        set("width", "1024", on: svg)
        set("height", "1024", on: svg)
        let content: XMLElement
        if scale == 1 {
            content = svg
        } else {
            let box = (svg.attribute(forName: "viewBox")?.stringValue ?? "")
                .split { $0.isWhitespace || $0 == "," }.compactMap { Double($0) }
            guard box.count == 4, box.allSatisfy(\.isFinite), box[2] > 0, box[3] > 0 else {
                throw AssetError.invalidSVG
            }
            let x = box[0] + box[2] / 2
            let y = box[1] + box[3] / 2
            content = XMLElement(name: "g")
            // The native enclosure needs an inset; transparent web marks keep their original size.
            set("transform", "translate(\(x) \(y)) scale(\(scale)) translate(\(-x) \(-y))", on: content)
            svg.addChild(content)
        }
        for id in ids {
            guard let shape = shapes[id]?.copy() as? XMLElement else { throw AssetError.invalidSVG }
            let color = palette.color(for: id)
            let channel = id == "track" || id == "ring" ? "stroke" : "fill"
            set(channel, color.svgColor, on: shape)
            set(channel + "-opacity", color.svgOpacity, on: shape)
            content.addChild(shape)
        }
        return XMLDocument(rootElement: svg).xmlData(options: [.nodePrettyPrint])
    }

    private static func set(_ name: String, _ value: String, on element: XMLElement) {
        element.removeAttribute(forName: name)
        element.addAttribute(XMLNode.attribute(withName: name, stringValue: value) as! XMLNode)
    }

    private static func faviconData(_ darkSVG: Data) throws -> Data {
        let document = try XMLDocument(data: darkSVG)
        guard let svg = document.rootElement() else { throw AssetError.invalidSVG }
        guard let track = (svg.children ?? []).compactMap({ $0 as? XMLElement })
            .first(where: { $0.attribute(forName: "id")?.stringValue == "track" }),
              let x = track.attribute(forName: "cx")?.stringValue,
              let y = track.attribute(forName: "cy")?.stringValue,
              let cx = Double(x), let cy = Double(y),
              let radius = Double(track.attribute(forName: "r")?.stringValue ?? ""),
              let stroke = Double(track.attribute(forName: "stroke-width")?.stringValue ?? ""),
              [cx, cy, radius, stroke].allSatisfy(\.isFinite), radius > 0, stroke > 0 else {
            throw AssetError.invalidSVG
        }
        // A tab's background can differ from its preferred color scheme; keep the white mark on black.
        let background = XMLElement(name: "circle")
        for (name, value) in [("id", "background"), ("cx", x), ("cy", y),
                              ("r", String(radius + stroke / 2)), ("fill", "#000")] {
            set(name, value, on: background)
        }
        svg.insertChild(background, at: 0)
        return document.xmlData(options: [.nodePrettyPrint])
    }

    private static func png(_ svg: Data, size: Int) throws -> Data {
        guard let image = NSImage(data: svg),
              let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                                      bytesPerRow: size * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                                        | CGBitmapInfo.byteOrder32Big.rawValue) else {
            throw AssetError.svgRendering
        }
        context.interpolationQuality = .high
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        image.draw(in: NSRect(x: 0, y: 0, width: size, height: size), from: .zero,
                   operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        guard let result = context.makeImage(),
              let data = NSBitmapImageRep(cgImage: result).representation(using: .png, properties: [:]) else {
            throw AssetError.pngEncoding
        }
        return data
    }

    private static func ico(_ svg: Data) throws -> Data {
        let sizes = [16, 32, 48]
        let images = try sizes.map { try png(svg, size: $0) }
        var data = Data([0, 0, 1, 0, UInt8(sizes.count), 0])
        var offset = 6 + sizes.count * 16
        for (size, image) in zip(sizes, images) {
            data.append(contentsOf: [UInt8(size), UInt8(size), 0, 0, 1, 0, 32, 0])
            append(UInt32(image.count), to: &data)
            append(UInt32(offset), to: &data)
            offset += image.count
        }
        for image in images { data.append(image) }
        return data
    }

    private static func append(_ value: UInt32, to data: inout Data) {
        data.append(contentsOf: (0..<4).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) })
    }

    private enum AssetError: Error {
        case invalidSVG, colorResolution, svgRendering, pngEncoding
    }
}

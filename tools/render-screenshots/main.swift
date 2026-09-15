// Renders the widget views to PNG at each family's size using live snapshot data.
// Built by tools/render-screenshots/render.sh — no Screen Recording permission needed.
import AppKit
import SwiftUI
import WidgetKit

let outDir = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "docs")
let snapshot = SnapshotStore.load() ?? .placeholder
let families: [(String, WidgetFamily, CGSize)] = [
    ("small", .systemSmall, CGSize(width: 170, height: 170)),
    ("medium", .systemMedium, CGSize(width: 364, height: 170)),
    ("large", .systemLarge, CGSize(width: 364, height: 382)),
]

@MainActor
func render() throws {
    _ = NSApplication.shared   // fonts and appearance need an app context
    try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

    for (name, family, size) in families {
        let view = WidgetContent(family: family, snapshot: snapshot)
            .padding(16)                                   // WidgetKit's default content margins
            .frame(width: size.width, height: size.height)
            .background(Color(red: 0.13, green: 0.13, blue: 0.14))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding(12)
            .background(Color(red: 0.07, green: 0.07, blue: 0.08))
            .environment(\.colorScheme, .dark)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let cgImage = renderer.cgImage,
              let png = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else {
            fatalError("could not render \(name)")
        }
        let url = outDir.appendingPathComponent("widget-\(name).png")
        try png.write(to: url)
        print("wrote \(url.path)")
    }
}

try MainActor.assumeIsolated { try render() }

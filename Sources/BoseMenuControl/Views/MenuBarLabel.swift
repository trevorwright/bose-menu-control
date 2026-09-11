import AppKit
import SwiftUI

/// The menu bar item: headphones plus battery percentage when connected, a slashed icon otherwise.
///
/// The menu bar splits a label into a separate image and title, which drops an inline symbol and
/// misaligns a side-by-side image and text. Rendering both into one template image avoids that.
struct MenuBarLabel: View {
    @ObservedObject var controller: HeadphoneController

    var body: some View {
        if controller.isConnected, let image = Self.connectedImage(text: batteryText) {
            Image(nsImage: image)
        } else if controller.isConnected {
            Text(batteryText)
        } else {
            Image(systemName: "headphones.slash")
        }
    }

    private var batteryText: String {
        guard let percent = controller.headphones?.battery?.percent else { return "--" }
        return "\(percent)%"
    }

    @MainActor
    private static func connectedImage(text: String) -> NSImage? {
        let content = HStack(alignment: .center, spacing: 4) {
            Image(systemName: "headphones")
                .font(.system(size: 14, weight: .medium))
            Text(text)
                .font(.system(size: 14))
                .monospacedDigit()
        }
        .foregroundStyle(Color.black)
        .padding(.horizontal, 1)
        .fixedSize()

        let renderer = ImageRenderer(content: content)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let image = renderer.nsImage else { return nil }
        image.isTemplate = true
        return image
    }
}

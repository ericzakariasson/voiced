import AppKit
import SwiftUI

/// The look of every surface: near-black and white with greys between, hairline borders, the
/// system font, and untinted Liquid Glass. Nothing here uses a hue; states are told apart by
/// shape, motion and wording. Controls are the system's own wherever one fits.
enum Monochrome {
    /// The window background: near-black in the dark appearance, white in the light one.
    static let canvas = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(white: 0.04, alpha: 1)
            : NSColor(white: 1, alpha: 1)
    })
    /// The opposite of the canvas: white on near-black, near-black on white. Glass tones down the
    /// semantic `.primary` style, so marks and labels that must stay crisp on glass use this.
    static let ink = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(white: 1, alpha: 1)
            : NSColor(white: 0.04, alpha: 1)
    })
    static let hairline = Color.primary.opacity(0.14)
    static let panelRadius: CGFloat = 14
    static let controlHeight: CGFloat = 28
}

/// Fills a window with the canvas colour, title bar included.
struct Canvas: View {
    var body: some View {
        Monochrome.canvas.ignoresSafeArea()
    }
}

/// A one-point rule between rows.
struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(Monochrome.hairline)
            .frame(height: 1)
    }
}

/// A Liquid Glass panel with a hairline edge. Rows inside it are separated by `Hairline`s.
struct Panel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: Monochrome.panelRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Monochrome.panelRadius, style: .continuous)
                .strokeBorder(Monochrome.hairline, lineWidth: 1)
        }
    }
}

/// Voiced's mark: five bars of a waveform. Drawn here so the app and its icon share one shape.
struct WaveformMark: View {
    var height: CGFloat

    private static let bars: [CGFloat] = [0.36, 0.72, 1, 0.56, 0.3]

    var body: some View {
        HStack(spacing: height * 0.13) {
            ForEach(Self.bars.indices, id: \.self) { index in
                Capsule()
                    .frame(width: height * 0.13, height: height * Self.bars[index])
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// The mark on a glass disc, for window and menu headers.
struct MarkBadge: View {
    var size: CGFloat

    var body: some View {
        Color.clear
            .frame(width: size, height: size)
            .glassEffect(.regular, in: .circle)
            .overlay {
                Circle().strokeBorder(Monochrome.hairline, lineWidth: 1)
            }
            .overlay {
                WaveformMark(height: size * 0.42)
                    .foregroundStyle(Monochrome.ink)
            }
    }
}

/// A keycap-style label for a hotkey.
struct Keycap: View {
    var label: String

    var body: some View {
        Text(label)
            .font(.callout.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .glassEffect(.regular, in: .rect(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Monochrome.hairline, lineWidth: 1)
            }
    }
}

/// "Done" told by a tick and a word instead of green.
struct StatusMark: View {
    var isDone: Bool
    var label: String

    var body: some View {
        Label(label, systemImage: isDone ? "checkmark" : "minus")
            .labelStyle(.titleAndIcon)
            .font(.callout.weight(.medium))
            .foregroundStyle(isDone ? .primary : .secondary)
            .lineLimit(1)
    }
}

/// The one main action on a surface: a solid ink capsule with its label in the canvas colour.
///
/// This is the one control drawn here rather than by the system. The system's prominent button
/// takes the accent colour, and when the app is not frontmost it drops its fill, which left a
/// white label on a pale button. Every other button is a standard one.
struct InkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Face(configuration: configuration)
    }

    private struct Face: View {
        var configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.controlSize) private var controlSize

        var body: some View {
            configuration.label
                .font(.body.weight(.medium))
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(height: controlSize == .large ? 34 : Monochrome.controlHeight)
                .foregroundStyle(Monochrome.canvas)
                .background(Monochrome.ink, in: .capsule)
                .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.35)
                .contentShape(.capsule)
        }
    }
}

extension ButtonStyle where Self == InkButtonStyle {
    /// The main action, in black and white.
    static var ink: InkButtonStyle { InkButtonStyle() }
}

/// One row of a panel: a title and up to two lines of detail on the left, a control or a status
/// on the right. The row and its right-hand slot have fixed sizes, so a button turning into a
/// status moves nothing.
struct SettingRow<Trailing: View>: View {
    /// A step number such as "1", shown in the setup window.
    var number: String?
    var title: String
    var detail: String
    @ViewBuilder var trailing: Trailing

    static var height: CGFloat { 74 }
    static var trailingWidth: CGFloat { 132 }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            if let number {
                Text(number)
                    .font(.callout.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 20, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
                .frame(width: Self.trailingWidth, height: Monochrome.controlHeight, alignment: .trailing)
        }
        .padding(.horizontal, 18)
        .frame(height: Self.height)
    }
}

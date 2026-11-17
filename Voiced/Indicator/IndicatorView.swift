import SwiftUI
import VoicedKit

/// What the floating indicator is showing.
enum IndicatorContent: Equatable {
    case hidden
    /// The hotkey is held, but the microphone is slow to start and nothing is being recorded yet.
    case startingMicrophone
    /// Listening, with the time audio began to arrive.
    case recording(since: Date)
    case working(String)
    case notice(DictationController.Notice.Kind, String)
    /// Nothing is being dictated; the pill is up so it can be dragged to where it should live.
    case placing
}

/// The glass pill that floats above the Dock while Voiced records and works.
///
/// It has one look, whatever the appearance of the Mac: dark glass with white marks, as it was
/// in the dark appearance alone before. A pill is a small thing over somebody else's window,
/// and it reads the same over a white page as over a black one only if it brings its own
/// darkness along. Everything else in Voiced follows the appearance.
struct IndicatorView: View {
    var content: IndicatorContent
    var level: Float
    /// Told where the pill is within this view, so the panel knows which part of itself can be grabbed.
    var onPillFrame: (CGRect) -> Void = { _ in }

    /// Black laid over the glass and under the marks. Dark glass takes much of its tone from
    /// what is behind it, and over a white window it comes out a middle grey, on which the
    /// clock, at 65% of white, stood at 3.7 to 1. This is the least, in whole percent, that
    /// brings it to 4.5 to 1 there; over anything darker the pill is better off still.
    static let wash = Color.black.opacity(0.17)

    /// The gap between the pill and the bottom edge of this view.
    static let bottomPadding: CGFloat = 10

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            if content != .hidden {
                pill
                    .transition(.scale(scale: 0.85, anchor: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, Self.bottomPadding)
        .animation(.spring(duration: 0.3), value: content)
    }

    private var pill: some View {
        HStack(spacing: 10) {
            switch content {
            case .hidden:
                EmptyView()
            case .startingMicrophone:
                // Not listening yet, so none of what says listening: an outlined microphone that
                // holds still, no bars and no clock.
                Image(systemName: "mic")
                Text("Starting Microphone…")
                    .foregroundStyle(Monochrome.ink.opacity(0.65))
            case let .recording(since):
                // Listening is told by the pulse, the moving bars and the running clock, not by red.
                Image(systemName: "mic.fill")
                    .symbolEffect(.pulse)
                WaveformBars(level: level)
                ElapsedTime(since: since)
            case let .working(label):
                ProgressView()
                    .controlSize(.small)
                Text(label)
            case let .notice(kind, message):
                // An octagon for an error, a triangle for a warning.
                Image(systemName: kind == .error ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                Text(message)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            case .placing:
                Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                Text("Drag to Move")
            }
        }
        .font(.callout.weight(.medium))
        .foregroundStyle(Monochrome.ink)
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .frame(minHeight: 42)
        .frame(maxWidth: 420)
        .fixedSize(horizontal: true, vertical: false)
        .background(Self.wash, in: .rect(cornerRadius: 21))
        .glassEffect(.regular, in: .rect(cornerRadius: 21))
        .overlay {
            RoundedRectangle(cornerRadius: 21, style: .continuous)
                .strokeBorder(Monochrome.hairline, lineWidth: 1)
        }
        // The glass, the ink and the hairline all take their tone from the colour scheme.
        .environment(\.colorScheme, .dark)
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global)
        } action: { frame in
            onPillFrame(frame)
        }
    }
}

/// Minutes and seconds since recording began. The system font, with digits of equal width so the
/// pill holds still as they change.
private struct ElapsedTime: View {
    var since: Date

    var body: some View {
        Text(timerInterval: since...since.addingTimeInterval(24 * 60 * 60), countsDown: false)
            .font(.callout.weight(.medium))
            .monospacedDigit()
            .foregroundStyle(Monochrome.ink.opacity(0.65))
            .frame(minWidth: 32, alignment: .trailing)
            .accessibilityLabel("Recording time")
    }
}

/// Bars that follow the microphone level.
private struct WaveformBars: View {
    var level: Float

    private static let barCount = 13
    /// Tallest in the middle, like a voice waveform.
    private static let envelope: [CGFloat] = (0..<barCount).map { index in
        let position = Double(index) / Double(barCount - 1)
        return 0.35 + 0.65 * sin(position * .pi)
    }

    @State private var jitter = Array(repeating: CGFloat(1), count: barCount)

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<Self.barCount, id: \.self) { index in
                Capsule()
                    .frame(width: 3, height: 4 + 18 * CGFloat(level) * Self.envelope[index] * jitter[index])
            }
        }
        .frame(height: 22)
        .animation(.spring(duration: 0.16), value: level)
        .onChange(of: level) {
            jitter = jitter.map { _ in CGFloat.random(in: 0.7...1) }
        }
    }
}

#Preview("Recording") {
    IndicatorView(content: .recording(since: .now), level: 0.7)
        .frame(width: 460, height: 110)
}

#Preview("Starting Microphone") {
    IndicatorView(content: .startingMicrophone, level: 0)
        .frame(width: 460, height: 110)
}

#Preview("Notice") {
    IndicatorView(content: .notice(.warning, "Cleanup failed, inserted the raw transcript."), level: 0)
        .frame(width: 460, height: 110)
}

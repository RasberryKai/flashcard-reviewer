import AppKit
import SwiftUI

enum ReviewerAppearance: String {
    case light
    case dark

    static let storageKey = "reviewerAppearance"
    var colorScheme: ColorScheme { self == .dark ? .dark : .light }
    var nativeAppearance: NSAppearance? {
        NSAppearance(named: self == .dark ? .darkAqua : .aqua)
    }
    var toggleLabel: String { self == .dark ? "Switch to light mode" : "Switch to dark mode" }
}

struct AppearanceToggle: View {
    @AppStorage(ReviewerAppearance.storageKey) private var appearance: ReviewerAppearance = .dark

    var body: some View {
        Button {
            appearance = appearance == .dark ? .light : .dark
        } label: {
            Image(systemName: appearance == .dark ? "sun.max" : "moon")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(ReviewerPalette.text2)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(appearance.toggleLabel)
        .accessibilityLabel(appearance.toggleLabel)
        .accessibilityValue(appearance == .dark ? "Dark mode" : "Light mode")
    }
}

struct AppLogo: View {
    var size: CGFloat = 32

    private static let image: NSImage? = {
#if SWIFT_PACKAGE
        let bundle = Bundle.module
#else
        let bundle = Bundle.main
#endif
        return bundle.url(forResource: "flashcard-reviewer-logo", withExtension: "png")
            .flatMap { NSImage(contentsOf: $0) }
    }()

    var body: some View {
        Group {
            if let image = Self.image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Image(systemName: "checkmark.square")
                    .foregroundStyle(ReviewerPalette.green)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

enum ReviewerPalette {
    static let canvas = adaptive(light: 0xF3F0EB, dark: 0x161513)
    static let surface = adaptive(light: 0xFCFBF8, dark: 0x1C1B18)
    static let card = adaptive(light: 0xFFFFFF, dark: 0x1F1E1B)
    static let sidebar = adaptive(light: 0xF3F0EB, dark: 0x1A1917)
    static let raised = adaptive(light: 0xECE9E3, dark: 0x262521)
    static let selected = adaptive(light: 0xFFFFFF, dark: 0x26251F)
    static let border = adaptive(light: 0xE2DED6, dark: 0x2E2C28)
    static let borderStrong = adaptive(light: 0xD6D1C8, dark: 0x34322D)
    static let ink = adaptive(light: 0x1C1B19, dark: 0xECE8E0)
    static let text2 = adaptive(light: 0x5E5A52, dark: 0xA39E92)
    static let text3 = adaptive(light: 0x8A857A, dark: 0x8C877C)
    static let primaryButton = adaptive(light: 0x1C1B19, dark: 0xECE8E0)
    static let onPrimaryButton = adaptive(light: 0xFCFBF8, dark: 0x1C1B19)
    static let good = adaptive(light: 0x3E7A57, dark: 0x5FB383)
    static let goodBar = adaptive(light: 0x3E7A57, dark: 0x4E9A6F)
    static let bad = adaptive(light: 0xA6463B, dark: 0xE07A6C)
    static let amber = adaptive(light: 0x8E6A1C, dark: 0xD4A24C)
    static let goodWash = adaptive(light: 0xE3EEE6, dark: 0x1F3328)
    static let badWash = adaptive(light: 0xF6E7E4, dark: 0x2E1F1C)
    static let amberWash = adaptive(light: 0xF4EEDF, dark: 0x2E2718)
    static let accent = adaptive(light: 0x2F6FEB, dark: 0x2E6FDB)
    static let link = adaptive(light: 0x1D5FD6, dark: 0x8FB4FF)
    static let input = adaptive(light: 0xFFFFFF, dark: 0x141311)
    static let track = adaptive(light: 0xE2DED6, dark: 0x3A3833)
    static let disabled = adaptive(light: 0xB8B3A9, dark: 0x5C5850)

    // Kept for existing review components while they migrate to semantic names.
    static let muted = text2
    static let line = border
    static let green = good
    static let greenWash = goodWash
    static let red = bad
    static let redWash = badWash
    static let grayWash = raised

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let value = isDark ? dark : light
            return NSColor(
                srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255,
                alpha: 1
            )
        }))
    }
}

extension CardVerdict {
    var label: String {
        switch self {
        case .unreviewed: "Unreviewed"
        case .good: "Good"
        case .bad: "Bad"
        case .needsAdjustment: "Needs adjustment"
        }
    }

    var color: Color {
        switch self {
        case .unreviewed: ReviewerPalette.muted
        case .good: ReviewerPalette.green
        case .bad: ReviewerPalette.red
        case .needsAdjustment: ReviewerPalette.amber
        }
    }

    var wash: Color {
        switch self {
        case .unreviewed: ReviewerPalette.grayWash
        case .good: ReviewerPalette.greenWash
        case .bad: ReviewerPalette.redWash
        case .needsAdjustment: ReviewerPalette.amberWash
        }
    }

    var symbol: String {
        switch self {
        case .unreviewed: "circle.dashed"
        case .good: "checkmark"
        case .bad: "xmark"
        case .needsAdjustment: "pencil"
        }
    }
}

struct VerdictBadge: View {
    let verdict: CardVerdict

    var body: some View {
        Label(verdict.label, systemImage: verdict.symbol)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(verdict.color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(verdict.wash, in: Capsule())
    }
}

struct PageHeading: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 30, weight: .regular, design: .serif))
                .foregroundStyle(ReviewerPalette.ink)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(ReviewerPalette.muted)
            }
        }
    }
}

struct SurfaceCard<Content: View>: View {
    var padding: CGFloat = 20
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background(ReviewerPalette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(ReviewerPalette.border.opacity(0.7), lineWidth: 1)
            }
    }
}

struct ReviewerPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(ReviewerPalette.onPrimaryButton)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(ReviewerPalette.primaryButton, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.82 : 1) : 0.45)
    }
}

struct ProgressStrip: View {
    let good: Int
    let adjustment: Int
    let bad: Int
    let unreviewed: Int

    private var total: Int { max(good + adjustment + bad + unreviewed, 1) }

    var body: some View {
        GeometryReader { proxy in
            let segmentWidth = max(proxy.size.width - 6, 0)
            HStack(spacing: 2) {
                segment(good, ReviewerPalette.goodBar, segmentWidth)
                segment(adjustment, ReviewerPalette.amber, segmentWidth)
                segment(bad, ReviewerPalette.bad, segmentWidth)
                segment(unreviewed, ReviewerPalette.track, segmentWidth)
            }
            .clipShape(Capsule())
        }
        .frame(height: 4)
        .accessibilityLabel("Review progress")
    }

    private func segment(_ count: Int, _ color: Color, _ width: CGFloat) -> some View {
        color.frame(width: width * CGFloat(count) / CGFloat(total))
    }
}

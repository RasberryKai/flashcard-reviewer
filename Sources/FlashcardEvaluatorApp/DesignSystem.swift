import AppKit
import SwiftUI

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
    static let canvas = Color(red: 0.957, green: 0.945, blue: 0.918)
    static let surface = Color(red: 1.0, green: 0.996, blue: 0.976)
    static let ink = Color(red: 0.14, green: 0.13, blue: 0.12)
    static let muted = Color(red: 0.43, green: 0.41, blue: 0.38)
    static let line = Color(red: 0.86, green: 0.83, blue: 0.78)
    static let green = Color(red: 0.18, green: 0.44, blue: 0.32)
    static let greenWash = Color(red: 0.88, green: 0.93, blue: 0.89)
    static let amber = Color(red: 0.57, green: 0.37, blue: 0.08)
    static let amberWash = Color(red: 0.96, green: 0.91, blue: 0.79)
    static let red = Color(red: 0.66, green: 0.25, blue: 0.20)
    static let redWash = Color(red: 0.96, green: 0.88, blue: 0.86)
    static let grayWash = Color(red: 0.92, green: 0.90, blue: 0.86)
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
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(20)
            .background(ReviewerPalette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(ReviewerPalette.line.opacity(0.7), lineWidth: 1)
            }
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
                segment(good, ReviewerPalette.green, segmentWidth)
                segment(adjustment, ReviewerPalette.amber, segmentWidth)
                segment(bad, ReviewerPalette.red, segmentWidth)
                segment(unreviewed, ReviewerPalette.line, segmentWidth)
            }
            .clipShape(Capsule())
        }
        .frame(height: 8)
        .accessibilityLabel("Review progress")
    }

    private func segment(_ count: Int, _ color: Color, _ width: CGFloat) -> some View {
        color.frame(width: width * CGFloat(count) / CGFloat(total))
    }
}

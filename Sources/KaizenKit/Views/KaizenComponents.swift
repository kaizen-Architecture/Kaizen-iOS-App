import SwiftUI

public extension Color {
    static let kaizenCyan = Color(red: 0.2, green: 0.8, blue: 0.9)
}

public struct GlassCard<Content: View>: View {
    let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content
    }

    public var body: some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.white.opacity(0.15), lineWidth: 1))
            .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
    }
}

public struct PrimaryButton: View {
    let title: String
    let systemImage: String?
    let isGlowing: Bool
    let action: () -> Void

    public init(title: String, systemImage: String? = nil, isGlowing: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.isGlowing = isGlowing
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(
                LinearGradient(colors: [.kaizenCyan, .blue], startPoint: .leading, endPoint: .trailing),
                in: RoundedRectangle(cornerRadius: 14)
            )
            .shadow(color: isGlowing ? Color.kaizenCyan.opacity(0.4) : .clear, radius: 8, y: 4)
        }
        .buttonStyle(.plain)
    }
}

public struct SecondaryButton: View {
    let title: String
    let systemImage: String?
    let tint: Color
    let action: () -> Void

    public init(title: String, systemImage: String? = nil, tint: Color = .white, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .foregroundStyle(tint)
                }
                Text(title)
                    .lineLimit(1)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

public struct Badge: View {
    let text: String
    let color: Color

    public init(text: String, color: Color) {
        self.text = text
        self.color = color
    }

    public var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.2), in: Capsule())
            .foregroundStyle(color)
            .fixedSize(horizontal: true, vertical: false)
    }
}

public struct StatusDot: View {
    public enum Status {
        case waiting, active, completed, failed
    }
    let status: Status

    public init(status: Status) {
        self.status = status
    }

    public var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
    }

    private var color: Color {
        switch status {
        case .waiting: return .gray
        case .active: return .kaizenCyan
        case .completed: return .green
        case .failed: return .red
        }
    }
}

public struct SegmentedGlass: View {
    let items: [String]
    @Binding var selectedIndex: Int

    public init(items: [String], selectedIndex: Binding<Int>) {
        self.items = items
        self._selectedIndex = selectedIndex
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<items.count, id: \.self) { index in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedIndex = index
                    }
                } label: {
                    Text(items[index])
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(selectedIndex == index ? .black : .white)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(selectedIndex == index ? Color.kaizenCyan : Color.clear, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
    }
}

public struct ProgressBarGlow: View {
    let progress: Double
    let color: Color
    let height: CGFloat

    public init(progress: Double, color: Color, height: CGFloat = 6) {
        self.progress = progress
        self.color = color
        self.height = height
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                    .fill(Color.white.opacity(0.15))

                RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                    .fill(color)
                    .frame(width: geo.size.width * CGFloat(progress))
                    .shadow(color: color.opacity(0.6), radius: 4, y: 0)
            }
        }
        .frame(height: height)
    }
}

public struct CoverView: View {
    let url: String?
    let token: String?
    let width: CGFloat?
    let height: CGFloat?
    let cornerRadius: CGFloat

    public init(url: String?, token: String?, width: CGFloat? = nil, height: CGFloat? = nil, cornerRadius: CGFloat = 8) {
        self.url = url
        self.token = token
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        RemoteImage(url: url.flatMap { URL(string: $0) }, token: token, contentMode: .fill)
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.3), radius: cornerRadius / 2, y: cornerRadius / 4)
    }
}

public extension View {
    func kaizenBackgroundStyle() -> some View {
        self.background(
            ZStack {
                Color.black.ignoresSafeArea()
                LinearGradient(
                    colors: [Color.indigo.opacity(0.1), Color.black],
                    startPoint: .top,
                    endPoint: .bottom
                ).ignoresSafeArea()
            }
        )
    }
}

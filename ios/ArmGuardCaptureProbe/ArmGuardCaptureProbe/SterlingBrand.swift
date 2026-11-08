import SwiftUI

/// Native vector companion to assets/branding/sterling-ring.svg.
struct SterlingRingMark: View {
    private struct Annulus: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.addEllipse(in: rect)
            path.addEllipse(in: rect.insetBy(dx: rect.width * 0.073, dy: rect.height * 0.076))
            return path
        }
    }
    var body: some View {
        GeometryReader { geometry in
            Annulus()
                .fill(LinearGradient(colors: [Color(white: 0.98), Color(white: 0.46), Color(white: 0.89), Color(white: 0.62)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing), style: FillStyle(eoFill: true))
                .overlay { Annulus().stroke(Color(white: 0.45).opacity(0.6), lineWidth: 0.7) }
                .frame(width: geometry.size.width * 0.84, height: geometry.size.height * 0.58)
                .rotationEffect(.degrees(-37))
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }.accessibilityHidden(true)
    }
}

enum SterlingStyle {
    static let accent = Color(red: 0.04, green: 0.43, blue: 0.50)
}

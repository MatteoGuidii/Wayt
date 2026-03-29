import SwiftUI

/// The Wayt brand mark — displays the app logo from the asset catalog.
struct WaytLogomark: View {

    let size: CGFloat

    var body: some View {
        Image("WaytLogo")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
            .accessibilityLabel("Wayt logo")
    }
}

#Preview("Logomark Sizes") {
    HStack(spacing: 24) {
        WaytLogomark(size: 100)
        WaytLogomark(size: 64)
        WaytLogomark(size: 48)
    }
    .padding()
}

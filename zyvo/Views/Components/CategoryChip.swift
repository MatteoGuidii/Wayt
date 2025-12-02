import SwiftUI

struct CategoryChip: View {
    let icon: String
    let label: String
    var isSelected: Bool = false
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(NSLocalizedString(label, comment: ""))
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(isSelected ? .white : .primary)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(isSelected ? Color.blue : Color.clear)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(isSelected ? Color.blue : .secondary.opacity(0.2), lineWidth: 1)
        )
    }
}

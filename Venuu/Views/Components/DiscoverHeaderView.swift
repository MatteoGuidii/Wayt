import SwiftUI

struct DiscoverHeaderView: View {
    @Binding var showMap: Bool
    
    var timeBasedGreeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return NSLocalizedString("Good Morning", comment: "")
        case 12..<17: return NSLocalizedString("Good Afternoon", comment: "")
        case 17..<22: return NSLocalizedString("Good Evening", comment: "")
        default: return NSLocalizedString("Good Night", comment: "")
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(timeBasedGreeting)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            
            HStack {
                Text("Find your vibe")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                
                Spacer()
                
                Button {
                    withAnimation {
                        showMap.toggle()
                    }
                } label: {
                    Image(systemName: showMap ? "map.fill" : "map")
                        .font(.title2)
                        .foregroundStyle(.primary)
                        .padding(8)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }
}

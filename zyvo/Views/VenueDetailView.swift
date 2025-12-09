import SwiftUI
import MapKit
import Contacts

struct VenueDetailView: View {
    let venue: Venue
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Header Image
                ZStack(alignment: .topTrailing) {
                    if let image = venue.image {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(height: 250)
                            .clipped()
                    } else {
                        Rectangle()
                            .fill(venue.themeColor.gradient)
                            .frame(height: 250)
                            .overlay(
                                Image(systemName: venue.systemImage)
                                    .font(.system(size: 60))
                                    .foregroundStyle(.white.opacity(0.5))
                            )
                    }
                    
                    // Close Button
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .padding()
                }
                
                VStack(alignment: .leading, spacing: 20) {
                    // Title and Category
                    VStack(alignment: .leading, spacing: 8) {
                        Text(venue.name)
                            .font(.title.weight(.bold))
                            .foregroundStyle(.primary)
                        
                        if let category = venue.category?.rawValue {
                            Text(category.replacingOccurrences(of: "MKPOICategory", with: ""))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                        }
                    }
                    
                    Divider()
                    
                    // Actions
                    HStack(spacing: 20) {
                        ActionButton(title: "Directions", icon: "arrow.turn.up.right", color: .blue) {
                            venue.mapItem.openInMaps()
                        }
                        
                        if let phone = venue.mapItem.phoneNumber {
                            ActionButton(title: "Call", icon: "phone.fill", color: .green) {
                                if let url = URL(string: "tel://\(phone.replacingOccurrences(of: " ", with: ""))") {
                                    UIApplication.shared.open(url)
                                }
                            }
                        }
                        
                        if let url = venue.mapItem.url {
                            ActionButton(title: "Website", icon: "globe", color: .indigo) {
                                UIApplication.shared.open(url)
                            }
                        }
                    }
                    
                    Divider()
                    
                    // Info
                    VStack(alignment: .leading, spacing: 16) {
                        InfoRow(icon: "mappin.and.ellipse", text: getAddress(for: venue.mapItem))
                        
                        if let phone = venue.mapItem.phoneNumber {
                            InfoRow(icon: "phone", text: phone)
                        }
                        
                        if let url = venue.mapItem.url {
                            InfoRow(icon: "link", text: url.host ?? "Website")
                        }
                    }
                }
                .padding(24)
            }
        }
        .ignoresSafeArea(edges: .top)
        .background(Color(uiColor: .systemBackground))
    }
    
    private func getAddress(for mapItem: MKMapItem) -> String {
        // Try modern postal address API (available iOS 16+)
        if let postalAddress = mapItem.placemark.postalAddress {
            let formatter = CNPostalAddressFormatter()
            return formatter.string(from: postalAddress)
        }

        // Fall back to placemark data
        let placemark = mapItem.placemark
        let components = [
            placemark.subThoroughfare,
            placemark.thoroughfare,
            placemark.locality,
            placemark.administrativeArea,
            placemark.postalCode
        ].compactMap { $0 }

        if !components.isEmpty {
            return components.joined(separator: ", ")
        }

        // Final fallback to coordinate representation
        let coord = mapItem.placemark.coordinate
        return String(format: "%.5f, %.5f", coord.latitude, coord.longitude)
    }
}

struct ActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title3)
                Text(title)
                    .font(.caption.weight(.medium))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: 12))
            .shadow(color: color.opacity(0.3), radius: 5, x: 0, y: 3)
        }
    }
}

struct InfoRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            
            Text(text)
                .font(.body)
                .foregroundStyle(.primary)
        }
    }
}

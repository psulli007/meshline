//
// ShareMeshlineView.swift
// Meshline
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

/// Where people get Meshline. Placeholder until the TestFlight public link
/// or App Store URL exists; swap this one constant.
enum MeshlineShareLink {
    static let url = URL(string: "https://testflight.apple.com/join/PC6vqs3k")!
}

/// Offline app sharing: a QR code anyone nearby can scan, plus the system
/// share sheet (AirDrop works with no internet or cell service).
struct ShareMeshlineView: View {
    @Environment(\.dismiss) private var dismiss
    let url: URL

    init(url: URL = MeshlineShareLink.url) {
        self.url = url
    }

    var body: some View {
        VStack(spacing: 20) {
            Text(verbatim: "Share Meshline")
                .font(.title2.weight(.semibold))
            Text(verbatim: "Scan the code or AirDrop the link so friends nearby can install Meshline. AirDrop works without internet or cell service.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let qr = Self.qrImage(for: url.absoluteString) {
                Image(decorative: qr, scale: 1)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 220, height: 220)
                    .padding(12)
                    .background(Color.white)
                    .cornerRadius(12)
                    .accessibilityLabel(Text(verbatim: "QR code for the Meshline download link"))
            }

            Text(verbatim: url.absoluteString)
                .font(.caption.monospaced())
                .textSelection(.enabled)

            ShareLink(item: url) {
                Label {
                    Text(verbatim: "AirDrop or share link")
                } icon: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
            .buttonStyle(.borderedProminent)

            Button {
                dismiss()
            } label: {
                Text(verbatim: "Done")
            }
        }
        .padding(24)
    }

    /// Renders `string` as a QR code CGImage, scaled up for crisp display.
    static func qrImage(for string: String) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        return CIContext().createCGImage(scaled, from: scaled.extent)
    }
}

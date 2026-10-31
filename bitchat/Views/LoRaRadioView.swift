//
// LoRaRadioView.swift
// Meshline
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import SwiftUI

/// Scan for, pair and forget a Meshtastic LoRa radio, and show its status.
struct LoRaRadioView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var radio: MeshtasticRadioService

    init(radio: MeshtasticRadioService = .shared) {
        self.radio = radio
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(verbatim: "LoRa radio")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Text(verbatim: "Done")
                }
            }

            Text(verbatim: "Optional. Pair a Meshtastic LoRa radio to reach Meshline users several miles away. Text and private messages travel over the radio; photos and voice stay on Bluetooth and Wi-Fi. Messages stay end to end encrypted.")
                .font(.footnote)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Circle()
                    .fill(radio.state.isConnected ? Color.green : Color.gray)
                    .frame(width: 10, height: 10)
                Text(verbatim: radio.state.label)
                    .font(.subheadline)
            }

            if radio.state.isConnected {
                Text(verbatim: "Sent \(radio.framesSent), received \(radio.framesReceived)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let name = radio.pairedRadioName {
                HStack {
                    Text(verbatim: "Paired: \(name)")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Button(role: .destructive) {
                        radio.unpair()
                    } label: {
                        Text(verbatim: "Forget radio")
                    }
                }
            } else {
                HStack {
                    Button {
                        radio.startScan()
                    } label: {
                        Label {
                            Text(verbatim: "Scan for radios")
                        } icon: {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                        }
                    }
                    Spacer()
                    if radio.state == .scanning {
                        Button {
                            radio.stopScan()
                        } label: {
                            Text(verbatim: "Stop")
                        }
                    }
                }

                ForEach(radio.discovered) { found in
                    Button {
                        radio.pair(found)
                    } label: {
                        HStack {
                            Text(verbatim: found.name)
                            Spacer()
                            Text(verbatim: "\(found.rssi) dBm")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Text(verbatim: "When asked, enter the PIN shown on the radio (radios without a screen often use 123456). Everyone who should hear each other needs radios on the same Meshtastic channel and region.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .padding(20)
        .onDisappear {
            radio.stopScan()
        }
    }
}

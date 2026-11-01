//
// SafetyViews.swift
// Meshline
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import BitFoundation
import CoreLocation
import SwiftUI

/// One-shot location fix for a check-in, only when the user turns it on.
final class CheckInLocator: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var location: CheckInLocation?
    @Published private(set) var isLocating = false
    @Published private(set) var failed = false
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func request() {
        failed = false
        isLocating = true
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            isLocating = false
            failed = true
        default:
            manager.requestLocation()
        }
    }

    func clear() {
        location = nil
        isLocating = false
        failed = false
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard isLocating else { return }
        switch manager.authorizationStatus {
        case .notDetermined: break
        case .denied, .restricted:
            DispatchQueue.main.async { self.isLocating = false; self.failed = true }
        default:
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        DispatchQueue.main.async {
            self.location = CheckInLocation(latitude: last.coordinate.latitude, longitude: last.coordinate.longitude)
            self.isLocating = false
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async { self.isLocating = false; self.failed = true }
    }
}

struct CheckInSheet: View {
    @EnvironmentObject private var peerListModel: PeerListModel
    @Environment(\.dismiss) private var dismiss
    let people: [MeshPeerRow]
    let nameFor: (MeshPeerRow) -> String

    @State private var status: SafetyStatus = .safe
    @State private var note = ""
    @State private var includeLocation = false
    @State private var picked: Set<PeerID> = []
    @State private var pickedGroups: Set<PeerID> = []
    @State private var sentCount: Int?
    @StateObject private var locator = CheckInLocator()

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Picker(selection: $status) {
                        ForEach(SafetyStatus.allCases) { s in
                            Text(verbatim: s.title).tag(s)
                        }
                    } label: {
                        Text(verbatim: "Status")
                    }
                    .pickerStyle(.segmented)
                    TextField(text: $note) {
                        Text(verbatim: "Short note (optional)")
                    }
                    Toggle(isOn: $includeLocation) {
                        Text(verbatim: "Include my location")
                    }
                    .onChange(of: includeLocation) { on in
                        if on { locator.request() } else { locator.clear() }
                    }
                    if includeLocation {
                        if locator.isLocating {
                            Text(verbatim: "Finding your location...").font(.caption).foregroundColor(.secondary)
                        } else if locator.failed {
                            Text(verbatim: "Couldn't get your location. You can still send without it.").font(.caption).foregroundColor(.orange)
                        } else if locator.location != nil {
                            Text(verbatim: "Location added, about 100 m accurate.").font(.caption).foregroundColor(.secondary)
                        }
                    }
                } footer: {
                    Text(verbatim: "Sent as an end-to-end encrypted message to the people and groups you pick. People out of range get it later: other phones carry it for up to 72 hours, and it also goes over the internet if anyone along the way has a connection.")
                }

                Section {
                    if people.isEmpty && peerListModel.groupRows.isEmpty {
                        Text(verbatim: "Add some people first.").foregroundColor(.secondary)
                    }
                    ForEach(people) { row in
                        toggleRow(nameFor(row), isOn: picked.contains(row.peerID)) {
                            if picked.contains(row.peerID) { picked.remove(row.peerID) } else { picked.insert(row.peerID) }
                        }
                    }
                    ForEach(peerListModel.groupRows) { group in
                        toggleRow("Group: \(group.name)", isOn: pickedGroups.contains(group.peerID)) {
                            if pickedGroups.contains(group.peerID) { pickedGroups.remove(group.peerID) } else { pickedGroups.insert(group.peerID) }
                        }
                    }
                } header: {
                    Text(verbatim: "Send to")
                }
            }
            .navigationTitle(Text(verbatim: "Check in"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text(verbatim: "Cancel") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        let text = SafetyCheckIn.message(
                            status: status,
                            note: note,
                            location: includeLocation ? locator.location : nil
                        )
                        sentCount = peerListModel.sendCheckIn(text, toPeople: Array(picked), groups: Array(pickedGroups))
                    } label: {
                        Text(verbatim: "Send")
                    }
                    .disabled(picked.isEmpty && pickedGroups.isEmpty || (includeLocation && locator.isLocating))
                }
            }
            .onAppear {
                if picked.isEmpty && pickedGroups.isEmpty {
                    picked = Set(people.map(\.peerID))
                    pickedGroups = Set(peerListModel.groupRows.map(\.peerID))
                }
            }
            .alert(Text(verbatim: "Check-in sent"), isPresented: Binding(
                get: { sentCount != nil },
                set: { if !$0 { sentCount = nil; dismiss() } }
            )) {
                Button {} label: { Text(verbatim: "OK") }
            } message: {
                Text(verbatim: "Sent to \(sentCount ?? 0). Open Chats to see when each one is delivered.")
            }
        }
    }

    private func toggleRow(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle").foregroundColor(.accentColor)
                Text(verbatim: title)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Offline emergency tips. Bundled text only; no network needed.
enum EmergencyTips {
    struct Tip: Identifiable {
        let title: String
        let body: String
        var id: String { title }
    }

    static let tips: [Tip] = [
        Tip(title: "Call or text for help first",
            body: "If you have any signal, call your local emergency number (911 in the US and Canada, 112 in Europe). Texts often get through when calls fail. Meshline does not reach emergency services."),
        Tip(title: "Make Meshline reach farther",
            body: "Keep Bluetooth on and Meshline open. Every phone running Meshline passes messages along, so ask people near you to install it. Higher spots and windows help. Messages to people out of range are carried by other phones for up to 72 hours."),
        Tip(title: "Save battery",
            body: "Turn on Low Power Mode, lower screen brightness, and close other apps. Send short messages and check in at set times instead of constantly."),
        Tip(title: "Tell people you're OK",
            body: "Use Check in on the People tab to send \"I'm safe\" or \"I need help\" to everyone you pick in one tap. Agree with family ahead of time where to meet if you can't reach each other."),
        Tip(title: "Injuries",
            body: "For heavy bleeding, press firmly on the wound with a clean cloth and keep pressing. Keep injured people warm and still. Don't move someone with a possible neck or back injury unless they are in danger."),
        Tip(title: "Water and food",
            body: "Plan for at least one gallon (about 4 liters) of water per person per day. If tap water may be unsafe, boil it for one minute, or use unscented household bleach as directed on the label."),
        Tip(title: "Power and heat",
            body: "Never run a generator, grill, or camp stove indoors or in a garage. Carbon monoxide has no smell and can kill. Stay away from downed power lines."),
        Tip(title: "Check messages are really from them",
            body: "Anyone can type any name or phone number. A blue seal means you checked that person in person by QR code. Vouched means someone you checked has checked them. Be careful with requests for money or to meet."),
    ]
}

struct EmergencyInfoView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                Section {
                    Text(verbatim: "These tips are saved in the app and work with no internet. They are general guidance, not professional advice. Follow instructions from local officials.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                ForEach(EmergencyTips.tips) { tip in
                    Section {
                        Text(verbatim: tip.body)
                    } header: {
                        Text(verbatim: tip.title)
                    }
                }
            }
            .navigationTitle(Text(verbatim: "Emergency tips"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text(verbatim: "Done") }
                }
            }
        }
    }
}

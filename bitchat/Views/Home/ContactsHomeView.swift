//
// ContactsHomeView.swift
// Meshline
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import BitFoundation
import SwiftUI
#if os(iOS)
import ContactsUI
#endif

/// Pure grouping for the People screen, kept testable.
enum ContactsHomeSections {
    /// Saved people: favorites and anyone verified in person.
    static func isContact(_ row: MeshPeerRow) -> Bool {
        !row.isMe && !row.isBlocked
            && (row.isFavorite || row.encryptionStatus == .noiseVerified || row.showsVerifiedBadgeWhenOffline)
    }

    /// Others in range right now who are not saved yet.
    static func isNearbyStranger(_ row: MeshPeerRow) -> Bool {
        !row.isMe && !row.isBlocked && !isContact(row) && (row.isConnected || row.isReachable)
    }

    static func contacts(_ rows: [MeshPeerRow]) -> [MeshPeerRow] {
        rows.filter(isContact).sorted { lhs, rhs in
            if lhs.isReachable != rhs.isReachable { return lhs.isReachable }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    static func nearby(_ rows: [MeshPeerRow]) -> [MeshPeerRow] {
        rows.filter(isNearbyStranger)
    }

    static func statusText(_ row: MeshPeerRow) -> String {
        if row.isConnected { return "Nearby now" }
        if row.isReachable { return "In range through others" }
        return "Not in range. Messages wait and send when they are."
    }
}

struct ContactsHomeView: View {
    @EnvironmentObject private var peerListModel: PeerListModel
    @EnvironmentObject private var verificationModel: VerificationModel
    @EnvironmentObject private var conversationUIModel: ConversationUIModel
    @StateObject private var labelStore = ContactLabelStore.shared

    let onOpenChat: () -> Void

    @State private var showAddContact = false
    @State private var showSettings = false
    @State private var renamingRow: MeshPeerRow?
    @State private var renameText = ""
    #if os(iOS)
    @State private var pickingContactFor: MeshPeerRow?
    #endif

    private var contacts: [MeshPeerRow] { ContactsHomeSections.contacts(peerListModel.meshRows) }
    private var nearby: [MeshPeerRow] { ContactsHomeSections.nearby(peerListModel.meshRows) }

    var body: some View {
        NavigationView {
            List {
                Section {
                    Button {
                        showAddContact = true
                    } label: {
                        Label {
                            Text(verbatim: "Add someone in person")
                        } icon: {
                            Image(systemName: "qrcode.viewfinder")
                        }
                    }
                    ShareLink(item: MeshlineInvite.message) {
                        Label {
                            Text(verbatim: "Invite friends to Meshline")
                        } icon: {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }

                Section {
                    if contacts.isEmpty {
                        Text(verbatim: "No saved people yet. Meet up with a friend, tap \"Add someone in person\" and scan each other's code.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(contacts) { row in
                            personRow(row, isContact: true)
                        }
                    }
                } header: {
                    Text(verbatim: "My people")
                }

                Section {
                    if nearby.isEmpty {
                        Text(verbatim: "Nobody else with Meshline is in range right now.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(nearby) { row in
                            personRow(row, isContact: false)
                        }
                    }
                } header: {
                    Text(verbatim: "Nearby now")
                } footer: {
                    Text(verbatim: "Meshline works with no internet or cell service. Phones pass messages along to each other, so more people nearby means longer reach.")
                }
            }
            .navigationTitle(Text(verbatim: "People"))
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel(Text(verbatim: "Settings"))
                }
            }
        }
        .sheet(isPresented: $showAddContact) {
            AddContactSheet(isPresented: $showAddContact)
                .environmentObject(verificationModel)
        }
        .sheet(isPresented: $showSettings) {
            AppInfoView()
        }
        #if os(iOS)
        .sheet(item: $pickingContactFor) { row in
            ContactNamePicker { name in
                labelStore.setLabel(name, for: labelKey(for: row))
                pickingContactFor = nil
            } onCancel: {
                pickingContactFor = nil
            }
        }
        #endif
        .alert(Text(verbatim: "Name this person"), isPresented: Binding(
            get: { renamingRow != nil },
            set: { if !$0 { renamingRow = nil } }
        )) {
            TextField(text: $renameText) {
                Text(verbatim: "Name")
            }
            Button {
                if let row = renamingRow {
                    labelStore.setLabel(renameText, for: labelKey(for: row))
                }
                renamingRow = nil
            } label: {
                Text(verbatim: "Save")
            }
            Button(role: .cancel) {
                renamingRow = nil
            } label: {
                Text(verbatim: "Cancel")
            }
        } message: {
            Text(verbatim: "Only you see this name. It stays on this phone.")
        }
    }

    private func labelKey(for row: MeshPeerRow) -> String {
        conversationUIModel.getFingerprint(for: row.peerID) ?? row.peerID.id
    }

    private func displayName(for row: MeshPeerRow) -> String {
        labelStore.label(for: labelKey(for: row)) ?? row.displayName
    }

    @ViewBuilder
    private func personRow(_ row: MeshPeerRow, isContact: Bool) -> some View {
        Button {
            peerListModel.startConversation(with: row.peerID)
            onOpenChat()
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(row.isReachable || row.isConnected ? Color.green : Color.gray.opacity(0.5))
                    .frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(verbatim: displayName(for: row))
                            .font(.body.weight(.semibold))
                        if row.encryptionStatus == .noiseVerified || row.showsVerifiedBadgeWhenOffline {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundColor(.blue)
                                .accessibilityLabel(Text(verbatim: "Checked in person"))
                        }
                    }
                    Text(verbatim: ContactsHomeSections.statusText(row))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if row.hasUnread {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 10, height: 10)
                        .accessibilityLabel(Text(verbatim: "New message"))
                }
                Image(systemName: "message")
                    .foregroundColor(.accentColor)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                peerListModel.startConversation(with: row.peerID)
                onOpenChat()
            } label: {
                Text(verbatim: "Send message")
            }
            if isContact {
                Button {
                    renameText = displayName(for: row)
                    renamingRow = row
                } label: {
                    Text(verbatim: "Rename")
                }
                #if os(iOS)
                Button {
                    pickingContactFor = row
                } label: {
                    Text(verbatim: "Name from my Contacts")
                }
                #endif
                if row.isFavorite {
                    Button(role: .destructive) {
                        peerListModel.toggleFavorite(peerID: row.peerID)
                    } label: {
                        Text(verbatim: "Remove from my people")
                    }
                }
            } else {
                Button {
                    peerListModel.toggleFavorite(peerID: row.peerID)
                } label: {
                    Text(verbatim: "Save to my people")
                }
            }
        }
    }
}

/// Show my code, or scan theirs. Reuses bitchat's in-person verification.
struct AddContactSheet: View {
    @EnvironmentObject private var verificationModel: VerificationModel
    @Binding var isPresented: Bool
    @State private var scanning = false

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                Picker(selection: $scanning) {
                    Text(verbatim: "Show my code").tag(false)
                    Text(verbatim: "Scan their code").tag(true)
                } label: {
                    Text(verbatim: "Mode")
                }
                .pickerStyle(.segmented)

                Text(verbatim: scanning
                     ? "Point your camera at the code on your friend's phone."
                     : "Have your friend scan this code. Then scan theirs so you both save each other.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if scanning {
                    QRScanView(isActive: scanning, onSuccess: {
                        scanning = false
                        isPresented = false
                    })
                    .environmentObject(verificationModel)
                    .frame(minHeight: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    MyQRView(qrString: verificationModel.myQRString())
                }
                Spacer()
            }
            .padding(20)
            .navigationTitle(Text(verbatim: "Add someone"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        isPresented = false
                    } label: {
                        Text(verbatim: "Done")
                    }
                }
            }
        }
        .onDisappear { scanning = false }
    }
}

#if os(iOS)
/// System contact picker. Runs out of process, so Meshline only receives the
/// one name the user picks; nothing else from the address book is read.
struct ContactNamePicker: UIViewControllerRepresentable {
    let onPick: (String) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick, onCancel: onCancel) }

    final class Coordinator: NSObject, CNContactPickerDelegate {
        let onPick: (String) -> Void
        let onCancel: () -> Void

        init(onPick: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            let name = CNContactFormatter.string(from: contact, style: .fullName)
                ?? [contact.givenName, contact.familyName].filter { !$0.isEmpty }.joined(separator: " ")
            if name.isEmpty { onCancel() } else { onPick(name) }
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            onCancel()
        }
    }
}
#endif

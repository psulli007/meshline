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
    @StateObject private var importModel = ContactImportModel.shared
    @Environment(\.openURL) private var openURL

    let onOpenChat: () -> Void

    @State private var showAddContact = false
    @State private var showSettings = false
    @State private var renamingRow: MeshPeerRow?
    @State private var renameText = ""
    @State private var showNewGroup = false
    @State private var showPhoneNumber = false
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
                            Text(verbatim: "Add or check someone in person")
                        } icon: {
                            Image(systemName: "qrcode.viewfinder")
                        }
                    }
                    Button {
                        importModel.importContacts()
                    } label: {
                        Label {
                            Text(verbatim: importModel.isImporting ? "Looking through your Contacts..." : "Find friends from my Contacts")
                        } icon: {
                            Image(systemName: "person.crop.circle.badge.plus")
                        }
                    }
                    .disabled(importModel.isImporting)
                    Button {
                        showNewGroup = true
                    } label: {
                        Label {
                            Text(verbatim: "New group")
                        } icon: {
                            Image(systemName: "person.3")
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
                } footer: {
                    if let error = importModel.lastError {
                        Text(verbatim: error)
                    } else {
                        Text(verbatim: "People found by phone number say \"Unverified number\" until you check them in person, because anyone can type any number.")
                    }
                }

                if !peerListModel.groupRows.isEmpty {
                    Section {
                        ForEach(peerListModel.groupRows) { group in
                            Button {
                                peerListModel.startConversation(with: group.peerID)
                                onOpenChat()
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(verbatim: group.name)
                                            .font(.body.weight(.semibold))
                                        Spacer()
                                        if group.hasUnread {
                                            Circle().fill(Color.blue).frame(width: 10, height: 10)
                                        }
                                    }
                                    Text(verbatim: peerListModel.groupMemberNames(for: group.peerID).joined(separator: ", "))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text(verbatim: "Groups")
                    }
                }

                if !importModel.unmatched.isEmpty {
                    Section {
                        ForEach(importModel.unmatched) { contact in
                            HStack {
                                Text(verbatim: contact.name)
                                Spacer()
                                Button {
                                    if let url = ContactImportModel.inviteURL(number: contact.number) {
                                        openURL(url)
                                    }
                                } label: {
                                    Text(verbatim: "Invite")
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    } header: {
                        Text(verbatim: "Not found nearby yet")
                    } footer: {
                        Text(verbatim: "They may not have Meshline, or just aren't in range. If they join and come near, they show up in My people.")
                    }
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
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        showPhoneNumber = true
                    } label: {
                        Text(verbatim: "My number")
                    }
                }
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
        .sheet(isPresented: $showNewGroup) {
            NewGroupSheet(
                people: contacts + nearby,
                nameFor: displayName(for:),
                onCreated: onOpenChat
            )
            .environmentObject(peerListModel)
        }
        .sheet(isPresented: $showPhoneNumber) {
            PhoneNumberSheet()
        }
        .onAppear {
            if !MyPhoneNumber.wasAsked { showPhoneNumber = true }
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

    private func isVerified(_ row: MeshPeerRow) -> Bool {
        row.encryptionStatus == .noiseVerified || row.showsVerifiedBadgeWhenOffline
    }

    private func isUnverifiedNumber(_ row: MeshPeerRow) -> Bool {
        !isVerified(row) && importModel.isPhoneMatched(fingerprint: labelKey(for: row))
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
                    if isUnverifiedNumber(row) {
                        Text(verbatim: "Unverified number")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.orange)
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

/// Pick people, name the group. Uses bitchat's end-to-end encrypted groups.
struct NewGroupSheet: View {
    @EnvironmentObject private var peerListModel: PeerListModel
    @Environment(\.dismiss) private var dismiss
    let people: [MeshPeerRow]
    let nameFor: (MeshPeerRow) -> String
    let onCreated: () -> Void

    @State private var groupName = ""
    @State private var picked: Set<PeerID> = []
    @State private var notAdded: [String] = []

    private var canCreate: Bool {
        !groupName.trimmingCharacters(in: .whitespaces).isEmpty && !picked.isEmpty
    }

    var body: some View {
        NavigationView {
            List {
                Section {
                    TextField(text: $groupName) {
                        Text(verbatim: "Group name")
                    }
                }
                Section {
                    if people.isEmpty {
                        Text(verbatim: "Add some people first.")
                            .foregroundColor(.secondary)
                    }
                    ForEach(people) { row in
                        Button {
                            if picked.contains(row.peerID) { picked.remove(row.peerID) } else { picked.insert(row.peerID) }
                        } label: {
                            HStack {
                                Image(systemName: picked.contains(row.peerID) ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(.accentColor)
                                Text(verbatim: nameFor(row))
                                Spacer()
                                if !row.isConnected {
                                    Text(verbatim: "Not nearby")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text(verbatim: "Who's in it")
                } footer: {
                    Text(verbatim: "Group messages are end-to-end encrypted. People need to be nearby when you create the group to get the invite. Up to 16 people.")
                }
            }
            .navigationTitle(Text(verbatim: "New group"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text(verbatim: "Cancel") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        create()
                    } label: {
                        Text(verbatim: "Create")
                    }
                    .disabled(!canCreate)
                }
            }
            .alert(Text(verbatim: "Group created"), isPresented: Binding(
                get: { !notAdded.isEmpty },
                set: { if !$0 { notAdded = []; dismiss(); onCreated() } }
            )) {
                Button {} label: { Text(verbatim: "OK") }
            } message: {
                Text(verbatim: "Couldn't add \(notAdded.joined(separator: ", ")) yet. They need to be nearby. Open the group later to add them when they are.")
            }
        }
    }

    private func create() {
        let members = people
            .filter { picked.contains($0.peerID) }
            .map { (peerID: $0.peerID, name: $0.displayName) }
        let result = peerListModel.createGroup(named: groupName.trimmingCharacters(in: .whitespaces), members: members)
        if !result.created {
            notAdded = members.map(\.name)
            return
        }
        if result.failedNames.isEmpty {
            dismiss()
            onCreated()
        } else {
            notAdded = result.failedNames
        }
    }
}

/// Ask for the user's own number. No SMS, never checked, stored on this
/// phone; only a scrambled version is shared with nearby phones.
struct PhoneNumberSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var number = MyPhoneNumber.stored ?? ""
    @State private var invalid = false

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField(text: $number) {
                        Text(verbatim: "Your phone number")
                    }
                    #if os(iOS)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                    #endif
                    if invalid {
                        Text(verbatim: "That doesn't look like a full number. Include the country code if you're outside the US.")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                } footer: {
                    Text(verbatim: "Friends who have your number in their Contacts can find you, even with no internet. Your number stays on this phone. Nearby phones only get a scrambled version of it. Nothing is checked and no text is sent.")
                }
            }
            .navigationTitle(Text(verbatim: "Your number"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        if !MyPhoneNumber.wasAsked { MyPhoneNumber.save(nil) }
                        dismiss()
                    } label: {
                        Text(verbatim: MyPhoneNumber.wasAsked ? "Cancel" : "Skip")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        if MyPhoneNumber.save(number) { dismiss() } else { invalid = true }
                    } label: {
                        Text(verbatim: "Save")
                    }
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

//
// MeshlineHomeView.swift
// Meshline
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import SwiftUI

/// People first home: the contact list is the main screen; the nearby group
/// chat and private conversations live on the second tab.
struct MeshlineHomeView: View {
    enum Tab: Hashable {
        case people
        case chats
    }

    @State private var selectedTab: Tab = .people
    @StateObject private var inviteNudge = InviteNudge.shared

    var body: some View {
        TabView(selection: $selectedTab) {
            ContactsHomeView(onOpenChat: { selectedTab = .chats })
                .tabItem {
                    Label {
                        Text(verbatim: "People")
                    } icon: {
                        Image(systemName: "person.2.fill")
                    }
                }
                .tag(Tab.people)

            ContentView()
                .tabItem {
                    Label {
                        Text(verbatim: "Chats")
                    } icon: {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                    }
                }
                .tag(Tab.chats)
        }
        .sheet(isPresented: $inviteNudge.isShowing) {
            InviteNudgeSheet()
        }
        #if DEBUG
        .onAppear { if ScreenshotDemo.screen == "chat" { selectedTab = .chats } }
        #endif
    }
}

/// Shown once after the first message: the network only works if people
/// near you have the app.
struct InviteNudgeSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.3.fill")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)
            Text(verbatim: "Your first message is on its way")
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
            Text(verbatim: "Meshline gets stronger with every phone that has it. Invite 3 people you would want to reach in an emergency, like family, roommates, or neighbors.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            ShareLink(item: MeshlineInvite.message) {
                Text(verbatim: "Invite 3 people")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            Button {
                dismiss()
            } label: {
                Text(verbatim: "Not now")
            }
        }
        .padding(28)
    }
}

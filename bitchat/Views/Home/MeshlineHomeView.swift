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
        #if DEBUG
        .onAppear { if ScreenshotDemo.screen == "chat" { selectedTab = .chats } }
        #endif
    }
}

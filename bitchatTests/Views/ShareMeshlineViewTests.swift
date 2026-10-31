//
// ShareMeshlineViewTests.swift
// bitchatTests
//

import Testing
import Foundation
@testable import bitchat

struct ShareMeshlineViewTests {
    @Test
    func qrImage_rendersForShareLink() async {
        let image = ShareMeshlineView.qrImage(for: MeshlineShareLink.url.absoluteString)
        #expect(image != nil)
        #expect((image?.width ?? 0) > 100)
    }

    @Test
    func shareLink_isHTTPS() async {
        #expect(MeshlineShareLink.url.scheme == "https")
    }
}

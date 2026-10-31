//
// MultipeerLinkService.swift
// Meshline
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import BitFoundation
import BitLogger
import Foundation
import MultipeerConnectivity
#if os(iOS)
import UIKit
#endif

/// Pure policy for the Wi-Fi (MultipeerConnectivity) link layer, kept free of
/// framework types so it is unit-testable.
enum MultipeerLinkPolicy {
    /// Bonjour service type: 1-15 chars, lowercase letters, digits, hyphen.
    /// Must match NSBonjourServices in Info.plist (_meshline-mesh._tcp/_udp).
    static let serviceType = "meshline-mesh"
    /// Largest frame accepted from a Wi-Fi peer. Packets are text or chunked
    /// media; anything bigger is dropped before decoding.
    static let maxInboundFrameBytes = 512 * 1024
    /// Sessions this device keeps open at once (MCSession supports 8 peers).
    static let maxConnectedPeers = 7
    static let invitationTimeout: TimeInterval = 15

    /// Exactly one side invites, so two browsers never cross-invite.
    static func shouldInvite(localName: String, remoteName: String) -> Bool {
        localName < remoteName
    }

    static func acceptsFrame(byteCount: Int) -> Bool {
        byteCount > 0 && byteCount <= maxInboundFrameBytes
    }

    /// A random, non-identifying display name. The nickname and peer ID are
    /// never put in Bonjour records.
    static func randomDisplayName() -> String {
        var bytes = [UInt8](repeating: 0, count: 8)
        for index in bytes.indices { bytes[index] = UInt8.random(in: 0...255) }
        return "ml-" + bytes.map { String(format: "%02x", $0) }.joined()
    }
}

/// Wi-Fi peer-to-peer link alongside BLE. A dumb pipe: it carries the same
/// encoded `BitchatPacket` frames BLE carries, so routing, dedupe, TTL relay
/// and Noise encryption all stay in `BLEService`. Packets relayed by
/// `BLEService` go out on both radios, which bridges BLE-only and
/// Wi-Fi-only neighbors. Advertises and browses only while the app is active.
final class MultipeerLinkService: NSObject {
    /// Called on an internal queue with each decoded inbound packet.
    var onPacket: ((BitchatPacket) -> Void)?

    private let queue = DispatchQueue(label: "meshline.multipeer")
    private let localPeer: MCPeerID
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var running = false
    private var wantsRunning = false
    private var observers: [NSObjectProtocol] = []
    /// Connected-peer count mirrored under a lock, so `send` never blocks on
    /// `queue` (it can be called from relay paths that run on any queue).
    private let countLock = NSLock()
    private var connectedCountSnapshot = 0

    override init() {
        localPeer = MCPeerID(displayName: MultipeerLinkPolicy.randomDisplayName())
        super.init()
        #if os(iOS)
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: nil) { [weak self] _ in
            self?.queue.async { self?.applyStateLocked(appActive: true) }
        })
        observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: nil) { [weak self] _ in
            self?.queue.async { self?.applyStateLocked(appActive: false) }
        })
        #endif
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    /// Start advertising/browsing (now if the app is active, else on next activation).
    func start() {
        queue.async { [weak self] in
            guard let self else { return }
            self.wantsRunning = true
            self.applyStateLocked(appActive: true)
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.wantsRunning = false
            self.tearDownLocked()
        }
    }

    var connectedPeerCount: Int {
        countLock.lock()
        defer { countLock.unlock() }
        return connectedCountSnapshot
    }

    /// Queues an encoded packet frame for every connected Wi-Fi peer.
    /// Returns true when at least one peer was connected at call time.
    /// Never blocks the caller.
    @discardableResult
    func send(_ data: Data) -> Bool {
        guard connectedPeerCount > 0 else { return false }
        queue.async { [weak self] in
            guard let session = self?.session, !session.connectedPeers.isEmpty else { return }
            do {
                try session.send(data, toPeers: session.connectedPeers, with: .reliable)
            } catch {
                SecureLogger.debug("📶 Wi-Fi send failed: \(error.localizedDescription)", category: .session)
            }
        }
        return true
    }

    private func setConnectedCount(_ count: Int) {
        countLock.lock()
        connectedCountSnapshot = count
        countLock.unlock()
    }

    // MARK: - Lifecycle (queue-confined)

    private func applyStateLocked(appActive: Bool) {
        if wantsRunning && appActive {
            startLocked()
        } else {
            tearDownLocked()
        }
    }

    private func startLocked() {
        guard !running else { return }
        let session = MCSession(peer: localPeer, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        let advertiser = MCNearbyServiceAdvertiser(peer: localPeer, discoveryInfo: nil, serviceType: MultipeerLinkPolicy.serviceType)
        advertiser.delegate = self
        let browser = MCNearbyServiceBrowser(peer: localPeer, serviceType: MultipeerLinkPolicy.serviceType)
        browser.delegate = self
        self.session = session
        self.advertiser = advertiser
        self.browser = browser
        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()
        running = true
        SecureLogger.info("📶 Wi-Fi mesh link started", category: .session)
    }

    private func tearDownLocked() {
        guard running else { return }
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        session?.disconnect()
        advertiser = nil
        browser = nil
        session = nil
        running = false
        setConnectedCount(0)
        SecureLogger.info("📶 Wi-Fi mesh link stopped", category: .session)
    }

    private func handleInbound(_ data: Data) {
        guard MultipeerLinkPolicy.acceptsFrame(byteCount: data.count),
              let packet = BinaryProtocol.decode(data) else {
            return
        }
        onPacket?(packet)
    }
}

extension MultipeerLinkService: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        SecureLogger.debug("📶 Wi-Fi peer state \(state.rawValue)", category: .session)
        let count = session.connectedPeers.count
        queue.async { [weak self] in
            // Ignore callbacks from a session that was already torn down.
            guard let self, self.session === session else { return }
            self.setConnectedCount(count)
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        queue.async { [weak self] in self?.handleInbound(data) }
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        stream.close()
    }

    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        progress.cancel()
    }

    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

extension MultipeerLinkService: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        queue.async { [weak self] in
            guard let self, let session = self.session,
                  session.connectedPeers.count < MultipeerLinkPolicy.maxConnectedPeers else {
                invitationHandler(false, nil)
                return
            }
            invitationHandler(true, session)
        }
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        SecureLogger.warning("📶 Wi-Fi advertise failed: \(error.localizedDescription)", category: .session)
    }
}

extension MultipeerLinkService: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        queue.async { [weak self] in
            guard let self, let session = self.session,
                  MultipeerLinkPolicy.shouldInvite(localName: self.localPeer.displayName, remoteName: peerID.displayName),
                  !session.connectedPeers.contains(peerID),
                  session.connectedPeers.count < MultipeerLinkPolicy.maxConnectedPeers else {
                return
            }
            browser.invitePeer(peerID, to: session, withContext: nil, timeout: MultipeerLinkPolicy.invitationTimeout)
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}

    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        SecureLogger.warning("📶 Wi-Fi browse failed: \(error.localizedDescription)", category: .session)
    }
}

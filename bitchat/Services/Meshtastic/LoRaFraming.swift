//
// LoRaFraming.swift
// Meshline
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import BitFoundation
import CryptoKit
import Foundation

/// Splits a Meshline frame into chunks that fit one LoRa Data payload.
///
/// Chunk layout (7 byte header):
///   [0] magic 0x4D ("M")
///   [1] chunk index (0 based)
///   [2] chunk count (1...maxChunks)
///   [3..6] message id, big endian
///   [7...] frame bytes
enum LoRaFraming {
    static let magic: UInt8 = 0x4D
    static let headerBytes = 7
    static let chunkPayloadBytes = MeshtasticMessages.maxDataPayloadBytes - headerBytes
    /// LoRa airtime is scarce (about 1 to 2 seconds per full chunk on the
    /// default preset), so frames needing more chunks are not sent.
    static let maxChunks = 4
    static var maxFrameBytes: Int { chunkPayloadBytes * maxChunks }

    struct Chunk: Equatable {
        let messageID: UInt32
        let index: Int
        let count: Int
        let body: Data
    }

    static func split(_ frame: Data, messageID: UInt32) -> [Data]? {
        guard !frame.isEmpty, frame.count <= maxFrameBytes else { return nil }
        let bytes = [UInt8](frame)
        let count = (bytes.count + chunkPayloadBytes - 1) / chunkPayloadBytes
        var chunks: [Data] = []
        chunks.reserveCapacity(count)
        for index in 0..<count {
            var chunk = Data([
                magic,
                UInt8(index),
                UInt8(count),
                UInt8(truncatingIfNeeded: messageID >> 24),
                UInt8(truncatingIfNeeded: messageID >> 16),
                UInt8(truncatingIfNeeded: messageID >> 8),
                UInt8(truncatingIfNeeded: messageID)
            ])
            let start = index * chunkPayloadBytes
            let end = min(start + chunkPayloadBytes, bytes.count)
            chunk.append(contentsOf: bytes[start..<end])
            chunks.append(chunk)
        }
        return chunks
    }

    static func parse(_ data: Data) -> Chunk? {
        let bytes = [UInt8](data)
        guard bytes.count > headerBytes, bytes[0] == magic else { return nil }
        let index = Int(bytes[1])
        let count = Int(bytes[2])
        guard count >= 1, count <= maxChunks, index < count else { return nil }
        let messageID = (UInt32(bytes[3]) << 24) | (UInt32(bytes[4]) << 16) | (UInt32(bytes[5]) << 8) | UInt32(bytes[6])
        return Chunk(messageID: messageID, index: index, count: count, body: Data(bytes[headerBytes...]))
    }
}

/// Collects chunks per (radio node, message id). Bounded in entries and age.
struct LoRaReassembler {
    static let maxPartials = 32
    static let partialLifetime: TimeInterval = 120

    private struct Key: Hashable {
        let node: UInt32
        let messageID: UInt32
    }

    private struct Partial {
        let count: Int
        var parts: [Int: Data]
        let firstSeen: Date
    }

    private var partials: [Key: Partial] = [:]

    var pendingCount: Int { partials.count }

    /// Returns the full frame once every chunk has arrived.
    mutating func add(_ chunk: LoRaFraming.Chunk, from node: UInt32, now: Date = Date()) -> Data? {
        prune(now: now)
        if chunk.count == 1 { return chunk.body }
        let key = Key(node: node, messageID: chunk.messageID)
        var partial = partials[key] ?? Partial(count: chunk.count, parts: [:], firstSeen: now)
        guard partial.count == chunk.count else {
            partials[key] = nil
            return nil
        }
        partial.parts[chunk.index] = chunk.body
        if partial.parts.count == partial.count {
            partials[key] = nil
            var frame = Data()
            for i in 0..<partial.count {
                guard let part = partial.parts[i] else { return nil }
                frame.append(part)
            }
            return frame
        }
        if partials[key] == nil, partials.count >= Self.maxPartials,
           let oldest = partials.min(by: { $0.value.firstSeen < $1.value.firstSeen })?.key {
            partials[oldest] = nil
        }
        partials[key] = partial
        return nil
    }

    private mutating func prune(now: Date) {
        partials = partials.filter { now.timeIntervalSince($0.value.firstSeen) < Self.partialLifetime }
    }
}

/// Decides which mesh packets are worth LoRa airtime, and rate limits them.
struct LoRaForwardPolicy {
    /// Text, private messages, handshakes they need, store-carry-forward
    /// envelopes, board posts, group messages and (throttled) announces.
    /// Bulk and chatty local types (files, voice, sync, BLE fragments,
    /// prekey gossip, ping) stay off LoRa.
    static let allowedTypes: Set<UInt8> = [
        MessageType.message.rawValue,
        MessageType.noiseEncrypted.rawValue,
        MessageType.noiseHandshake.rawValue,
        MessageType.courierEnvelope.rawValue,
        MessageType.boardPost.rawValue,
        MessageType.groupMessage.rawValue,
        MessageType.announce.rawValue
    ]
    static let announceMinInterval: TimeInterval = 300
    /// Token bucket in chunks: a burst of 12, refilling 6 per minute.
    static let bucketCapacity: Double = 12
    static let refillPerSecond: Double = 6.0 / 60.0
    static let recentKeyLimit = 512

    private var tokens: Double = bucketCapacity
    private var lastRefill: Date?
    private var lastAnnounce: Date?
    private var recentKeys: [Data] = []
    private var recentKeySet: Set<Data> = []

    /// Identity of a packet that survives relay (TTL changes, bytes do not).
    static func key(for packet: BitchatPacket) -> Data {
        var hasher = SHA256()
        hasher.update(data: packet.senderID)
        var ts = packet.timestamp.bigEndian
        withUnsafeBytes(of: &ts) { hasher.update(bufferPointer: $0) }
        hasher.update(data: Data([packet.type]))
        hasher.update(data: packet.payload)
        return Data(hasher.finalize().prefix(16))
    }

    /// Records a packet that arrived over LoRa so it is never echoed back.
    mutating func noteReceived(_ packet: BitchatPacket) {
        remember(Self.key(for: packet))
    }

    /// True if the packet should go out over LoRa now. Consumes tokens.
    mutating func admit(_ packet: BitchatPacket, chunkCount: Int, now: Date = Date()) -> Bool {
        guard Self.allowedTypes.contains(packet.type), chunkCount > 0 else { return false }
        let key = Self.key(for: packet)
        guard !recentKeySet.contains(key) else { return false }
        if packet.type == MessageType.announce.rawValue,
           let last = lastAnnounce, now.timeIntervalSince(last) < Self.announceMinInterval {
            return false
        }
        refill(now: now)
        guard tokens >= Double(chunkCount) else { return false }
        tokens -= Double(chunkCount)
        if packet.type == MessageType.announce.rawValue { lastAnnounce = now }
        remember(key)
        return true
    }

    private mutating func refill(now: Date) {
        if let last = lastRefill {
            tokens = min(Self.bucketCapacity, tokens + max(0, now.timeIntervalSince(last)) * Self.refillPerSecond)
        }
        lastRefill = now
    }

    private mutating func remember(_ key: Data) {
        guard recentKeySet.insert(key).inserted else { return }
        recentKeys.append(key)
        if recentKeys.count > Self.recentKeyLimit {
            recentKeySet.remove(recentKeys.removeFirst())
        }
    }
}

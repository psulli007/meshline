//
// MeshtasticLoRaTests.swift
// bitchatTests
//

import BitFoundation
import Foundation
import Testing
@testable import bitchat

struct MeshtasticLoRaTests {
    private func packet(type: MessageType, payload: Data = Data("hi".utf8), timestamp: UInt64 = 1_000) -> BitchatPacket {
        BitchatPacket(
            type: type.rawValue,
            senderID: Data([1, 2, 3, 4, 5, 6, 7, 8]),
            recipientID: nil,
            timestamp: timestamp,
            payload: payload,
            signature: nil,
            ttl: 7
        )
    }

    // MARK: Wire

    @Test
    func varint_roundTrips() async {
        for value: UInt64 in [0, 1, 127, 128, 300, 0xFFFF_FFFF, UInt64.max] {
            var data = Data()
            ProtoWire.appendVarintField(5, value, to: &data)
            #expect(ProtoWire.parse(data) == [ProtoWire.Field(number: 5, value: .varint(value))])
        }
    }

    @Test
    func wantConfig_encodesField3() async {
        #expect(MeshtasticMessages.wantConfig(id: 300) == Data([0x18, 0xAC, 0x02]))
    }

    @Test
    func parse_rejectsTruncatedLength() async {
        #expect(ProtoWire.parse(Data([0x12, 0x05, 0x01])) == nil)
        #expect(ProtoWire.parse(Data([0x0B])) == nil) // group wire type
    }

    @Test
    func broadcastPrivateApp_decodesAsFromRadioPacket() async throws {
        let toRadio = MeshtasticMessages.broadcastPrivateApp(payload: Data([9, 8, 7]), packetID: 42)
        let fields = try #require(ProtoWire.parse(toRadio))
        guard case .bytes(let meshPacket) = try #require(fields.first).value else {
            Issue.record("expected packet bytes"); return
        }
        // Simulate the radio delivering it: FromRadio.packet (2) with from (1).
        var withFrom = Data()
        ProtoWire.appendFixed32Field(1, 0x1234_5678, to: &withFrom)
        withFrom.append(meshPacket)
        var fromRadio = Data()
        ProtoWire.appendBytesField(2, withFrom, to: &fromRadio)
        #expect(MeshtasticMessages.decodeFromRadio(fromRadio) == .privateApp(from: 0x1234_5678, payload: Data([9, 8, 7])))
    }

    @Test
    func decodeFromRadio_readsMyInfoAndConfigComplete() async {
        var info = Data()
        ProtoWire.appendVarintField(1, 77, to: &info)
        var myInfo = Data()
        ProtoWire.appendBytesField(3, info, to: &myInfo)
        #expect(MeshtasticMessages.decodeFromRadio(myInfo) == .myNodeNum(77))

        var complete = Data()
        ProtoWire.appendVarintField(1, 5, to: &complete)
        ProtoWire.appendVarintField(7, 99, to: &complete)
        #expect(MeshtasticMessages.decodeFromRadio(complete) == .configComplete(99))
    }

    @Test
    func decodeFromRadio_ignoresOtherPorts() async {
        var dataMsg = Data()
        ProtoWire.appendVarintField(1, 1, to: &dataMsg) // TEXT_MESSAGE_APP
        ProtoWire.appendBytesField(2, Data("x".utf8), to: &dataMsg)
        var meshPacket = Data()
        ProtoWire.appendFixed32Field(1, 1, to: &meshPacket)
        ProtoWire.appendBytesField(4, dataMsg, to: &meshPacket)
        var fromRadio = Data()
        ProtoWire.appendBytesField(2, meshPacket, to: &fromRadio)
        #expect(MeshtasticMessages.decodeFromRadio(fromRadio) == .other)
    }

    // MARK: Framing

    @Test
    func split_fitsLoRaPayloadAndReassembles() async throws {
        let frame = Data((0..<600).map { UInt8($0 % 251) })
        let chunks = try #require(LoRaFraming.split(frame, messageID: 0xA1B2_C3D4))
        #expect(chunks.count == 3)
        #expect(chunks.allSatisfy { $0.count <= MeshtasticMessages.maxDataPayloadBytes })

        var reassembler = LoRaReassembler()
        var result: Data?
        for chunk in chunks.reversed() {
            result = try reassembler.add(#require(LoRaFraming.parse(chunk)), from: 7)
        }
        #expect(result == frame)
        #expect(reassembler.pendingCount == 0)
    }

    @Test
    func split_rejectsOversizedFrames() async {
        #expect(LoRaFraming.split(Data(count: LoRaFraming.maxFrameBytes + 1), messageID: 1) == nil)
        #expect(LoRaFraming.split(Data(), messageID: 1) == nil)
    }

    @Test
    func reassembler_keepsSendersApartAndExpires() async throws {
        let chunks = try #require(LoRaFraming.split(Data(count: 300), messageID: 5))
        let first = try #require(LoRaFraming.parse(chunks[0]))
        let second = try #require(LoRaFraming.parse(chunks[1]))
        var reassembler = LoRaReassembler()
        let now = Date(timeIntervalSince1970: 0)
        #expect(reassembler.add(first, from: 1, now: now) == nil)
        #expect(reassembler.add(second, from: 2, now: now) == nil)
        #expect(reassembler.pendingCount == 2)
        let later = now.addingTimeInterval(LoRaReassembler.partialLifetime + 1)
        #expect(reassembler.add(second, from: 1, now: later) == nil)
        #expect(reassembler.pendingCount == 1)
    }

    @Test
    func meshlineFrame_survivesLoRaRoundTrip() async throws {
        let original = packet(type: .message, payload: Data(repeating: 0x41, count: 400))
        let frame = try #require(original.toBinaryData(padding: false))
        let chunks = try #require(LoRaFraming.split(frame, messageID: 9))
        var reassembler = LoRaReassembler()
        var out: Data?
        for c in chunks { out = try reassembler.add(#require(LoRaFraming.parse(c)), from: 3) }
        let decoded = try #require(BinaryProtocol.decode(#require(out)))
        #expect(decoded.payload == original.payload)
        #expect(decoded.type == original.type)
    }

    // MARK: Policy

    @Test
    func policy_filtersTypesAndEchoes() async {
        var policy = LoRaForwardPolicy()
        let now = Date(timeIntervalSince1970: 0)
        #expect(!policy.admit(packet(type: .fileTransfer), chunkCount: 1, now: now))
        #expect(!policy.admit(packet(type: .requestSync), chunkCount: 1, now: now))
        #expect(policy.admit(packet(type: .message), chunkCount: 1, now: now))
        // Same packet again (for example a relay of it) is not resent.
        #expect(!policy.admit(packet(type: .message), chunkCount: 1, now: now))

        let fromLoRa = packet(type: .message, timestamp: 2_000)
        policy.noteReceived(fromLoRa)
        #expect(!policy.admit(fromLoRa, chunkCount: 1, now: now))
    }

    @Test
    func policy_rateLimitsChunksAndAnnounces() async {
        var policy = LoRaForwardPolicy()
        let now = Date(timeIntervalSince1970: 0)
        #expect(policy.admit(packet(type: .message, timestamp: 1), chunkCount: 4, now: now))
        #expect(policy.admit(packet(type: .message, timestamp: 2), chunkCount: 4, now: now))
        #expect(policy.admit(packet(type: .message, timestamp: 3), chunkCount: 4, now: now))
        #expect(!policy.admit(packet(type: .message, timestamp: 4), chunkCount: 1, now: now))
        #expect(policy.admit(packet(type: .message, timestamp: 5), chunkCount: 1, now: now.addingTimeInterval(20)))

        #expect(policy.admit(packet(type: .announce, timestamp: 10), chunkCount: 1, now: now.addingTimeInterval(600)))
        #expect(!policy.admit(packet(type: .announce, timestamp: 11), chunkCount: 1, now: now.addingTimeInterval(700)))
        #expect(policy.admit(packet(type: .announce, timestamp: 12), chunkCount: 1, now: now.addingTimeInterval(901)))
    }

    @Test
    func uuids_areWellFormed() async {
        for id in [MeshtasticBLE.serviceUUID, MeshtasticBLE.toRadioUUID, MeshtasticBLE.fromRadioUUID, MeshtasticBLE.fromNumUUID] {
            #expect(UUID(uuidString: id) != nil)
        }
    }
}

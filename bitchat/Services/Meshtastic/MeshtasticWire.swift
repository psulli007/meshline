//
// MeshtasticWire.swift
// Meshline
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//
// Hand-written, minimal protobuf wire encoding for the handful of Meshtastic
// phone-API fields Meshline needs. No generated code or .proto files are
// used; only the public field numbers of the radio's phone API.
//

import Foundation

/// Meshtastic BLE phone API identifiers.
enum MeshtasticBLE {
    static let serviceUUID = "6BA1B218-15A8-461F-9FA8-5DCAE273EAFD"
    /// Write: phone to radio.
    static let toRadioUUID = "F75C76D2-129E-4DAD-A1DD-7866124401E7"
    /// Read: radio to phone, one message per read until empty.
    static let fromRadioUUID = "2C55E69E-4993-11ED-B878-0242AC120002"
    /// Notify: bumps when FromRadio has new data.
    static let fromNumUUID = "ED9DA18C-A800-4F66-A670-AA7547E34453"
}

/// Minimal protobuf wire reader and writer.
enum ProtoWire {
    enum WireType: UInt8 {
        case varint = 0
        case fixed64 = 1
        case lengthDelimited = 2
        case fixed32 = 5
    }

    enum FieldValue: Equatable {
        case varint(UInt64)
        case fixed64(UInt64)
        case bytes(Data)
        case fixed32(UInt32)
    }

    struct Field: Equatable {
        let number: UInt32
        let value: FieldValue
    }

    // MARK: Writing

    static func appendVarint(_ value: UInt64, to data: inout Data) {
        var v = value
        while v >= 0x80 {
            data.append(UInt8(truncatingIfNeeded: v) | 0x80)
            v >>= 7
        }
        data.append(UInt8(truncatingIfNeeded: v))
    }

    static func appendKey(_ number: UInt32, _ type: WireType, to data: inout Data) {
        appendVarint((UInt64(number) << 3) | UInt64(type.rawValue), to: &data)
    }

    static func appendVarintField(_ number: UInt32, _ value: UInt64, to data: inout Data) {
        appendKey(number, .varint, to: &data)
        appendVarint(value, to: &data)
    }

    static func appendFixed32Field(_ number: UInt32, _ value: UInt32, to data: inout Data) {
        appendKey(number, .fixed32, to: &data)
        var le = value.littleEndian
        withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
    }

    static func appendBytesField(_ number: UInt32, _ value: Data, to data: inout Data) {
        appendKey(number, .lengthDelimited, to: &data)
        appendVarint(UInt64(value.count), to: &data)
        data.append(value)
    }

    // MARK: Reading

    /// Parses one message level. Returns nil on malformed input. Group wire
    /// types (3, 4) are not used by Meshtastic and are rejected.
    static func parse(_ input: Data) -> [Field]? {
        let bytes = [UInt8](input)
        var index = 0
        var fields: [Field] = []

        func readVarint() -> UInt64? {
            var result: UInt64 = 0
            var shift: UInt64 = 0
            while index < bytes.count {
                let byte = bytes[index]
                index += 1
                if shift >= 64 { return nil }
                result |= UInt64(byte & 0x7F) << shift
                if byte & 0x80 == 0 { return result }
                shift += 7
            }
            return nil
        }

        while index < bytes.count {
            guard let key = readVarint() else { return nil }
            let number = UInt32(truncatingIfNeeded: key >> 3)
            guard number > 0, let type = WireType(rawValue: UInt8(key & 0x07)) else { return nil }
            switch type {
            case .varint:
                guard let v = readVarint() else { return nil }
                fields.append(Field(number: number, value: .varint(v)))
            case .fixed64:
                guard index + 8 <= bytes.count else { return nil }
                var v: UInt64 = 0
                for i in 0..<8 { v |= UInt64(bytes[index + i]) << (8 * UInt64(i)) }
                index += 8
                fields.append(Field(number: number, value: .fixed64(v)))
            case .fixed32:
                guard index + 4 <= bytes.count else { return nil }
                var v: UInt32 = 0
                for i in 0..<4 { v |= UInt32(bytes[index + i]) << (8 * UInt32(i)) }
                index += 4
                fields.append(Field(number: number, value: .fixed32(v)))
            case .lengthDelimited:
                guard let len64 = readVarint(), len64 <= UInt64(bytes.count - index) else { return nil }
                let len = Int(len64)
                fields.append(Field(number: number, value: .bytes(Data(bytes[index..<(index + len)]))))
                index += len
            }
        }
        return fields
    }
}

/// The few Meshtastic phone API messages Meshline reads and writes.
enum MeshtasticMessages {
    /// PortNum.PRIVATE_APP: reserved for private applications.
    static let privateAppPort: UInt64 = 256
    static let broadcastNode: UInt32 = 0xFFFF_FFFF
    /// Largest Data.payload the radio accepts (DATA_PAYLOAD_LEN).
    static let maxDataPayloadBytes = 233
    static let defaultHopLimit: UInt64 = 3

    /// ToRadio { want_config_id = 3 }
    static func wantConfig(id: UInt32) -> Data {
        var out = Data()
        ProtoWire.appendVarintField(3, UInt64(id), to: &out)
        return out
    }

    /// ToRadio { packet = 1: MeshPacket { to = 2, decoded = 4: Data { portnum = 1, payload = 2 }, id = 6, hop_limit = 9 } }
    static func broadcastPrivateApp(payload: Data, packetID: UInt32, hopLimit: UInt64 = defaultHopLimit) -> Data {
        var dataMsg = Data()
        ProtoWire.appendVarintField(1, privateAppPort, to: &dataMsg)
        ProtoWire.appendBytesField(2, payload, to: &dataMsg)

        var meshPacket = Data()
        ProtoWire.appendFixed32Field(2, broadcastNode, to: &meshPacket)
        ProtoWire.appendBytesField(4, dataMsg, to: &meshPacket)
        ProtoWire.appendFixed32Field(6, packetID, to: &meshPacket)
        ProtoWire.appendVarintField(9, hopLimit, to: &meshPacket)

        var toRadio = Data()
        ProtoWire.appendBytesField(1, meshPacket, to: &toRadio)
        return toRadio
    }

    /// What Meshline cares about in one FromRadio message.
    enum FromRadio: Equatable {
        /// A decoded PRIVATE_APP packet from another node.
        case privateApp(from: UInt32, payload: Data)
        /// FromRadio.my_info (3) -> MyNodeInfo.my_node_num (1).
        case myNodeNum(UInt32)
        /// FromRadio.config_complete_id (7).
        case configComplete(UInt32)
        /// Anything else (node db, config, other ports, encrypted packets).
        case other
    }

    static func decodeFromRadio(_ data: Data) -> FromRadio? {
        guard let fields = ProtoWire.parse(data) else { return nil }
        for field in fields {
            switch (field.number, field.value) {
            case (2, .bytes(let packetBytes)):
                return decodeMeshPacket(packetBytes) ?? .other
            case (3, .bytes(let infoBytes)):
                guard let info = ProtoWire.parse(infoBytes) else { return .other }
                for f in info {
                    if f.number == 1, case .varint(let num) = f.value {
                        return .myNodeNum(UInt32(truncatingIfNeeded: num))
                    }
                }
                return .other
            case (7, .varint(let id)):
                return .configComplete(UInt32(truncatingIfNeeded: id))
            default:
                continue
            }
        }
        return .other
    }

    private static func decodeMeshPacket(_ data: Data) -> FromRadio? {
        guard let fields = ProtoWire.parse(data) else { return nil }
        var from: UInt32?
        var decoded: Data?
        for field in fields {
            switch (field.number, field.value) {
            case (1, .fixed32(let v)): from = v
            case (4, .bytes(let d)): decoded = d
            default: continue
            }
        }
        guard let from, let decoded, let dataFields = ProtoWire.parse(decoded) else { return nil }
        var port: UInt64?
        var payload: Data?
        for field in dataFields {
            switch (field.number, field.value) {
            case (1, .varint(let p)): port = p
            case (2, .bytes(let p)): payload = p
            default: continue
            }
        }
        guard port == privateAppPort, let payload else { return nil }
        return .privateApp(from: from, payload: payload)
    }
}

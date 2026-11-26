import Foundation
import Compression

enum Zlib {
    static let maxTextLength = 16000000
    static let maxJSONLength = 12000000
    private static func adler(_ bytes: [UInt8]) -> UInt32 {
        var a: UInt32 = 1, b: UInt32 = 0
        for v in bytes { a = (a + UInt32(v)) % 65521; b = (b + a) % 65521 }
        return (b << 16) | a
    }
    static func pack(_ data: Data) -> Data? {
        guard !data.isEmpty, data.count <= maxJSONLength else { return nil }
        let source = [UInt8](data)
        var destination = [UInt8](repeating: 0, count: maxJSONLength + 512)
        let capacity = destination.count
        let count = source.withUnsafeBufferPointer { src in
            destination.withUnsafeMutableBufferPointer { dst in
                compression_encode_buffer(dst.baseAddress!, capacity, src.baseAddress!, source.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard count > 0 else { return nil }
        let check = adler(source)
        return Data([0x78, 0x9c] + Array(destination.prefix(count)) + [UInt8((check >> 24) & 255), UInt8((check >> 16) & 255), UInt8((check >> 8) & 255), UInt8(check & 255)])
    }
    static func unpack(_ data: Data) -> Data? {
        let bytes = [UInt8](data)
        guard bytes.count >= 7, bytes.count <= maxTextLength, bytes[0] & 15 == 8,
              bytes[0] >> 4 <= 7, (Int(bytes[0]) * 256 + Int(bytes[1])) % 31 == 0, bytes[1] & 32 == 0 else { return nil }
        let source = Array(bytes[2..<(bytes.count - 4)])
        var destination = [UInt8](repeating: 0, count: maxJSONLength + 1)
        let capacity = destination.count
        let count = source.withUnsafeBufferPointer { src in
            destination.withUnsafeMutableBufferPointer { dst in
                compression_decode_buffer(dst.baseAddress!, capacity, src.baseAddress!, source.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard count > 0, count <= maxJSONLength else { return nil }
        let json = Array(destination.prefix(count)), tail = Array(bytes.suffix(4))
        let check = tail.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard adler(json) == check else { return nil }
        return Data(json)
    }
}

import CCryptoBridge
import Foundation

public enum RelayCompressionError: Error, Equatable {
    case inputTooLarge
    case outputTooLarge
    case compressionFailed
    case decompressionFailed
}

public enum RelayCompression {
    public static let maxSectionBytes = 128 * 1_024

    public static func zlibCompress(_ data: Data, maxInputBytes: Int = maxSectionBytes) throws -> Data {
        guard data.count <= maxInputBytes else { throw RelayCompressionError.inputTooLarge }
        if data.isEmpty { return Data() }
        let capacity = Int(cc_zlib_compress_bound(data.count))
        var output = Data(count: capacity)
        var outputLength = capacity
        let status = output.withUnsafeMutableBytes { destination in
            data.withUnsafeBytes { source in
                cc_zlib_compress(
                    source.bindMemory(to: UInt8.self).baseAddress!,
                    data.count,
                    destination.bindMemory(to: UInt8.self).baseAddress!,
                    &outputLength,
                    9
                )
            }
        }
        guard status == 0 else { throw RelayCompressionError.compressionFailed }
        output.count = outputLength
        return output
    }

    public static func zlibDecompress(_ data: Data, maxOutputBytes: Int = maxSectionBytes) throws -> Data {
        guard maxOutputBytes > 0 else { throw RelayCompressionError.outputTooLarge }
        if data.isEmpty { return Data() }
        var capacity = min(max(data.count * 4, 2_048), maxOutputBytes)
        while capacity <= maxOutputBytes {
            var output = Data(count: capacity)
            var outputLength = capacity
            let status = output.withUnsafeMutableBytes { destination in
                data.withUnsafeBytes { source in
                    cc_zlib_decompress(
                        source.bindMemory(to: UInt8.self).baseAddress!,
                        data.count,
                        destination.bindMemory(to: UInt8.self).baseAddress!,
                        &outputLength
                    )
                }
            }
            if status == 0 {
                output.count = outputLength
                return output
            }
            if status != -5 { throw RelayCompressionError.decompressionFailed }
            if capacity == maxOutputBytes { break }
            capacity = min(capacity * 2, maxOutputBytes)
        }
        throw RelayCompressionError.outputTooLarge
    }
}

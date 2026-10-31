import CoreFoundation
import Foundation

/// Pure preview of repairing legacy tag encodings, with no draft or persistence dependency.
enum TagEncodingRepair {
    /// Reinterprets recoverable legacy bytes while preserving values that cannot be decoded.
    static func preview(_ values: [String], encodingName: String) -> [String] {

        let encoding: String.Encoding =
            encodingName == "Shift-JIS"
            ? .shiftJIS
            : encodingName == "UTF-8"
                ? .utf8
                : String.Encoding(
                    rawValue: CFStringConvertEncodingToNSStringEncoding(
                        CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
                    )
                )
        return
            values
            .map { value in
                guard
                    let bytes = value.data(using: .isoLatin1) ?? value.data(using: .windowsCP1252),
                    let text = String(data: bytes, encoding: encoding), !text.contains("\u{fffd}")
                else { return value }
                return text
            }

    }
}

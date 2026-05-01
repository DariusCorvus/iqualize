import AppKit

extension NSColor {
    /// Returns "#RRGGBB" by converting to sRGB first; nil if conversion fails.
    var srgbHexRGB: String? {
        guard let c = usingColorSpace(.sRGB) else { return nil }
        let r = Int(round(c.redComponent * 255))
        let g = Int(round(c.greenComponent * 255))
        let b = Int(round(c.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    /// Parses "#RRGGBB" or "RRGGBB" into an sRGB NSColor; nil if malformed.
    convenience init?(srgbHexRGB: String) {
        var s = srgbHexRGB.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        let r = CGFloat((v >> 16) & 0xFF) / 255.0
        let g = CGFloat((v >> 8) & 0xFF) / 255.0
        let b = CGFloat(v & 0xFF) / 255.0
        self.init(srgbRed: r, green: g, blue: b, alpha: 1.0)
    }
}

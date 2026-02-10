import Foundation
import AppKit
import LookinShared

/// Formats detailed view attributes into human-readable text.
enum ViewDetailFormatter {

    static func format(_ detail: LookinDisplayItemDetail) -> String {
        var sections: [String] = []

        sections.append("=== View Detail (oid: \(detail.displayItemOid)) ===")

        if let frameValue = detail.frameValue {
            let frame = frameValue.rectValue
            sections.append("Frame: (\(Int(frame.origin.x)), \(Int(frame.origin.y)), \(Int(frame.size.width)), \(Int(frame.size.height)))")
        }
        if let boundsValue = detail.boundsValue {
            let bounds = boundsValue.rectValue
            sections.append("Bounds: (\(Int(bounds.origin.x)), \(Int(bounds.origin.y)), \(Int(bounds.size.width)), \(Int(bounds.size.height)))")
        }
        if let hiddenValue = detail.hiddenValue {
            sections.append("Hidden: \(hiddenValue.boolValue)")
        }
        if let alphaValue = detail.alphaValue {
            sections.append("Alpha: \(String(format: "%.2f", alphaValue.doubleValue))")
        }
        if let title = detail.customDisplayTitle, !title.isEmpty {
            sections.append("Custom Title: \(title)")
        }

        if let groups = detail.attributesGroupList, !groups.isEmpty {
            sections.append("")
            sections.append("--- Attributes ---")
            for group in groups {
                sections.append(formatGroup(group))
            }
        }

        if let customGroups = detail.customAttrGroupList, !customGroups.isEmpty {
            sections.append("")
            sections.append("--- Custom Attributes ---")
            for group in customGroups {
                sections.append(formatGroup(group))
            }
        }

        return sections.joined(separator: "\n")
    }

    static func formatGroups(_ groups: [LookinAttributesGroup]) -> String {
        if groups.isEmpty {
            return "(no attribute groups)"
        }
        return groups.map { formatGroup($0) }.joined(separator: "\n\n")
    }

    // MARK: - Private

    private static func formatGroup(_ group: LookinAttributesGroup) -> String {
        let groupTitle = group.userCustomTitle ?? group.identifier ?? "Unknown Group"
        var lines = ["[\(groupTitle)]"]

        guard let attrSections = group.attrSections else { return lines.joined(separator: "\n") }

        for section in attrSections {
            let sectionTitle = section.identifier ?? ""
            if !sectionTitle.isEmpty {
                lines.append("  \(sectionTitle):")
            }

            guard let attributes = section.attributes else { continue }
            for attr in attributes {
                lines.append("    \(formatAttribute(attr))")
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func formatAttribute(_ attr: LookinAttribute) -> String {
        let name = attr.displayTitle ?? attr.identifier ?? "?"
        let valueStr = formatValue(attr.value, type: attr.attrType)
        return "\(name): \(valueStr)"
    }

    private static func formatValue(_ value: Any?, type: LookinAttrType) -> String {
        guard let value = value else { return "(nil)" }

        switch type {
        case .none, .void:
            return "(void)"

        case .BOOL:
            if let num = value as? NSNumber {
                return num.boolValue ? "YES" : "NO"
            }
            return "\(value)"

        case .char, .int, .short, .long, .longLong,
             .unsignedChar, .unsignedInt, .unsignedShort, .unsignedLong, .unsignedLongLong:
            if let num = value as? NSNumber {
                return "\(num.intValue)"
            }
            return "\(value)"

        case .float, .double:
            if let num = value as? NSNumber {
                return String(format: "%.2f", num.doubleValue)
            }
            return "\(value)"

        case .sel:
            return "\(value)"

        case .class:
            return "\(value)"

        case .cgPoint:
            if let val = value as? NSValue {
                let pt = val.pointValue
                return "(\(pt.x), \(pt.y))"
            }
            return "\(value)"

        case .cgVector:
            return "\(value)"

        case .cgSize:
            if let val = value as? NSValue {
                let sz = val.sizeValue
                return "(\(sz.width), \(sz.height))"
            }
            return "\(value)"

        case .cgRect:
            if let val = value as? NSValue {
                let r = val.rectValue
                return "(\(r.origin.x), \(r.origin.y), \(r.size.width), \(r.size.height))"
            }
            return "\(value)"

        case .cgAffineTransform:
            return "\(value)"

        case .uiEdgeInsets:
            return "\(value)"

        case .uiOffset:
            return "\(value)"

        case .nsString:
            if let str = value as? String {
                return "\"\(str)\""
            }
            return "\(value)"

        case .enumInt, .enumLong:
            if let num = value as? NSNumber {
                return "\(num.intValue)"
            }
            return "\(value)"

        case .uiColor:
            // Value is an array: [@(r), @(g), @(b), @(a)] range 0~1
            if let arr = value as? [NSNumber], arr.count >= 4 {
                let r = Int(arr[0].doubleValue * 255)
                let g = Int(arr[1].doubleValue * 255)
                let b = Int(arr[2].doubleValue * 255)
                let a = arr[3].doubleValue
                if a < 1.0 {
                    return "rgba(\(r),\(g),\(b),\(String(format: "%.2f", a)))"
                } else {
                    return "#\(String(format: "%02X%02X%02X", r, g, b))"
                }
            }
            return "\(value)"

        case .customObj:
            return "\(value)"

        case .enumString:
            return "\(value)"

        case .shadow:
            return "\(value)"

        case .json:
            if let str = value as? String {
                return str
            }
            return "\(value)"

        @unknown default:
            return "\(value)"
        }
    }
}

import Foundation
import LookinShared

/// Formats a LookinHierarchyInfo into a human-readable indented text tree.
enum HierarchyFormatter {

    static func format(_ hierarchy: LookinHierarchyInfo) -> String {
        guard let items = hierarchy.displayItems, !items.isEmpty else {
            return "(empty hierarchy)"
        }
        var lines: [String] = []
        for item in items {
            formatItem(item, depth: 0, prefix: "", isLast: true, lines: &lines)
        }
        return lines.joined(separator: "\n")
    }

    /// Search the hierarchy for nodes whose class name or VC name contains `query` (case-insensitive).
    /// Returns a flat, numbered list so the AI can pick from the results without token-heavy subtrees.
    static func searchFlat(_ hierarchy: LookinHierarchyInfo, query: String) -> String {
        guard let items = hierarchy.displayItems, !items.isEmpty else {
            return "(empty hierarchy)"
        }
        let q = query.lowercased()
        var matches: [(className: String, oid: UInt, frame: NSRect, vcName: String?)] = []
        for item in items {
            collectAllMatches(item, query: q, results: &matches)
        }
        if matches.isEmpty {
            return "No views found matching \"\(query)\"."
        }
        var lines: [String] = []
        lines.append("Found \(matches.count) match(es) for \"\(query)\":")
        for (i, m) in matches.enumerated() {
            let f = m.frame
            let frameStr = "(\(Int(f.origin.x)),\(Int(f.origin.y)),\(Int(f.size.width)),\(Int(f.size.height)))"
            var line = "\(i + 1). \(m.className) \(frameStr) oid:\(m.oid)"
            if let vc = m.vcName {
                line += " vc=\(vc)"
            }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }

    /// Find the node with the given OID and format it + its full subtree.
    static func formatNodeSubtree(_ hierarchy: LookinHierarchyInfo, oid: UInt) -> String? {
        guard let item = findItem(in: hierarchy, viewOid: oid) else {
            return nil
        }
        var lines: [String] = []
        formatItem(item, depth: 0, prefix: "", isLast: true, lines: &lines)
        return lines.joined(separator: "\n")
    }

    static func findItem(in hierarchy: LookinHierarchyInfo, viewOid: UInt) -> LookinDisplayItem? {
        guard let items = hierarchy.displayItems else { return nil }
        for item in items {
            if let found = findItemRecursive(item, viewOid: viewOid) {
                return found
            }
        }
        return nil
    }

    // MARK: - Private

    private static func collectAllMatches(
        _ item: LookinDisplayItem,
        query: String,
        results: inout [(className: String, oid: UInt, frame: NSRect, vcName: String?)]
    ) {
        let className = item.viewObject?.classChainList?.first
            ?? item.layerObject?.classChainList?.first
            ?? "Unknown"
        let vcName = item.hostViewControllerObject?.classChainList?.first

        if className.lowercased().contains(query) || (vcName?.lowercased().contains(query) ?? false) {
            let oid = item.viewObject?.oid ?? item.layerObject?.oid ?? 0
            results.append((className: className, oid: oid, frame: item.frame, vcName: vcName))
        }
        // Always recurse — a child might also match independently
        for child in item.subitems ?? [] {
            collectAllMatches(child, query: query, results: &results)
        }
    }

    private static func findItemRecursive(_ item: LookinDisplayItem, viewOid: UInt) -> LookinDisplayItem? {
        let itemOid = item.viewObject?.oid ?? item.layerObject?.oid ?? 0
        if itemOid == viewOid {
            return item
        }
        for child in item.subitems ?? [] {
            if let found = findItemRecursive(child, viewOid: viewOid) {
                return found
            }
        }
        return nil
    }

    private static func formatItem(
        _ item: LookinDisplayItem,
        depth: Int,
        prefix: String,
        isLast: Bool,
        lines: inout [String]
    ) {
        let connector: String
        if depth == 0 {
            connector = ""
        } else {
            connector = isLast ? "└─ " : "├─ "
        }

        let className = item.viewObject?.classChainList?.first
            ?? item.layerObject?.classChainList?.first
            ?? "Unknown"

        let frame = item.frame
        let frameStr = "(\(Int(frame.origin.x)),\(Int(frame.origin.y)),\(Int(frame.size.width)),\(Int(frame.size.height)))"

        let oid = item.viewObject?.oid ?? item.layerObject?.oid ?? 0

        var flags: [String] = []
        if item.isHidden { flags.append("hidden") }
        if item.alpha < 1.0 { flags.append("alpha=\(String(format: "%.2f", item.alpha))") }
        if item.representedAsKeyWindow { flags.append("keyWindow") }

        var vcStr = ""
        if let vc = item.hostViewControllerObject, let vcClass = vc.classChainList?.first {
            vcStr = " vc=\(vcClass)"
        }

        var titleStr = ""
        if let customTitle = item.customDisplayTitle, !customTitle.isEmpty {
            titleStr = " \"\(customTitle)\""
        }

        let flagStr = flags.isEmpty ? "" : " [\(flags.joined(separator: ", "))]"
        let line = "\(prefix)\(connector)\(className) \(frameStr) oid:\(oid)\(vcStr)\(titleStr)\(flagStr)"
        lines.append(line)

        let subitems = item.subitems ?? []
        let childPrefix: String
        if depth == 0 {
            childPrefix = ""
        } else {
            childPrefix = prefix + (isLast ? "   " : "│  ")
        }

        for (index, child) in subitems.enumerated() {
            let childIsLast = (index == subitems.count - 1)
            formatItem(child, depth: depth + 1, prefix: childPrefix, isLast: childIsLast, lines: &lines)
        }
    }
}

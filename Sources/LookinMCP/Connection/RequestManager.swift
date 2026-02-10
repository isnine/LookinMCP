import Foundation
import AppKit
import LookinShared

/// Handles encoding requests and decoding responses using NSKeyedArchiver/NSKeyedUnarchiver.
struct LookinCodec {

    static let requestTypePing: UInt32 = 200
    static let requestTypeApp: UInt32 = 201
    static let requestTypeHierarchy: UInt32 = 202
    static let requestTypeHierarchyDetails: UInt32 = 203
    static let requestTypeInbuiltAttrModification: UInt32 = 204
    static let requestTypeAttrModificationPatch: UInt32 = 205
    static let requestTypeInvokeMethod: UInt32 = 206
    static let requestTypeFetchObject: UInt32 = 207
    static let requestTypeAllAttrGroups: UInt32 = 210
    static let requestTypeAllSelectorNames: UInt32 = 213

    static func encodeAttachment(_ attachment: LookinConnectionAttachment) throws -> Data {
        return try NSKeyedArchiver.archivedData(withRootObject: attachment, requiringSecureCoding: true)
    }

    static func encodeDictionary(_ dict: NSDictionary) throws -> Data {
        return try NSKeyedArchiver.archivedData(withRootObject: dict, requiringSecureCoding: true)
    }

    static func decodeResponseAttachment(from data: Data) throws -> LookinConnectionResponseAttachment {
        let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
        unarchiver.requiresSecureCoding = false

        // LookinServer runs on iOS so it archives UIImage/UIColor, but we're
        // on macOS where those classes don't exist. Map them to AppKit types.
        NSKeyedUnarchiver.setClass(NSImage.self, forClassName: "UIImage")
        NSKeyedUnarchiver.setClass(NSColor.self, forClassName: "UIColor")
        unarchiver.setClass(NSImage.self, forClassName: "UIImage")
        unarchiver.setClass(NSColor.self, forClassName: "UIColor")

        guard let attachment = unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey) as? LookinConnectionResponseAttachment else {
            throw LookinConnection.ConnectionError.invalidFrame
        }
        unarchiver.finishDecoding()
        return attachment
    }

    static func decodeObject(from data: Data) throws -> Any? {
        let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
        unarchiver.requiresSecureCoding = false
        let obj = unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey)
        unarchiver.finishDecoding()
        return obj
    }
}

// MARK: - Attribute Mapping

/// Describes how to modify a single attribute via the LookinServer protocol.
struct AttributeMapping {
    /// Friendly name used by MCP clients (e.g. "hidden", "alpha", "text").
    let name: String
    /// The LookinAttrIdentifier string (e.g. "vl_v_h").
    let attrIdentifier: String
    /// The Objective-C setter selector string (e.g. "setHidden:").
    let setter: String
    /// How the server should interpret the value.
    let attrType: Int  // LookinAttrType raw value
    /// If true, target is the view OID; if false, target is the layer OID.
    let isViewProperty: Bool
    /// Whether modification requires a patch (re-fetch of screenshots/positions).
    let needsPatch: Bool
    /// Human-readable description of expected value format.
    let valueDescription: String
}

/// Central registry of modifiable attributes, keyed by friendly name.
enum AttributeRegistry {
    static let mappings: [String: AttributeMapping] = {
        var m: [String: AttributeMapping] = [:]
        for mapping in allMappings {
            m[mapping.name] = mapping
        }
        return m
    }()

    // LookinAttrType raw values we need
    private static let typeBOOL   = 14  // LookinAttrTypeBOOL
    private static let typeFloat  = 12  // LookinAttrTypeFloat
    private static let typeInt    = 3   // LookinAttrTypeInt
    private static let typeLong   = 5   // LookinAttrTypeLong
    private static let typeDouble = 13  // LookinAttrTypeDouble
    private static let typeCGRect = 20  // LookinAttrTypeCGRect
    private static let typeCGPoint = 17 // LookinAttrTypeCGPoint
    private static let typeCGSize = 19  // LookinAttrTypeCGSize
    private static let typeString = 23  // LookinAttrTypeNSString
    private static let typeColor  = 27  // LookinAttrTypeUIColor
    private static let typeEnumInt = 24 // LookinAttrTypeEnumInt
    private static let typeEnumLong = 25 // LookinAttrTypeEnumLong
    private static let typeEdgeInsets = 22 // LookinAttrTypeUIEdgeInsets

    private static let allMappings: [AttributeMapping] = [
        // --- Layout (CALayer) ---
        .init(name: "frame", attrIdentifier: "la_f_f", setter: "setFrame:", attrType: typeCGRect, isViewProperty: false, needsPatch: true, valueDescription: "CGRect as 'x,y,w,h' e.g. '10,20,100,50'"),
        .init(name: "bounds", attrIdentifier: "la_b_b", setter: "setBounds:", attrType: typeCGRect, isViewProperty: false, needsPatch: true, valueDescription: "CGRect as 'x,y,w,h'"),
        .init(name: "position", attrIdentifier: "la_p_p", setter: "setPosition:", attrType: typeCGPoint, isViewProperty: false, needsPatch: true, valueDescription: "CGPoint as 'x,y'"),
        .init(name: "anchorPoint", attrIdentifier: "la_a_a", setter: "setAnchorPoint:", attrType: typeCGPoint, isViewProperty: false, needsPatch: true, valueDescription: "CGPoint as 'x,y' e.g. '0.5,0.5'"),

        // --- Visibility (CALayer) ---
        .init(name: "hidden", attrIdentifier: "vl_v_h", setter: "setHidden:", attrType: typeBOOL, isViewProperty: false, needsPatch: true, valueDescription: "Boolean: 'true' or 'false'"),
        .init(name: "alpha", attrIdentifier: "vl_v_o", setter: "setOpacity:", attrType: typeFloat, isViewProperty: false, needsPatch: true, valueDescription: "Float 0.0-1.0"),
        .init(name: "opacity", attrIdentifier: "vl_v_o", setter: "setOpacity:", attrType: typeFloat, isViewProperty: false, needsPatch: true, valueDescription: "Float 0.0-1.0"),

        // --- Interaction (UIView) ---
        .init(name: "userInteractionEnabled", attrIdentifier: "vl_i_i", setter: "setUserInteractionEnabled:", attrType: typeBOOL, isViewProperty: true, needsPatch: false, valueDescription: "Boolean: 'true' or 'false'"),

        // --- Masks (CALayer) ---
        .init(name: "masksToBounds", attrIdentifier: "vl_i_m", setter: "setMasksToBounds:", attrType: typeBOOL, isViewProperty: false, needsPatch: true, valueDescription: "Boolean: 'true' or 'false'"),
        .init(name: "clipsToBounds", attrIdentifier: "vl_i_m", setter: "setMasksToBounds:", attrType: typeBOOL, isViewProperty: false, needsPatch: true, valueDescription: "Boolean: 'true' or 'false'"),

        // --- Corner (CALayer) ---
        .init(name: "cornerRadius", attrIdentifier: "vl_co_r", setter: "setCornerRadius:", attrType: typeFloat, isViewProperty: false, needsPatch: true, valueDescription: "Float e.g. '8.0'"),

        // --- Background (CALayer) ---
        .init(name: "backgroundColor", attrIdentifier: "vl_b_b", setter: "setLks_backgroundColor:", attrType: typeColor, isViewProperty: false, needsPatch: true, valueDescription: "Color as 'r,g,b,a' (0-1) or hex '#RRGGBB' or '#RRGGBBAA'"),

        // --- Border (CALayer) ---
        .init(name: "borderColor", attrIdentifier: "vl_bo_c", setter: "setLks_borderColor:", attrType: typeColor, isViewProperty: false, needsPatch: true, valueDescription: "Color as 'r,g,b,a' or hex '#RRGGBB'"),
        .init(name: "borderWidth", attrIdentifier: "vl_bo_w", setter: "setBorderWidth:", attrType: typeFloat, isViewProperty: false, needsPatch: true, valueDescription: "Float e.g. '1.0'"),

        // --- Shadow (CALayer) ---
        .init(name: "shadowColor", attrIdentifier: "vl_s_c", setter: "setLks_shadowColor:", attrType: typeColor, isViewProperty: false, needsPatch: true, valueDescription: "Color as 'r,g,b,a' or hex '#RRGGBB'"),
        .init(name: "shadowOpacity", attrIdentifier: "vl_s_o", setter: "setShadowOpacity:", attrType: typeFloat, isViewProperty: false, needsPatch: true, valueDescription: "Float 0.0-1.0"),
        .init(name: "shadowRadius", attrIdentifier: "vl_s_r", setter: "setShadowRadius:", attrType: typeFloat, isViewProperty: false, needsPatch: true, valueDescription: "Float e.g. '4.0'"),
        .init(name: "shadowOffsetWidth", attrIdentifier: "vl_s_ow", setter: "setLks_shadowOffsetWidth:", attrType: typeFloat, isViewProperty: false, needsPatch: true, valueDescription: "Float"),
        .init(name: "shadowOffsetHeight", attrIdentifier: "vl_s_oh", setter: "setLks_shadowOffsetHeight:", attrType: typeFloat, isViewProperty: false, needsPatch: true, valueDescription: "Float"),

        // --- Content mode (UIView) ---
        .init(name: "contentMode", attrIdentifier: "vl_cm_m", setter: "setContentMode:", attrType: typeEnumInt, isViewProperty: true, needsPatch: true, valueDescription: "Integer 0-12: 0=scaleToFill, 1=scaleAspectFit, 2=scaleAspectFill, 3=redraw, 4=center, 5=top, 6=bottom, 7=left, 8=right, 9=topLeft, 10=topRight, 11=bottomLeft, 12=bottomRight"),

        // --- Tint (UIView) ---
        .init(name: "tintColor", attrIdentifier: "vl_tc_c", setter: "setTintColor:", attrType: typeColor, isViewProperty: true, needsPatch: true, valueDescription: "Color as 'r,g,b,a' or hex '#RRGGBB'"),

        // --- Tag (UIView) ---
        .init(name: "tag", attrIdentifier: "vl_t_t", setter: "setTag:", attrType: typeLong, isViewProperty: true, needsPatch: false, valueDescription: "Integer"),

        // --- UILabel ---
        .init(name: "text", attrIdentifier: "lb_t_t", setter: "setText:", attrType: typeString, isViewProperty: true, needsPatch: true, valueDescription: "String"),
        .init(name: "numberOfLines", attrIdentifier: "lb_n_n", setter: "setNumberOfLines:", attrType: typeLong, isViewProperty: true, needsPatch: true, valueDescription: "Integer (0 = unlimited)"),
        .init(name: "fontSize", attrIdentifier: "lb_f_s", setter: "setLks_fontSize:", attrType: typeFloat, isViewProperty: true, needsPatch: true, valueDescription: "Float e.g. '17.0'"),
        .init(name: "textColor", attrIdentifier: "lb_tc_c", setter: "setTextColor:", attrType: typeColor, isViewProperty: true, needsPatch: true, valueDescription: "Color as 'r,g,b,a' or hex '#RRGGBB'"),
        .init(name: "textAlignment", attrIdentifier: "lb_a_a", setter: "setTextAlignment:", attrType: typeEnumInt, isViewProperty: true, needsPatch: true, valueDescription: "Integer: 0=left, 1=center, 2=right, 3=justified, 4=natural"),

        // --- UITextField ---
        .init(name: "textFieldText", attrIdentifier: "tf_t_t", setter: "setText:", attrType: typeString, isViewProperty: true, needsPatch: true, valueDescription: "String"),
        .init(name: "placeholder", attrIdentifier: "tf_p_p", setter: "setPlaceholder:", attrType: typeString, isViewProperty: true, needsPatch: true, valueDescription: "String"),

        // --- UITextView ---
        .init(name: "textViewText", attrIdentifier: "te_t_t", setter: "setText:", attrType: typeString, isViewProperty: true, needsPatch: true, valueDescription: "String"),

        // --- UIControl ---
        .init(name: "enabled", attrIdentifier: "ct_es_e", setter: "setEnabled:", attrType: typeBOOL, isViewProperty: true, needsPatch: false, valueDescription: "Boolean: 'true' or 'false'"),
        .init(name: "selected", attrIdentifier: "ct_es_s", setter: "setSelected:", attrType: typeBOOL, isViewProperty: true, needsPatch: true, valueDescription: "Boolean: 'true' or 'false'"),

        // --- UIStackView ---
        .init(name: "stackAxis", attrIdentifier: "sv_a_a", setter: "setAxis:", attrType: typeEnumInt, isViewProperty: true, needsPatch: true, valueDescription: "Integer: 0=horizontal, 1=vertical"),
        .init(name: "stackDistribution", attrIdentifier: "sv_d_d", setter: "setDistribution:", attrType: typeEnumInt, isViewProperty: true, needsPatch: true, valueDescription: "Integer: 0=fill, 1=fillEqually, 2=fillProportionally, 3=equalSpacing, 4=equalCentering"),
        .init(name: "stackAlignment", attrIdentifier: "sv_al_a", setter: "setAlignment:", attrType: typeEnumInt, isViewProperty: true, needsPatch: true, valueDescription: "Integer: 0=fill, 1=leading, 2=firstBaseline, 3=center, 4=trailing, 5=lastBaseline"),
        .init(name: "stackSpacing", attrIdentifier: "sv_s_s", setter: "setSpacing:", attrType: typeFloat, isViewProperty: true, needsPatch: true, valueDescription: "Float e.g. '8.0'"),

        // --- UIScrollView ---
        .init(name: "contentOffset", attrIdentifier: "sc_o_o", setter: "setContentOffset:", attrType: typeCGPoint, isViewProperty: true, needsPatch: true, valueDescription: "CGPoint as 'x,y'"),
        .init(name: "contentSize", attrIdentifier: "sc_cs_s", setter: "setContentSize:", attrType: typeCGSize, isViewProperty: true, needsPatch: true, valueDescription: "CGSize as 'w,h'"),
        .init(name: "contentInset", attrIdentifier: "sc_ci_i", setter: "setContentInset:", attrType: typeEdgeInsets, isViewProperty: true, needsPatch: true, valueDescription: "UIEdgeInsets as 'top,left,bottom,right'"),
    ]

    /// Parse a string value into the appropriate NSObject for the wire protocol.
    static func parseValue(_ str: String, attrType: Int) throws -> Any {
        switch attrType {
        case typeBOOL:
            let lower = str.lowercased().trimmingCharacters(in: .whitespaces)
            switch lower {
            case "true", "yes", "1": return NSNumber(value: true)
            case "false", "no", "0": return NSNumber(value: false)
            default: throw ParseError.invalidValue("Expected boolean (true/false), got '\(str)'")
            }

        case typeInt, typeLong, typeEnumInt, typeEnumLong:
            guard let val = Int(str.trimmingCharacters(in: .whitespaces)) else {
                throw ParseError.invalidValue("Expected integer, got '\(str)'")
            }
            return NSNumber(value: val)

        case typeFloat:
            guard let val = Float(str.trimmingCharacters(in: .whitespaces)) else {
                throw ParseError.invalidValue("Expected float, got '\(str)'")
            }
            return NSNumber(value: val)

        case typeDouble:
            guard let val = Double(str.trimmingCharacters(in: .whitespaces)) else {
                throw ParseError.invalidValue("Expected double, got '\(str)'")
            }
            return NSNumber(value: val)

        case typeString:
            return str as NSString

        case typeColor:
            return try parseColor(str) as NSArray

        case typeCGRect:
            let parts = str.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard parts.count == 4 else {
                throw ParseError.invalidValue("Expected CGRect as 'x,y,w,h', got '\(str)'")
            }
            return NSValue(rect: NSRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3]))

        case typeCGPoint:
            let parts = str.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard parts.count == 2 else {
                throw ParseError.invalidValue("Expected CGPoint as 'x,y', got '\(str)'")
            }
            return NSValue(point: NSPoint(x: parts[0], y: parts[1]))

        case typeCGSize:
            let parts = str.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard parts.count == 2 else {
                throw ParseError.invalidValue("Expected CGSize as 'w,h', got '\(str)'")
            }
            return NSValue(size: NSSize(width: parts[0], height: parts[1]))

        case typeEdgeInsets:
            let parts = str.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard parts.count == 4 else {
                throw ParseError.invalidValue("Expected UIEdgeInsets as 'top,left,bottom,right', got '\(str)'")
            }
            return NSValue(edgeInsets: NSEdgeInsets(top: parts[0], left: parts[1], bottom: parts[2], right: parts[3]))

        default:
            throw ParseError.invalidValue("Unsupported attrType \(attrType) for value '\(str)'")
        }
    }

    /// Parse a color string. Supports:
    /// - RGBA floats: "r,g,b,a" (0-1 range)
    /// - Hex: "#RRGGBB" or "#RRGGBBAA"
    private static func parseColor(_ str: String) throws -> [NSNumber] {
        let trimmed = str.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("#") {
            return try parseHexColor(trimmed)
        }
        // Try comma-separated RGBA
        let parts = trimmed.split(separator: ",").compactMap { Float($0.trimmingCharacters(in: .whitespaces)) }
        if parts.count == 4 {
            return parts.map { NSNumber(value: $0) }
        }
        if parts.count == 3 {
            return parts.map { NSNumber(value: $0) } + [NSNumber(value: 1.0)]
        }
        throw ParseError.invalidValue("Expected color as 'r,g,b,a' (0-1) or '#RRGGBB', got '\(str)'")
    }

    private static func parseHexColor(_ hex: String) throws -> [NSNumber] {
        var hexStr = hex
        if hexStr.hasPrefix("#") { hexStr = String(hexStr.dropFirst()) }
        guard hexStr.count == 6 || hexStr.count == 8 else {
            throw ParseError.invalidValue("Hex color must be 6 or 8 hex digits, got '\(hex)'")
        }
        let scanner = Scanner(string: hexStr)
        var value: UInt64 = 0
        guard scanner.scanHexInt64(&value) else {
            throw ParseError.invalidValue("Invalid hex color '\(hex)'")
        }
        if hexStr.count == 6 {
            let r = Float((value >> 16) & 0xFF) / 255.0
            let g = Float((value >> 8) & 0xFF) / 255.0
            let b = Float(value & 0xFF) / 255.0
            return [NSNumber(value: r), NSNumber(value: g), NSNumber(value: b), NSNumber(value: 1.0)]
        } else {
            let r = Float((value >> 24) & 0xFF) / 255.0
            let g = Float((value >> 16) & 0xFF) / 255.0
            let b = Float((value >> 8) & 0xFF) / 255.0
            let a = Float(value & 0xFF) / 255.0
            return [NSNumber(value: r), NSNumber(value: g), NSNumber(value: b), NSNumber(value: a)]
        }
    }

    enum ParseError: LocalizedError {
        case invalidValue(String)
        var errorDescription: String? {
            switch self {
            case .invalidValue(let msg): return msg
            }
        }
    }

    /// Lists all available attribute names grouped for display.
    static var availableAttributeNames: [String] {
        allMappings.map { $0.name }
    }

    /// Returns a help string describing all available attributes and their value formats.
    static var helpText: String {
        var lines: [String] = ["Available attributes:"]
        for m in allMappings {
            lines.append("  \(m.name): \(m.valueDescription)")
        }
        return lines.joined(separator: "\n")
    }
}

/// Manages sending typed requests and decoding responses via a LookinConnection.
final class RequestManager: @unchecked Sendable {

    private let connection: LookinConnection

    init(connection: LookinConnection) {
        self.connection = connection
    }

    func ping() async throws -> (alive: Bool, isInBackground: Bool) {
        let frame = try await connection.sendRequest(type: LookinCodec.requestTypePing, timeout: 5)
        guard let payload = frame.payload else {
            return (alive: true, isInBackground: false)
        }
        let attachment = try LookinCodec.decodeResponseAttachment(from: payload)
        return (alive: true, isInBackground: attachment.appIsInBackground)
    }

    func fetchAppInfo() async throws -> LookinAppInfo {
        // Server expects NSDictionary with "needImages" and "local" keys,
        // wrapped in a LookinConnectionAttachment.
        let params: NSDictionary = ["needImages": NSNumber(value: false), "local": NSArray()]
        let requestAttachment = LookinConnectionAttachment()
        requestAttachment.data = params
        let requestData = try LookinCodec.encodeAttachment(requestAttachment)

        let frame = try await connection.sendRequest(type: LookinCodec.requestTypeApp, payload: requestData, timeout: 10)
        guard let payload = frame.payload else {
            throw LookinConnection.ConnectionError.invalidFrame
        }
        let responseAttachment = try LookinCodec.decodeResponseAttachment(from: payload)
        if let error = responseAttachment.error {
            throw error
        }
        if let appInfo = responseAttachment.data as? LookinAppInfo {
            return appInfo
        }
        if let hierarchyInfo = responseAttachment.data as? LookinHierarchyInfo, let appInfo = hierarchyInfo.appInfo {
            return appInfo
        }
        let dataType = responseAttachment.data.map { String(describing: type(of: $0)) } ?? "nil"
        throw NSError(domain: "LookinMCP", code: -2, userInfo: [NSLocalizedDescriptionKey: "Unexpected data type for app info: \(dataType)"])
    }

    func fetchHierarchy() async throws -> LookinHierarchyInfo {
        let frame = try await connection.sendRequest(type: LookinCodec.requestTypeHierarchy, timeout: 15)
        guard let payload = frame.payload else {
            throw LookinConnection.ConnectionError.invalidFrame
        }
        let attachment = try LookinCodec.decodeResponseAttachment(from: payload)
        if let error = attachment.error {
            throw error
        }
        guard let hierarchy = attachment.data as? LookinHierarchyInfo else {
            throw LookinConnection.ConnectionError.invalidFrame
        }
        return hierarchy
    }

    func fetchAllAttrGroups(oid: UInt) async throws -> [LookinAttributesGroup] {
        let requestAttachment = LookinConnectionAttachment()
        requestAttachment.data = NSNumber(value: oid)
        let requestData = try LookinCodec.encodeAttachment(requestAttachment)

        let frame = try await connection.sendRequest(type: LookinCodec.requestTypeAllAttrGroups, payload: requestData, timeout: 15)
        guard let payload = frame.payload else {
            throw LookinConnection.ConnectionError.invalidFrame
        }
        let responseAttachment = try LookinCodec.decodeResponseAttachment(from: payload)
        if let error = responseAttachment.error {
            throw error
        }
        guard let groups = responseAttachment.data as? [LookinAttributesGroup] else {
            throw LookinConnection.ConnectionError.invalidFrame
        }
        return groups
    }

    /// Known attribute identifiers for text content.
    private static let textAttrIdentifiers: Set<String> = [
        "lb_t_t",   // LookinAttr_UILabel_Text_Text
        "tf_t_t",   // LookinAttr_UITextField_Text_Text
        "tf_p_p",   // LookinAttr_UITextField_Placeholder_Placeholder
        "te_t_t",   // LookinAttr_UITextView_Text_Text
    ]

    /// Extract text content from attribute groups by looking for known text attribute identifiers.
    private static func extractText(from groups: [LookinAttributesGroup]) -> String? {
        var texts: [String] = []
        for group in groups {
            for section in group.attrSections ?? [] {
                for attr in section.attributes ?? [] {
                    guard let identifier = attr.identifier,
                          textAttrIdentifiers.contains(identifier),
                          let str = attr.value as? String,
                          !str.isEmpty else { continue }
                    texts.append(str)
                }
            }
        }
        return texts.isEmpty ? nil : texts.joined(separator: " | ")
    }

    /// Fetch text content for multiple views concurrently.
    /// Returns a map from view OID to the combined text content string.
    /// Individual fetch failures are silently skipped.
    func fetchTextContentMap(for views: [(viewOid: UInt, layerOid: UInt)]) async -> [UInt: String] {
        guard !views.isEmpty else { return [:] }

        // Use TaskGroup for concurrent fetching with a concurrency limit via chunking.
        // Each request goes through a single TCP connection so we limit concurrency
        // to avoid overwhelming the connection.
        let maxConcurrency = 10
        var resultMap: [UInt: String] = [:]

        for chunkStart in stride(from: 0, to: views.count, by: maxConcurrency) {
            let chunkEnd = min(chunkStart + maxConcurrency, views.count)
            let chunk = Array(views[chunkStart..<chunkEnd])

            await withTaskGroup(of: (UInt, String?).self) { group in
                for view in chunk {
                    group.addTask {
                        do {
                            let groups = try await self.fetchAllAttrGroups(oid: view.layerOid)
                            let text = RequestManager.extractText(from: groups)
                            return (view.viewOid, text)
                        } catch {
                            return (view.viewOid, nil)
                        }
                    }
                }
                for await (viewOid, text) in group {
                    if let text = text {
                        resultMap[viewOid] = text
                    }
                }
            }
        }

        return resultMap
    }

    // MARK: - Attribute Modification (Type 204)

    /// Modify an attribute on a view/layer.
    /// - Parameters:
    ///   - targetOid: The OID of the target (view OID or layer OID depending on the attribute).
    ///   - setter: The setter selector string (e.g. "setHidden:").
    ///   - attrType: The LookinAttrType raw value.
    ///   - value: The encoded value (NSNumber, NSString, NSArray, NSValue, etc.).
    /// - Returns: The server's response description string.
    func modifyAttribute(targetOid: UInt, setter: String, attrType: Int, value: Any) async throws -> String {
        let modification = LookinAttributeModification()
        modification.targetOid = targetOid
        modification.setterSelector = NSSelectorFromString(setter)
        modification.attrType = LookinAttrType(rawValue: attrType) ?? .none
        modification.value = value
        modification.clientReadableVersion = "LookinMCP 0.1.0"

        let requestAttachment = LookinConnectionAttachment()
        requestAttachment.data = modification
        let requestData = try LookinCodec.encodeAttachment(requestAttachment)

        let frame = try await connection.sendRequest(type: LookinCodec.requestTypeInbuiltAttrModification, payload: requestData, timeout: 10)
        guard let payload = frame.payload else {
            return "Modification sent (no response data)."
        }
        let responseAttachment = try LookinCodec.decodeResponseAttachment(from: payload)
        if let error = responseAttachment.error {
            throw error
        }
        // Server returns a LookinDisplayItemDetail on success
        if responseAttachment.data is LookinDisplayItemDetail {
            return "Attribute modified successfully."
        }
        return "Modification sent."
    }

    // MARK: - Invoke Method (Type 206)

    /// Invoke a zero-argument method on a view/layer.
    /// - Parameters:
    ///   - oid: The OID of the target object.
    ///   - selectorName: The selector name (e.g. "setNeedsLayout").
    /// - Returns: Description of the return value, or "void" for void methods.
    func invokeMethod(oid: UInt, selectorName: String) async throws -> String {
        let dict: NSDictionary = [
            "oid": NSNumber(value: oid),
            "text": selectorName as NSString
        ]
        let requestAttachment = LookinConnectionAttachment()
        requestAttachment.data = dict
        let requestData = try LookinCodec.encodeAttachment(requestAttachment)

        let frame = try await connection.sendRequest(type: LookinCodec.requestTypeInvokeMethod, payload: requestData, timeout: 10)
        guard let payload = frame.payload else {
            return "Method invoked (no response data)."
        }
        let responseAttachment = try LookinCodec.decodeResponseAttachment(from: payload)
        if let error = responseAttachment.error {
            throw error
        }
        guard let resultDict = responseAttachment.data as? NSDictionary else {
            return "Method invoked."
        }
        if let desc = resultDict["description"] as? String {
            if desc == "LOOKIN_TAG_RETURN_VALUE_VOID" {
                return "Method invoked (void return)."
            }
            return "Return value: \(desc)"
        }
        return "Method invoked."
    }

    // MARK: - Fetch Selector Names (Type 213)

    /// Fetch all selector names for a given class.
    /// - Parameters:
    ///   - className: The class name (e.g. "UIView", "UILabel").
    ///   - hasArg: If false, only returns selectors without arguments.
    /// - Returns: Array of selector name strings.
    func fetchAllSelectorNames(className: String, hasArg: Bool) async throws -> [String] {
        let dict: NSDictionary = [
            "className": className as NSString,
            "hasArg": NSNumber(value: hasArg)
        ]
        let requestAttachment = LookinConnectionAttachment()
        requestAttachment.data = dict
        let requestData = try LookinCodec.encodeAttachment(requestAttachment)

        let frame = try await connection.sendRequest(type: LookinCodec.requestTypeAllSelectorNames, payload: requestData, timeout: 10)
        guard let payload = frame.payload else {
            throw LookinConnection.ConnectionError.invalidFrame
        }
        let responseAttachment = try LookinCodec.decodeResponseAttachment(from: payload)
        if let error = responseAttachment.error {
            throw error
        }
        guard let selectors = responseAttachment.data as? [String] else {
            throw LookinConnection.ConnectionError.invalidFrame
        }
        return selectors
    }
}

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
}

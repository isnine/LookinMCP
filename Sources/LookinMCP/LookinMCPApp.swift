import MCP
import Foundation
import LookinShared

/// Shared mutable state for the MCP server's connection to a LookinServer instance.
/// Marked @unchecked Sendable because access is serialized by the MCP Server actor.
private final class SessionState: @unchecked Sendable {
    var connection: LookinConnection?
    var requestManager: RequestManager?
    /// Used by lookin_view_detail to look up the layer OID from a view OID.
    var cachedHierarchy: LookinHierarchyInfo?
    /// Cached text content map: view OID -> text string (e.g. UILabel.text, UITextField.text).
    /// Populated on first search and invalidated when hierarchy is re-fetched.
    var cachedTextContentMap: [UInt: String]?
}

@main
struct LookinMCPApp {
    static func main() async throws {
        let session = SessionState()

        let server = Server(
            name: "LookinMCP",
            version: "0.1.0",
            capabilities: .init(
                tools: .init(listChanged: false)
            )
        )

        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: [
                Tool(
                    name: "lookin_connect",
                    description: "Connect to a LookinServer running in an iOS Simulator. Scans ports 47164-47169 unless a specific port is provided.",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([
                            "port": .object([
                                "type": .string("integer"),
                                "description": .string("Specific port to connect to (47164-47169). If omitted, scans all ports.")
                            ])
                        ]),
                        "required": .array([])
                    ]),
                    annotations: .init(readOnlyHint: false, destructiveHint: false, openWorldHint: false)
                ),
                Tool(
                    name: "lookin_disconnect",
                    description: "Disconnect from the currently connected LookinServer.",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([:])
                    ]),
                    annotations: .init(readOnlyHint: false, destructiveHint: false, openWorldHint: false)
                ),
                Tool(
                    name: "lookin_ping",
                    description: "Check if the connected LookinServer is alive and whether the app is in the foreground.",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([:])
                    ]),
                    annotations: .init(readOnlyHint: true, openWorldHint: false)
                ),
                Tool(
                    name: "lookin_app_info",
                    description: "Get information about the connected app: name, bundle ID, device, OS version.",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([:])
                    ]),
                    annotations: .init(readOnlyHint: true, openWorldHint: false)
                ),
                Tool(
                    name: "lookin_hierarchy",
                    description: "Get the full view hierarchy of the connected app as an indented text tree. Each node shows: ClassName (x,y,w,h) oid:N [flags].",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([:])
                    ]),
                    annotations: .init(readOnlyHint: true, openWorldHint: false)
                ),
                Tool(
                    name: "lookin_view_detail",
                    description: "Get detailed attributes for a specific view by its OID (object identifier). Use lookin_hierarchy first to find the OID.",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([
                            "oid": .object([
                                "type": .string("integer"),
                                "description": .string("The object identifier (oid) of the view to inspect. Get this from lookin_hierarchy output.")
                            ])
                        ]),
                        "required": .array([.string("oid")])
                    ]),
                    annotations: .init(readOnlyHint: true, openWorldHint: false)
                ),
                Tool(
                    name: "lookin_search",
                    description: "Fuzzy-search the view hierarchy by class name, view controller name, or text content such as UILabel text, UIButton title label, UITextField text/placeholder (case-insensitive substring match). Returns a flat numbered list of matching nodes with class name, OID, frame, VC, and text. Use lookin_subtree to expand a specific result.",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([
                            "query": .object([
                                "type": .string("string"),
                                "description": .string("Substring to match against view class names, view controller names, and text content (case-insensitive). Example: 'Reorder', 'Submit', 'Label', 'TableView'.")
                            ])
                        ]),
                        "required": .array([.string("query")])
                    ]),
                    annotations: .init(readOnlyHint: true, openWorldHint: false)
                ),
                Tool(
                    name: "lookin_subtree",
                    description: "Get a specific node and its full subtree from the view hierarchy by OID. Use lookin_search or lookin_hierarchy first to find the OID.",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([
                            "oid": .object([
                                "type": .string("integer"),
                                "description": .string("The OID of the node whose subtree you want to see.")
                            ])
                        ]),
                        "required": .array([.string("oid")])
                    ]),
                    annotations: .init(readOnlyHint: true, openWorldHint: false)
                ),
                Tool(
                    name: "lookin_modify",
                    description: "Modify a view property by friendly name. Supports: hidden, alpha, frame, bounds, backgroundColor, cornerRadius, text, fontSize, textColor, borderWidth, borderColor, shadowColor, shadowOpacity, shadowRadius, contentMode, tintColor, tag, numberOfLines, textAlignment, enabled, selected, stackAxis, stackSpacing, contentOffset, contentSize, and more. Use lookin_modify with attribute='help' to see all available attributes and value formats.",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([
                            "oid": .object([
                                "type": .string("integer"),
                                "description": .string("The OID of the view to modify. Get this from lookin_hierarchy or lookin_search.")
                            ]),
                            "attribute": .object([
                                "type": .string("string"),
                                "description": .string("The attribute name to modify (e.g. 'hidden', 'alpha', 'backgroundColor', 'text'). Use 'help' to list all available attributes.")
                            ]),
                            "value": .object([
                                "type": .string("string"),
                                "description": .string("The new value as a string. Format depends on attribute type: booleans as 'true'/'false', colors as '#RRGGBB' or 'r,g,b,a', rects as 'x,y,w,h', etc.")
                            ])
                        ]),
                        "required": .array([.string("oid"), .string("attribute"), .string("value")])
                    ]),
                    annotations: .init(readOnlyHint: false, destructiveHint: true, openWorldHint: false)
                ),
                Tool(
                    name: "lookin_invoke",
                    description: "Call a zero-argument method on a view or layer. Useful for triggering actions like setNeedsLayout, setNeedsDisplay, layoutIfNeeded, removeFromSuperview, etc. Only methods with no arguments are supported.",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([
                            "oid": .object([
                                "type": .string("integer"),
                                "description": .string("The OID of the view to invoke the method on.")
                            ]),
                            "selector": .object([
                                "type": .string("string"),
                                "description": .string("The selector name to invoke (e.g. 'setNeedsLayout', 'layoutIfNeeded', 'setNeedsDisplay'). Must be a zero-argument method.")
                            ])
                        ]),
                        "required": .array([.string("oid"), .string("selector")])
                    ]),
                    annotations: .init(readOnlyHint: false, destructiveHint: true, openWorldHint: false)
                ),
                Tool(
                    name: "lookin_selectors",
                    description: "List available method selectors for a given class name. Returns methods sorted by name length. Use this to discover what methods can be called via lookin_invoke.",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([
                            "className": .object([
                                "type": .string("string"),
                                "description": .string("The class name to list selectors for (e.g. 'UIView', 'UILabel', 'UIButton').")
                            ]),
                            "hasArg": .object([
                                "type": .string("boolean"),
                                "description": .string("If false (default), only return zero-argument selectors. If true, return all selectors.")
                            ])
                        ]),
                        "required": .array([.string("className")])
                    ]),
                    annotations: .init(readOnlyHint: true, openWorldHint: false)
                ),
            ])
        }

        await server.withMethodHandler(CallTool.self) { params in
            switch params.name {

            case "lookin_connect":
                if session.connection?.isConnected == true {
                    return CallTool.Result(content: [.text("Already connected on port \(session.connection!.connectedPort). Disconnect first.")], isError: true)
                }

                let connection = LookinConnection()

                if let portValue = params.arguments?["port"]?.intValue {
                    let port = portValue
                    do {
                        try await connection.connect(port: port)
                        let mgr = RequestManager(connection: connection)
                        session.connection = connection
                        session.requestManager = mgr
                        return CallTool.Result(content: [.text("Connected to LookinServer on port \(port).")])
                    } catch {
                        return CallTool.Result(content: [.text("Failed to connect to port \(port): \(error.localizedDescription)")], isError: true)
                    }
                } else {
                    guard let scanResult = await PortScanner.findAvailablePort() else {
                        return CallTool.Result(content: [.text("No LookinServer found on ports \(PortScanner.portRange). Make sure an app with LookinServer is running in the iOS Simulator.")], isError: true)
                    }
                    do {
                        try await connection.connect(port: scanResult.port)
                        let mgr = RequestManager(connection: connection)
                        session.connection = connection
                        session.requestManager = mgr
                        return CallTool.Result(content: [.text("Connected to LookinServer on port \(scanResult.port).")])
                    } catch {
                        return CallTool.Result(content: [.text("Found server on port \(scanResult.port) but failed to connect: \(error.localizedDescription)")], isError: true)
                    }
                }

            case "lookin_disconnect":
                guard let connection = session.connection else {
                    return CallTool.Result(content: [.text("Not connected to any LookinServer.")], isError: true)
                }
                connection.disconnect()
                session.connection = nil
                session.requestManager = nil
                session.cachedHierarchy = nil
                session.cachedTextContentMap = nil
                return CallTool.Result(content: [.text("Disconnected.")])

            case "lookin_ping":
                guard let mgr = session.requestManager else {
                    return CallTool.Result(content: [.text("Not connected. Use lookin_connect first.")], isError: true)
                }
                do {
                    let result = try await mgr.ping()
                    let status = result.isInBackground ? "App is in BACKGROUND" : "App is in FOREGROUND"
                    return CallTool.Result(content: [.text("Alive. \(status).")])
                } catch {
                    session.connection = nil
                    session.requestManager = nil
                    return CallTool.Result(content: [.text("Ping failed (connection lost): \(error.localizedDescription)")], isError: true)
                }

            case "lookin_app_info":
                guard let mgr = session.requestManager else {
                    return CallTool.Result(content: [.text("Not connected. Use lookin_connect first.")], isError: true)
                }
                do {
                    let appInfo = try await mgr.fetchAppInfo()
                    var lines: [String] = []
                    lines.append("App Name: \(appInfo.appName ?? "Unknown")")
                    lines.append("Bundle ID: \(appInfo.appBundleIdentifier ?? "Unknown")")
                    lines.append("Device: \(appInfo.deviceDescription ?? "Unknown")")
                    lines.append("OS: \(appInfo.osDescription ?? "Unknown")")
                    lines.append("Screen: \(Int(appInfo.screenWidth))x\(Int(appInfo.screenHeight)) @\(Int(appInfo.screenScale))x")
                    lines.append("LookinServer Version: \(appInfo.serverReadableVersion ?? "Unknown")")
                    return CallTool.Result(content: [.text(lines.joined(separator: "\n"))])
                } catch {
                    return CallTool.Result(content: [.text("Failed to fetch app info: \(error.localizedDescription)")], isError: true)
                }

            case "lookin_hierarchy":
                guard let mgr = session.requestManager else {
                    return CallTool.Result(content: [.text("Not connected. Use lookin_connect first.")], isError: true)
                }
                do {
                    let hierarchy = try await mgr.fetchHierarchy()
                    session.cachedHierarchy = hierarchy
                    session.cachedTextContentMap = nil  // invalidate text cache when hierarchy changes
                    let text = HierarchyFormatter.format(hierarchy)
                    return CallTool.Result(content: [.text(text)])
                } catch {
                    return CallTool.Result(content: [.text("Failed to fetch hierarchy: \(error.localizedDescription)")], isError: true)
                }

            case "lookin_view_detail":
                guard let mgr = session.requestManager else {
                    return CallTool.Result(content: [.text("Not connected. Use lookin_connect first.")], isError: true)
                }
                guard let oidValue = params.arguments?["oid"]?.intValue else {
                    return CallTool.Result(content: [.text("Missing required parameter 'oid'. Use lookin_hierarchy to find view OIDs.")], isError: true)
                }
                let oid = UInt(oidValue)

                // AllAttrGroups (request type 210) expects a CALayer OID, but the hierarchy
                // tree prints view OIDs. Look up the corresponding layer OID from the
                // cached hierarchy.
                var layerOid = oid
                if let hierarchy = session.cachedHierarchy {
                    if let item = HierarchyFormatter.findItem(in: hierarchy, viewOid: oid) {
                        if let lo = item.layerObject {
                            layerOid = lo.oid
                        }
                    }
                }

                do {
                    let groups = try await mgr.fetchAllAttrGroups(oid: layerOid)
                    let text = "=== View Detail (oid: \(oid)) ===\n" + ViewDetailFormatter.formatGroups(groups)
                    return CallTool.Result(content: [.text(text)])
                } catch {
                    return CallTool.Result(content: [.text("Failed to fetch view detail for oid \(oid): \(error.localizedDescription)")], isError: true)
                }

            case "lookin_search":
                guard let mgr = session.requestManager else {
                    return CallTool.Result(content: [.text("Not connected. Use lookin_connect first.")], isError: true)
                }
                guard let query = params.arguments?["query"]?.stringValue, !query.isEmpty else {
                    return CallTool.Result(content: [.text("Missing required parameter 'query'.")], isError: true)
                }
                do {
                    let hierarchy: LookinHierarchyInfo
                    if let cached = session.cachedHierarchy {
                        hierarchy = cached
                    } else {
                        hierarchy = try await mgr.fetchHierarchy()
                        session.cachedHierarchy = hierarchy
                        session.cachedTextContentMap = nil  // invalidate text cache with new hierarchy
                    }

                    // Fetch text content for all text-bearing views (cached after first fetch)
                    let textContentMap: [UInt: String]
                    if let cached = session.cachedTextContentMap {
                        textContentMap = cached
                    } else {
                        let textBearingViews = HierarchyFormatter.collectTextBearingOids(hierarchy)
                        textContentMap = await mgr.fetchTextContentMap(for: textBearingViews)
                        session.cachedTextContentMap = textContentMap
                    }

                    let text = HierarchyFormatter.searchFlat(hierarchy, query: query, textContentMap: textContentMap)
                    return CallTool.Result(content: [.text(text)])
                } catch {
                    return CallTool.Result(content: [.text("Failed to search hierarchy: \(error.localizedDescription)")], isError: true)
                }

            case "lookin_subtree":
                guard let mgr = session.requestManager else {
                    return CallTool.Result(content: [.text("Not connected. Use lookin_connect first.")], isError: true)
                }
                guard let oidValue = params.arguments?["oid"]?.intValue else {
                    return CallTool.Result(content: [.text("Missing required parameter 'oid'. Use lookin_search or lookin_hierarchy to find OIDs.")], isError: true)
                }
                let oid = UInt(oidValue)
                do {
                    let hierarchy: LookinHierarchyInfo
                    if let cached = session.cachedHierarchy {
                        hierarchy = cached
                    } else {
                        hierarchy = try await mgr.fetchHierarchy()
                        session.cachedHierarchy = hierarchy
                    }
                    guard let text = HierarchyFormatter.formatNodeSubtree(hierarchy, oid: oid) else {
                        return CallTool.Result(content: [.text("No node found with oid \(oid). Use lookin_hierarchy to refresh.")], isError: true)
                    }
                    return CallTool.Result(content: [.text(text)])
                } catch {
                    return CallTool.Result(content: [.text("Failed to get subtree: \(error.localizedDescription)")], isError: true)
                }

            case "lookin_modify":
                guard let mgr = session.requestManager else {
                    return CallTool.Result(content: [.text("Not connected. Use lookin_connect first.")], isError: true)
                }
                guard let attribute = params.arguments?["attribute"]?.stringValue else {
                    return CallTool.Result(content: [.text("Missing required parameter 'attribute'.")], isError: true)
                }

                // Special case: help
                if attribute.lowercased() == "help" {
                    return CallTool.Result(content: [.text(AttributeRegistry.helpText)])
                }

                guard let oidValue = params.arguments?["oid"]?.intValue else {
                    return CallTool.Result(content: [.text("Missing required parameter 'oid'.")], isError: true)
                }
                guard let valueStr = params.arguments?["value"]?.stringValue else {
                    return CallTool.Result(content: [.text("Missing required parameter 'value'.")], isError: true)
                }
                let viewOid = UInt(oidValue)

                guard let mapping = AttributeRegistry.mappings[attribute] else {
                    return CallTool.Result(content: [.text("Unknown attribute '\(attribute)'. Use attribute='help' to see available attributes.")], isError: true)
                }

                // Determine the target OID: view OID vs layer OID
                var targetOid = viewOid
                if !mapping.isViewProperty {
                    // Need layer OID - look up from cached hierarchy
                    if let hierarchy = session.cachedHierarchy,
                       let item = HierarchyFormatter.findItem(in: hierarchy, viewOid: viewOid),
                       let layerObj = item.layerObject {
                        targetOid = layerObj.oid
                    }
                    // If no cached hierarchy, the view OID might work (the server
                    // resolves it), but layer OID is more reliable.
                }

                do {
                    let parsedValue = try AttributeRegistry.parseValue(valueStr, attrType: mapping.attrType)
                    let result = try await mgr.modifyAttribute(
                        targetOid: targetOid,
                        setter: mapping.setter,
                        attrType: mapping.attrType,
                        value: parsedValue
                    )
                    // Invalidate caches since the view tree may have changed visually
                    session.cachedTextContentMap = nil
                    return CallTool.Result(content: [.text(result)])
                } catch {
                    return CallTool.Result(content: [.text("Failed to modify '\(attribute)': \(error.localizedDescription)")], isError: true)
                }

            case "lookin_invoke":
                guard let mgr = session.requestManager else {
                    return CallTool.Result(content: [.text("Not connected. Use lookin_connect first.")], isError: true)
                }
                guard let oidValue = params.arguments?["oid"]?.intValue else {
                    return CallTool.Result(content: [.text("Missing required parameter 'oid'.")], isError: true)
                }
                guard let selector = params.arguments?["selector"]?.stringValue, !selector.isEmpty else {
                    return CallTool.Result(content: [.text("Missing required parameter 'selector'.")], isError: true)
                }
                // Validate: no colon means zero args (unless it's a simple property getter)
                if selector.contains(":") {
                    return CallTool.Result(content: [.text("Only zero-argument methods are supported. '\(selector)' contains ':' which indicates it takes arguments.")], isError: true)
                }
                let oid = UInt(oidValue)
                do {
                    let result = try await mgr.invokeMethod(oid: oid, selectorName: selector)
                    return CallTool.Result(content: [.text(result)])
                } catch {
                    return CallTool.Result(content: [.text("Failed to invoke '\(selector)': \(error.localizedDescription)")], isError: true)
                }

            case "lookin_selectors":
                guard let mgr = session.requestManager else {
                    return CallTool.Result(content: [.text("Not connected. Use lookin_connect first.")], isError: true)
                }
                guard let className = params.arguments?["className"]?.stringValue, !className.isEmpty else {
                    return CallTool.Result(content: [.text("Missing required parameter 'className'.")], isError: true)
                }
                let hasArg = params.arguments?["hasArg"]?.boolValue ?? false
                do {
                    let selectors = try await mgr.fetchAllSelectorNames(className: className, hasArg: hasArg)
                    if selectors.isEmpty {
                        return CallTool.Result(content: [.text("No selectors found for class '\(className)'.")])
                    }
                    let header = hasArg
                        ? "All selectors for \(className) (\(selectors.count)):"
                        : "Zero-argument selectors for \(className) (\(selectors.count)):"
                    let text = header + "\n" + selectors.joined(separator: "\n")
                    return CallTool.Result(content: [.text(text)])
                } catch {
                    return CallTool.Result(content: [.text("Failed to fetch selectors for '\(className)': \(error.localizedDescription)")], isError: true)
                }

            default:
                return CallTool.Result(content: [.text("Unknown tool: \(params.name)")], isError: true)
            }
        }

        let transport = StdioTransport()
        try await server.start(transport: transport)
        await server.waitUntilCompleted()
    }
}

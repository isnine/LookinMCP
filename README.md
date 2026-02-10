# LookinMCP

An MCP (Model Context Protocol) server that lets AI assistants inspect the live UI view hierarchy of iOS apps running in the Simulator.

LookinMCP connects to [LookinServer](https://github.com/nicklama/LookinServer) — a framework embedded in your iOS app — and exposes the app's view hierarchy, view attributes, and layout information as MCP tools. This enables Claude, GPT, Cursor, and other MCP-compatible AI assistants to understand what's on screen and help you debug UI issues.

## How It Works

```
AI Assistant  <--stdio/JSON-RPC-->  LookinMCP  <--TCP/Peertalk-->  iOS Simulator App
                                   (this project)                  (with LookinServer)
```

1. Your iOS app includes the [LookinServer](https://github.com/nicklama/LookinServer) framework, which listens on a TCP port (47164-47169) in the Simulator.
2. LookinMCP connects to that port and speaks the Peertalk binary protocol to request view hierarchy data.
3. The AI assistant calls MCP tools (via stdio JSON-RPC) to query the hierarchy, search for views, and inspect individual view attributes.

## Prerequisites

- **macOS 13+** (Ventura or later)
- **Swift 6.0+** (Xcode 16+)
- **iOS Simulator** with an app that integrates LookinServer

## Building

```bash
swift build
```

The binary will be at `.build/debug/LookinMCP`.

## Integrating LookinServer in Your iOS App

Add LookinServer to your iOS app so LookinMCP can connect to it. **Only include it in Debug builds** — it should never ship to production.

### CocoaPods

```ruby
pod 'LookinServer', :configurations => ['Debug']
```

### Swift Package Manager

```
https://github.com/nicklama/LookinServer
```

Add it as a dependency and link it only to your Debug scheme.

Once integrated, simply run your app in the iOS Simulator. LookinServer starts automatically and listens on a local TCP port.

## Configuring Your AI Assistant

### Claude Desktop

Add to `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "lookin": {
      "command": "/path/to/LookinMCP"
    }
  }
}
```

### Cursor

Add to your MCP configuration:

```json
{
  "mcpServers": {
    "lookin": {
      "command": "/path/to/LookinMCP"
    }
  }
}
```

Replace `/path/to/LookinMCP` with the actual path to the built binary (e.g., the output of `swift build --show-bin-path`).

## Available Tools

| Tool | Description |
|------|-------------|
| `lookin_connect` | Connect to a LookinServer in the Simulator. Scans ports 47164-47169 or connects to a specific port. |
| `lookin_disconnect` | Disconnect from the current LookinServer. |
| `lookin_ping` | Check if the server is alive and whether the app is in the foreground. |
| `lookin_app_info` | Get app name, bundle ID, device model, OS version, and screen info. |
| `lookin_hierarchy` | Get the full view hierarchy as an indented text tree. Each node shows class name, frame, OID, and flags. |
| `lookin_view_detail` | Get detailed attributes for a specific view by its OID (object identifier). |
| `lookin_search` | Fuzzy-search the hierarchy by class name or view controller name. Returns a flat list of matches. |
| `lookin_subtree` | Get a specific node and its full subtree by OID. |

## Example Workflow

```
You: "Connect to the app and show me the view hierarchy"
AI:  [calls lookin_connect] → Connected on port 47164
AI:  [calls lookin_hierarchy] → Returns the full view tree

You: "Find all UILabel views"
AI:  [calls lookin_search with query "UILabel"] → Returns numbered list of matches

You: "Show me details for the label with oid 42"
AI:  [calls lookin_view_detail with oid 42] → Returns frame, font, text color, etc.

You: "What's the subtree under the navigation bar?"
AI:  [calls lookin_subtree with the nav bar's oid] → Returns that node and all its children
```

## Architecture

```
Sources/
├── LookinMCP/                        # Swift executable
│   ├── LookinMCPApp.swift            # Entry point, MCP tool handlers
│   ├── Connection/
│   │   ├── LookinConnection.swift    # TCP + Peertalk frame protocol
│   │   ├── PortScanner.swift         # Scans ports 47164-47169
│   │   └── RequestManager.swift      # Request/response codec
│   └── Formatters/
│       ├── HierarchyFormatter.swift  # View tree → text
│       └── ViewDetailFormatter.swift # View attributes → text
└── LookinShared/                     # ObjC models from LookinServer
```

## Limitations

- **Simulator only** — LookinServer communicates over localhost TCP, which is only available in the Simulator (not on physical devices over USB).
- **One connection at a time** — LookinServer accepts a single TCP client. Close the Lookin desktop app or other MCP instances before connecting.
- **Read-only** — LookinMCP currently only reads the view hierarchy. It does not modify views or invoke methods.

## Credits

- [LookinServer](https://github.com/nicklama/LookinServer) — The iOS framework that makes view inspection possible
- [Lookin](https://github.com/nicklama/Lookin) — The macOS desktop client for LookinServer
- [MCP Swift SDK](https://github.com/modelcontextprotocol/swift-sdk) — The official Swift SDK for the Model Context Protocol

## License

MIT

import Foundation

struct MCPServer {
    private let protocolVersion = "2025-06-18"
    private let serverName = "peek-mcp"
    private let serverVersion = "0.4.6"

    func run() async {
        log("peek-mcp listening on stdio")
        while let line = readLine(strippingNewline: true) {
            guard !line.isEmpty,
                  let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            if let response = await handle(request: json) {
                writeResponse(response)
            }
        }
    }

    /// Public so non-stdio transports (Unix socket daemon) can reuse it.
    func handle(request: [String: Any]) async -> [String: Any]? {
        guard let method = request["method"] as? String else { return nil }
        let id = request["id"]
        let params = (request["params"] as? [String: Any]) ?? [:]
        let isNotification = id == nil

        switch method {
        case "initialize":
            return success(id: id, result: [
                "protocolVersion": protocolVersion,
                "capabilities": ["tools": [String: Any]()],
                "serverInfo": ["name": serverName, "version": serverVersion]
            ])
        case "notifications/initialized", "notifications/cancelled":
            return nil
        case "tools/list":
            return success(id: id, result: ["tools": toolDefinitions()])
        case "tools/call":
            return await handleToolCall(id: id, params: params)
        default:
            if isNotification { return nil }
            return error(id: id, code: -32601, message: "Method not found: \(method)")
        }
    }

    private func handleToolCall(id: Any?, params: [String: Any]) async -> [String: Any]? {
        guard let name = params["name"] as? String else {
            return error(id: id, code: -32602, message: "Missing tool name")
        }
        let args = (params["arguments"] as? [String: Any]) ?? [:]

        do {
            switch name {
            case "list_windows":
                let includeOffscreen = (args["include_offscreen"] as? Bool) ?? false
                let windows = try await ScreenCapture.listWindows(includeOffscreen: includeOffscreen)
                return success(id: id, result: textResult(jsonText(windows)))

            case "list_displays":
                let displays = try await ScreenCapture.listDisplays()
                return success(id: id, result: textResult(jsonText(displays)))

            case "capture_window":
                let hideCursor = (args["hide_cursor"] as? Bool) ?? true
                let force = (args["force"] as? Bool) ?? false
                let format = parseFormat(args["format"])
                let wid: UInt32? = (args["window_id"] as? Int).map(UInt32.init)
                    ?? (args["window_id"] as? NSNumber)?.uint32Value
                if let wid = wid {
                    let result = try await ScreenCapture.captureWindow(
                        id: wid, hideCursor: hideCursor, caller: .mcp, force: force, format: format
                    )
                    return success(id: id, result: imageResult(result.data, mimeType: result.mimeType))
                }
                if let appName = args["app_name"] as? String, !appName.isEmpty {
                    let result = try await ScreenCapture.captureWindow(
                        byApp: appName, hideCursor: hideCursor, caller: .mcp, force: force, format: format
                    )
                    return success(id: id, result: imageResult(result.data, mimeType: result.mimeType))
                }
                return error(id: id, code: -32602, message: "capture_window requires window_id or app_name")

            case "capture_display":
                let did: UInt32? = (args["display_id"] as? Int).map(UInt32.init)
                    ?? (args["display_id"] as? NSNumber)?.uint32Value
                let hideCursor = (args["hide_cursor"] as? Bool) ?? true
                let format = parseFormat(args["format"])
                let result = try await ScreenCapture.captureDisplay(
                    id: did, hideCursor: hideCursor, caller: .mcp, format: format
                )
                return success(id: id, result: imageResult(result.data, mimeType: result.mimeType))

            case "capture_region":
                guard let x = args["x"] as? Int, let y = args["y"] as? Int,
                      let w = args["width"] as? Int, let h = args["height"] as? Int else {
                    return error(id: id, code: -32602, message: "capture_region requires x, y, width, height")
                }
                let did: UInt32? = (args["display_id"] as? Int).map(UInt32.init)
                let hideCursor = (args["hide_cursor"] as? Bool) ?? true
                let format = parseFormat(args["format"])
                let result = try await ScreenCapture.captureRegion(
                    x: x, y: y, width: w, height: h,
                    displayID: did, hideCursor: hideCursor, caller: .mcp, format: format
                )
                return success(id: id, result: imageResult(result.data, mimeType: result.mimeType))

            default:
                return error(id: id, code: -32602, message: "Unknown tool: \(name)")
            }
        } catch {
            return success(id: id, result: [
                "content": [["type": "text", "text": "Error: \(error.localizedDescription)"]],
                "isError": true
            ])
        }
    }

    private func toolDefinitions() -> [[String: Any]] {
        [
            [
                "name": "list_windows",
                "description": "List visible windows on macOS. Returns id, title, app, bundleID, bounds, onScreen, layer for each.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "include_offscreen": [
                            "type": "boolean",
                            "description": "Include windows that are minimized or off-screen. Default false."
                        ]
                    ]
                ]
            ],
            [
                "name": "list_displays",
                "description": "List attached displays with pixel size, frame, and backing scale.",
                "inputSchema": ["type": "object", "properties": [String: Any]()]
            ],
            [
                "name": "capture_window",
                "description": "Capture a specific window as a PNG (no shadow, no surrounding desktop). Pass either window_id (from list_windows) or app_name to capture the frontmost window for that app. Sensitive apps (1Password, Keychain Access, etc.) are denied by default — pass force: true to override.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "window_id": ["type": "integer", "description": "Window ID from list_windows."],
                        "app_name": ["type": "string", "description": "App name (case-insensitive substring), e.g. \"Safari\" or \"Xcode\"."],
                        "hide_cursor": ["type": "boolean", "description": "Default true."],
                        "force": ["type": "boolean", "description": "Bypass the deny-list. Default false."]
                    ]
                ]
            ],
            [
                "name": "capture_display",
                "description": "Capture a full display as a PNG image.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "display_id": ["type": "integer", "description": "Display ID from list_displays. Defaults to primary."],
                        "hide_cursor": ["type": "boolean", "description": "Default true."]
                    ]
                ]
            ],
            [
                "name": "capture_region",
                "description": "Capture a rectangular region of a display, in display points (origin top-left).",
                "inputSchema": [
                    "type": "object",
                    "required": ["x", "y", "width", "height"],
                    "properties": [
                        "x": ["type": "integer"],
                        "y": ["type": "integer"],
                        "width": ["type": "integer"],
                        "height": ["type": "integer"],
                        "display_id": ["type": "integer"],
                        "hide_cursor": ["type": "boolean"]
                    ]
                ]
            ]
        ]
    }

    private func imageResult(_ data: Data, mimeType: String) -> [String: Any] {
        [
            "content": [[
                "type": "image",
                "data": data.base64EncodedString(),
                "mimeType": mimeType
            ]]
        ]
    }

    /// MCP default comes from `QualityPreset.current` (env-driven via
    /// `PEEK_QUALITY=fast|balanced|lossless`, default `balanced`).
    /// Per-call `format: "png"` or `format: "jpeg"` overrides the preset.
    private func parseFormat(_ raw: Any?) -> ScreenCapture.OutputFormat {
        guard let s = (raw as? String)?.lowercased() else {
            return QualityPreset.current.format
        }
        switch s {
        case "png": return .png
        case "jpeg", "jpg": return .jpeg(quality: 0.7)
        default: return QualityPreset.current.format
        }
    }

    private func textResult(_ text: String) -> [String: Any] {
        ["content": [["type": "text", "text": text]]]
    }

    private func jsonText<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(value), let s = String(data: data, encoding: .utf8) {
            return s
        }
        return "[]"
    }

    private func success(id: Any?, result: [String: Any]) -> [String: Any] {
        var resp: [String: Any] = ["jsonrpc": "2.0", "result": result]
        if let id = id { resp["id"] = id }
        return resp
    }

    private func error(id: Any?, code: Int, message: String) -> [String: Any] {
        var resp: [String: Any] = [
            "jsonrpc": "2.0",
            "error": ["code": code, "message": message]
        ]
        if let id = id { resp["id"] = id }
        return resp
    }

    private func writeResponse(_ response: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: response, options: []) else { return }
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([0x0a]))
    }

    private func log(_ message: String) {
        FileHandle.standardError.write("\(message)\n".data(using: .utf8)!)
    }
}

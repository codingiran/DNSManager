//
//  ScriptRunner.swift
//  DNSManager
//
//  Created by CodingIran on 2022/11/11.
//

import Foundation

#if os(macOS)

import Cocoa

public enum ScriptError: LocalizedError {
    case initAppleScriptFailed
    case executeAppleScriptFailed(String)

    var localizedDescription: String {
        switch self {
        case .initAppleScriptFailed:
            return "init AppleScript failed"
        case .executeAppleScriptFailed(let reason):
            return "execute AppleScript failed: \(reason)"
        }
    }
}

open class ScriptRunner {
    public init() {}

    @discardableResult
    public func runBash(path: String = "/bin/bash", command: [String]) -> String? {
        let process = Process()
        process.launchPath = path
        process.arguments = command
        let pipe = Pipe()
        process.standardOutput = pipe
        process.launch()
        process.waitUntilExit()
        let fileData = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: fileData, encoding: String.Encoding.utf8)?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    }

    public func runScriptWithRootPermission(script: String) throws {
        let tmpPath = FileManager.default.temporaryDirectory.appendingPathComponent(NSUUID().uuidString).appendingPathExtension("sh")
        try script.write(to: tmpPath, atomically: true, encoding: .utf8)
        let appleScriptStr = "do shell script \"bash \(tmpPath.path) \" with administrator privileges"
        guard let appleScript = NSAppleScript(source: appleScriptStr) else {
            throw ScriptError.initAppleScriptFailed
        }
        var dict: NSDictionary?
        _ = appleScript.executeAndReturnError(&dict)
        if let dict {
            throw ScriptError.executeAppleScriptFailed(dict.description)
        }
        try FileManager.default.removeItem(at: tmpPath)
    }
}

#endif

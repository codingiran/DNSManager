//
//  DNSManager.swift
//  DNSManager
//
//  Created by CodingIran on 2022/11/11.
//

import Foundation

// Enforce minimum Swift version for all platforms and build systems.
#if swift(<5.10)
    #error("DNSManager doesn't support Swift versions below 5.10.")
#endif

/// Current DNSManager version Release 1.0.0. Necessary since SPM doesn't use dynamic libraries. Plus this will be more accurate.
public let version = "1.0.0"

/// DNS Manager error types
public enum DNSManagerError: LocalizedError, Sendable {
    case noNetworkServicesFound
    case backupFileNotFound(String)
    case invalidBackupFile(String)
    case backupCleanupFailed(Error)
    case jsonSerializationFailed(Error)
    case fileWriteFailed(String, Error)
    case fileReadFailed(String, Error)
    case jsonDeserializationFailed(String)
    case fileRemovalFailed(String, Error)

    public var errorDescription: String? {
        switch self {
        case .noNetworkServicesFound:
            return "No network services found"
        case let .backupFileNotFound(path):
            return "Backup file not found at path: \(path)"
        case let .invalidBackupFile(path):
            return "Invalid backup file at path: \(path)"
        case let .backupCleanupFailed(error):
            return "Failed to cleanup backup file: \(error.localizedDescription)"
        case let .jsonSerializationFailed(error):
            return "Failed to serialize DNS configuration to JSON: \(error.localizedDescription)"
        case let .fileWriteFailed(path, error):
            return "Failed to write backup file at \(path): \(error.localizedDescription)"
        case let .fileReadFailed(path, error):
            return "Failed to read backup file at \(path): \(error.localizedDescription)"
        case let .jsonDeserializationFailed(path):
            return "Failed to deserialize JSON from backup file at \(path)"
        case let .fileRemovalFailed(path, error):
            return "Failed to remove file at \(path): \(error.localizedDescription)"
        }
    }
}

#if os(macOS)

    import os.log
    import ScriptRunner

    open class DNSManager: ScriptRunner, @unchecked Sendable {
        /// Current system configured DNS servers
        public var currentSystemDnsServers: [String]? {
            let bash = ["-c", "scutil --dns | grep 'nameserver' | sort | uniq | cut -f2- -d':' | cut -f2- -d' '"]
            guard let output = try? runBash(command: bash) else { return nil }
            let dnsServers = output.components(separatedBy: "\n")
            return dnsServers
        }

        /// Backup current DNS settings and override all network services with target DNS servers
        public func overrideAndBackupDnsServers(_ targetDnsServers: [String], backupFilePath: String) throws {
            guard let allNetworkServiceNames = allNetworkServiceNames else {
                throw DNSManagerError.noNetworkServicesFound
            }

            if #available(macOS 11.0, *) {
                os_log("Found network services: \(allNetworkServiceNames)")
                os_log("Target DNS servers: \(targetDnsServers)")
            }

            let targetDnsString = targetDnsServers.joined(separator: " ")
            var DNSMap: [String: String] = [:]
            allNetworkServiceNames.forEach { [weak self] in
                guard let self else { return }
                var backupDNS = ""
                if let currentDns = getDnsServers(for: $0), currentDns != targetDnsString {
                    backupDNS = currentDns
                }
                DNSMap[$0] = backupDNS
            }

            // Serialize DNS configuration to JSON
            let data: Data
            do {
                data = try JSONSerialization.data(withJSONObject: DNSMap, options: [])
            } catch {
                throw DNSManagerError.jsonSerializationFailed(error)
            }

            // Remove existing backup file if present
            if FileManager.default.fileExists(atPath: backupFilePath) {
                do {
                    try FileManager.default.removeItem(atPath: backupFilePath)
                } catch {
                    throw DNSManagerError.fileRemovalFailed(backupFilePath, error)
                }
            }

            // Write backup file
            let url = URL(fileURLWithPath: backupFilePath)
            do {
                try data.write(to: url)
            } catch {
                throw DNSManagerError.fileWriteFailed(backupFilePath, error)
            }

            // Apply DNS servers to all network services
            allNetworkServiceNames.forEach { [weak self] in
                guard let self else { return }
                setDnsServers(targetDnsServers, to: $0)
            }
        }

        /// Backup and override DNS with single server (convenience method)
        public func overrideAndBackupDnsServer(_ targetDnsServer: String, backupFilePath: String) throws {
            try overrideAndBackupDnsServers([targetDnsServer], backupFilePath: backupFilePath)
        }

        /// Restore DNS servers from backup file
        public func restoreDnsServersFromBackup(backupFilePath: String) throws {
            guard let allNetworkServiceNames = allNetworkServiceNames,
                  allNetworkServiceNames.count > 0
            else {
                throw DNSManagerError.noNetworkServicesFound
            }

            // Check if backup file exists
            guard FileManager.default.fileExists(atPath: backupFilePath) else {
                throw DNSManagerError.backupFileNotFound(backupFilePath)
            }

            let url = URL(fileURLWithPath: backupFilePath)

            // Read backup file
            let data: Data
            do {
                data = try Data(contentsOf: url)
            } catch {
                throw DNSManagerError.fileReadFailed(backupFilePath, error)
            }

            // Deserialize JSON
            let DNSMap: [String: String]
            do {
                guard let jsonObject = try JSONSerialization.jsonObject(with: data, options: []) as? [String: String],
                      jsonObject.count > 0
                else {
                    throw DNSManagerError.jsonDeserializationFailed(backupFilePath)
                }
                DNSMap = jsonObject
            } catch {
                if error is DNSManagerError {
                    throw error
                } else {
                    throw DNSManagerError.jsonDeserializationFailed(backupFilePath)
                }
            }

            // Restore DNS settings
            if #available(macOS 11.0, *) {
                os_log("Restoring DNS for network services: \(allNetworkServiceNames)")
            }

            allNetworkServiceNames.forEach { [weak self] in
                guard let self else { return }
                if let backupDNS = DNSMap[$0] {
                    setDnsServers(backupDNS, to: $0)
                }
            }

            // Clean up backup file after successful restoration
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                throw DNSManagerError.fileRemovalFailed(backupFilePath, error)
            }
        }

        /// All active network interface names
        public var allNetworkInterfaceNames: [String]? {
            let bash = ["-c", "ifconfig -uv | grep '^[a-z0-9]' | awk -F : '{print $1}'"]
            guard let output = try? runBash(command: bash) else {
                return nil
            }
            let interfaceNames = output.components(separatedBy: "\n").filter { $0.count > 0 }
            return interfaceNames
        }

        /// All network service names (user-friendly names like "Wi-Fi", "Ethernet")
        public var allNetworkServiceNames: [String]? {
            guard let allNetworkInterfaceNames = allNetworkInterfaceNames else { return nil }
            let serviceNames: [String] = allNetworkInterfaceNames.compactMap { [weak self] in
                let bash = ["-c", "networksetup -listnetworkserviceorder | grep '\($0))' -B1 | grep -v '\($0)' | cut -d ')' -f2 | sed 's/^[ ]*//;s/[ ]*$//'"]
                let output = try? self?.runBash(command: bash)
                return output?.trimmed
            }
            return serviceNames.filter { $0.count > 0 }
        }

        /// Get DNS servers for specified network service (returns space-separated string)
        private func getDnsServers(for networkServiceName: String) -> String? {
            let bash = ["-c", "networksetup -getdnsservers '\(networkServiceName)'"]
            let dns = try? runBash(command: bash)
            guard let dns = dns, !dns.contains("There aren't any DNS Servers") else { return nil }
            return dns.replacingOccurrences(of: "\n", with: " ")
        }

        /// Set DNS servers for specified network service
        @discardableResult
        private func setDnsServers(_ dnsServers: [String], to networkServiceName: String) -> Bool {
            let dnsArguments: String
            if dnsServers.isEmpty {
                dnsArguments = "Empty"
            } else {
                dnsArguments = dnsServers.joined(separator: " ")
            }
            let bash = ["-c", "networksetup -setdnsservers '\(networkServiceName)' \(dnsArguments)"]
            let output = try? runBash(command: bash)
            return output == nil
        }

        /// Set DNS server from string (backward compatibility)
        @discardableResult
        private func setDnsServers(_ dnsServer: String?, to networkServiceName: String) -> Bool {
            if let dnsServer, !dnsServer.isEmpty {
                let dnsArray = dnsServer.components(separatedBy: " ").filter { !$0.isEmpty }
                return setDnsServers(dnsArray, to: networkServiceName)
            } else {
                return setDnsServers([], to: networkServiceName)
            }
        }
    }

    private extension String {
        var trimmed: String {
            return trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        }
    }

#endif

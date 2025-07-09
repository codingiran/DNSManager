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

/// Current DNSManager version Release 0.1.1. Necessary since SPM doesn't use dynamic libraries. Plus this will be more accurate.
public let version = "0.1.1"

#if os(macOS)

    import os.log
    import ScriptRunner

    open class DNSManager: ScriptRunner, @unchecked Sendable {
        public static let togglingDNS = "6.6.6.6"

        /// 路由器设置的默认 DNS
        private lazy var routerDefaultDNS: [String]? = {
            let bash = ["-c", "scutil --dns | grep 'nameserver' | sort | uniq | cut -f2- -d':' | cut -f2- -d' '"]
            guard let output = try? runBash(command: bash) else { return nil }
            let defaultDNS = output.components(separatedBy: "\n")
            return defaultDNS
        }()

        /// 接管 DNS
        public func takeOverDNS(_ dns: String = togglingDNS, backupDNSPath: String) {
            // 接管前保存用户设置的所有 DNS
            guard let allNetworkNames = allNetworkNames else { return }
            if #available(macOS 11.0, *) {
                os_log("takeOverDNS allNetworkNames is \(allNetworkNames)")
            }
            var DNSMap: [String: String] = [:]
            allNetworkNames.forEach { [weak self] in
                var backupDNS = ""
                if let dnsOfNetwork = self?.dnsOfNetwork($0), dnsOfNetwork != dns {
                    backupDNS = dnsOfNetwork
                }
                DNSMap[$0] = backupDNS
            }
            let data = try? JSONSerialization.data(withJSONObject: DNSMap, options: [])
            if FileManager.default.fileExists(atPath: backupDNSPath) {
                try? FileManager.default.removeItem(atPath: backupDNSPath)
            }
            let url = URL(fileURLWithPath: backupDNSPath)
            do {
                try data?.write(to: url)
            } catch {
                os_log("save backupDNS failed: %{public}@", error.localizedDescription)
            }
            // 设置 DNS
            allNetworkNames.forEach { [weak self] in
                self?.setDNS(dns, to: $0)
            }
        }

        /// 还原 DNS
        public func restoreDNS(backupDNSPath: String) {
            // 获取备份的DNS
            guard let allNetworkNames = allNetworkNames, allNetworkNames.count > 0 else {
                return
            }
            let url = URL(fileURLWithPath: backupDNSPath)
            if FileManager.default.fileExists(atPath: backupDNSPath),
               let data = try? Data(contentsOf: url),
               let DNSMap = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: String],
               DNSMap.count > 0
            {
                // 有记录，恢复成记录的 DNS
                if #available(macOS 11.0, *) {
                    os_log("restoreDNS allNetworkNames is \(allNetworkNames)")
                }
                allNetworkNames.forEach { [weak self] in
                    if let backupDNS = DNSMap[$0] {
                        self?.setDNS(backupDNS, to: $0)
                    }
                }
                do {
                    try FileManager.default.removeItem(at: url)
                } catch {
                    os_log("remove backupDNS failed: %{public}@", error.localizedDescription)
                }
            }
            // 清理所有网卡中的 togglingDNS
            allNetworkNames.forEach { [weak self] in
                if let dns = self?.dnsOfNetwork($0), dns == DNSManager.togglingDNS {
                    // 清理
                    self?.setDNS(nil, to: $0)
                }
            }
        }

        /// 获取所有的网卡
        private var allNetworkPorts: [String]? {
            let bash = ["-c", "ifconfig -uv | grep '^[a-z0-9]' | awk -F : '{print $1}'"]
            guard let output = try? runBash(command: bash) else {
                return nil
            }
            let networkPorts = output.components(separatedBy: "\n").filter { $0.count > 0 }
            return networkPorts
        }

        /// 获取全部网卡名称
        private var allNetworkNames: [String]? {
            guard let allNetworkPorts = allNetworkPorts else { return nil }
            let networkNames: [String] = allNetworkPorts.compactMap { [weak self] in
                let bash = ["-c", "networksetup -listnetworkserviceorder | grep '\($0))' -B1 | grep -v '\($0)' | cut -d ')' -f2 | sed 's/^[ ]*//;s/[ ]*$//'"]
                let output = try? self?.runBash(command: bash)
                return output?.trimmed
            }
            return networkNames.filter { $0.count > 0 }
        }

        /// 根据网卡名称获取 DNS （"1.1.1.1 8.8.8.8"）
        private func dnsOfNetwork(_ networkName: String) -> String? {
            let bash = ["-c", "networksetup -getdnsservers '\(networkName)'"]
            let dns = try? runBash(command: bash)
            guard let dns = dns, !dns.contains("There aren't any DNS Servers") else { return nil }
            return dns.replacingOccurrences(of: "\n", with: " ")
        }

        /// 给网卡设置 DNS
        @discardableResult
        private func setDNS(_ dns: String?, to network: String) -> Bool {
            var newDNS = "empty"
            if let dns, dns.count > 0 {
                newDNS = dns
            }
            let bash = ["-c", "networksetup -setdnsservers '\(network)' \(newDNS)"]
            let output = try? runBash(command: bash)
            return output == nil
        }
    }

    private extension String {
        var trimmed: String {
            return trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        }
    }

#endif

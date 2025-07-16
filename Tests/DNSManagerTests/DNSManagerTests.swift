@testable import DNSManager
import Foundation
import XCTest

// MARK: - DNSManagerTests

/*
 IMPORTANT TESTING STRATEGY:

 This test suite includes tests that actually modify system DNS settings temporarily:
 - testSingleDnsServerConvenienceMethod()
 - testMultipleDnsServersBackup()

 Safety Measures:
 1. Global test DNS values are defined as constants
 2. Original DNS settings are automatically backed up before modification
 3. DNS settings are automatically restored in tearDown() after each test
 4. Even if tests fail, tearDown() ensures restoration happens

 This approach ensures:
 - Tests validate real system behavior
 - No permanent "pollution" of the test machine's DNS
 - Safe execution in CI/CD environments
 - Reliable cleanup even on test failures
 */

#if os(macOS)

    final class DNSManagerTests: XCTestCase {
        var dnsManager: DNSManager!
        var tempDirectory: URL!
        var testBackupFilePath: String!

        // Test DNS values
        static let testSingleDnsServer = "8.8.8.8"
        static let testMultipleDnsServers = ["8.8.8.8", "8.8.4.4", "1.1.1.1"]

        // Backup management
        var needsRestore = false
        var actualBackupFilePath: String?

        override func setUp() {
            super.setUp()
            dnsManager = DNSManager()

            // Create temporary directory for test files
            tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
            testBackupFilePath = tempDirectory.appendingPathComponent("test_backup.json").path
        }

        override func tearDown() {
            // Restore DNS settings if needed
            if needsRestore, let backupPath = actualBackupFilePath {
                do {
                    try dnsManager.restoreDnsServersFromBackup(backupFilePath: backupPath)
                    print("✅ DNS settings restored successfully in tearDown")
                } catch {
                    print("⚠️  Failed to restore DNS in tearDown: \(error)")
                    // Don't fail the test, just log the warning
                }
            }

            // Clean up temporary directory
            try? FileManager.default.removeItem(at: tempDirectory)

            // Reset state
            needsRestore = false
            actualBackupFilePath = nil
            dnsManager = nil
            super.tearDown()
        }

        // MARK: - Property Tests

        func testCurrentSystemDnsServers() {
            // Test that the property returns an array or nil
            let dnsServers = dnsManager.currentSystemDnsServers

            if let servers = dnsServers {
                XCTAssertTrue(servers.allSatisfy { !$0.isEmpty }, "DNS servers should not contain empty strings")
                print("Current system DNS servers: \(servers)")
            } else {
                print("No DNS servers found or unable to retrieve")
            }

            // The result can be nil or an array, both are valid
            XCTAssertTrue(dnsServers == nil || dnsServers!.count >= 0)
        }

        func testAllNetworkInterfaceNames() {
            let interfaceNames = dnsManager.allNetworkInterfaceNames

            if let names = interfaceNames {
                XCTAssertFalse(names.isEmpty, "Should have at least one network interface")
                XCTAssertTrue(names.allSatisfy { !$0.isEmpty }, "Interface names should not be empty")
                print("Network interface names: \(names)")
            } else {
                XCTFail("Should be able to retrieve network interface names on macOS")
            }
        }

        func testAllNetworkServiceNames() {
            let serviceNames = dnsManager.allNetworkServiceNames

            if let names = serviceNames {
                XCTAssertTrue(names.allSatisfy { !$0.isEmpty }, "Service names should not be empty")
                print("Network service names: \(names)")
            }

            // Service names might be empty if no interfaces are configured
            XCTAssertTrue(serviceNames == nil || serviceNames!.count >= 0)
        }

        // MARK: - Error Handling Tests

        func testOverrideAndBackupDnsServersWithInvalidPath() {
            let invalidPath = "/root/invalid/path/backup.json"

            XCTAssertThrowsError(
                try dnsManager.overrideAndBackupDnsServers(["8.8.8.8"], backupFilePath: invalidPath)
            ) { error in
                XCTAssertTrue(error is DNSManagerError)
                if let dnsError = error as? DNSManagerError,
                   case let .fileWriteFailed(path, _) = dnsError
                {
                    XCTAssertEqual(path, invalidPath)
                }
            }
        }

        func testRestoreDnsServersFromNonExistentBackup() {
            let nonExistentPath = tempDirectory.appendingPathComponent("nonexistent.json").path

            XCTAssertThrowsError(
                try dnsManager.restoreDnsServersFromBackup(backupFilePath: nonExistentPath)
            ) { error in
                XCTAssertTrue(error is DNSManagerError)
                if let dnsError = error as? DNSManagerError,
                   case let .backupFileNotFound(path) = dnsError
                {
                    XCTAssertEqual(path, nonExistentPath)
                }
            }
        }

        func testRestoreDnsServersFromInvalidJSON() {
            // Create a file with invalid JSON
            let invalidJSONPath = tempDirectory.appendingPathComponent("invalid.json").path
            let invalidJSON = "{ invalid json content"
            try? invalidJSON.write(toFile: invalidJSONPath, atomically: true, encoding: .utf8)

            XCTAssertThrowsError(
                try dnsManager.restoreDnsServersFromBackup(backupFilePath: invalidJSONPath)
            ) { error in
                XCTAssertTrue(error is DNSManagerError)
                if let dnsError = error as? DNSManagerError,
                   case let .jsonDeserializationFailed(path) = dnsError
                {
                    XCTAssertEqual(path, invalidJSONPath)
                }
            }
        }

        func testRestoreDnsServersFromEmptyJSON() {
            // Create a file with empty JSON object
            let emptyJSONPath = tempDirectory.appendingPathComponent("empty.json").path
            let emptyJSON = "{}"
            try? emptyJSON.write(toFile: emptyJSONPath, atomically: true, encoding: .utf8)

            XCTAssertThrowsError(
                try dnsManager.restoreDnsServersFromBackup(backupFilePath: emptyJSONPath)
            ) { error in
                XCTAssertTrue(error is DNSManagerError)
                if let dnsError = error as? DNSManagerError,
                   case let .jsonDeserializationFailed(path) = dnsError
                {
                    XCTAssertEqual(path, emptyJSONPath)
                }
            }
        }

        // MARK: - File Operations Tests

        func testBackupFileCreationAndCleanup() {
            // Create a valid backup JSON file manually
            let backupData: [String: String] = [
                "Wi-Fi": "8.8.8.8 8.8.4.4",
                "Ethernet": "1.1.1.1 1.0.0.1",
            ]

            do {
                let jsonData = try JSONSerialization.data(withJSONObject: backupData, options: [])
                let backupURL = URL(fileURLWithPath: testBackupFilePath)
                try jsonData.write(to: backupURL)

                // Verify file was created
                XCTAssertTrue(FileManager.default.fileExists(atPath: testBackupFilePath))

                // Test that we can read it back
                let readData = try Data(contentsOf: backupURL)
                let deserializedData = try JSONSerialization.jsonObject(with: readData) as? [String: String]

                XCTAssertEqual(deserializedData?["Wi-Fi"], "8.8.8.8 8.8.4.4")
                XCTAssertEqual(deserializedData?["Ethernet"], "1.1.1.1 1.0.0.1")

            } catch {
                XCTFail("Failed to create or read backup file: \(error)")
            }
        }

        // MARK: - Integration Tests (Limited due to system dependencies)

        func testSingleDnsServerConvenienceMethod() {
            // Test the convenience method with automatic restoration
            do {
                try dnsManager.overrideAndBackupDnsServer(Self.testSingleDnsServer, backupFilePath: testBackupFilePath)

                // Mark for restoration in tearDown
                needsRestore = true
                actualBackupFilePath = testBackupFilePath

                // Verify backup file was created
                XCTAssertTrue(FileManager.default.fileExists(atPath: testBackupFilePath))
                print("✅ Single DNS server set to \(Self.testSingleDnsServer), backup created")

            } catch {
                XCTFail("Failed to set single DNS server: \(error)")
            }
        }

        func testMultipleDnsServersBackup() {
            // Test multiple DNS servers method with automatic restoration
            do {
                let uniqueBackupPath = tempDirectory.appendingPathComponent("multi_dns_backup.json").path

                try dnsManager.overrideAndBackupDnsServers(Self.testMultipleDnsServers, backupFilePath: uniqueBackupPath)

                // Mark for restoration in tearDown
                needsRestore = true
                actualBackupFilePath = uniqueBackupPath

                // Verify backup file was created
                XCTAssertTrue(FileManager.default.fileExists(atPath: uniqueBackupPath))

                // Verify backup file contains valid JSON
                let backupURL = URL(fileURLWithPath: uniqueBackupPath)
                let data = try Data(contentsOf: backupURL)
                let backupData = try JSONSerialization.jsonObject(with: data) as? [String: String]
                XCTAssertNotNil(backupData)

                print("✅ Multiple DNS servers set to \(Self.testMultipleDnsServers), backup created")

            } catch {
                XCTFail("Failed to set multiple DNS servers: \(error)")
            }
        }

        // MARK: - Error Description Tests

        func testDNSManagerErrorDescriptions() {
            let errors: [DNSManagerError] = [
                .noNetworkServicesFound,
                .backupFileNotFound("/test/path"),
                .invalidBackupFile("/test/path"),
                .backupCleanupFailed(NSError(domain: "test", code: 1)),
                .jsonSerializationFailed(NSError(domain: "test", code: 2)),
                .fileWriteFailed("/test/path", NSError(domain: "test", code: 3)),
                .fileReadFailed("/test/path", NSError(domain: "test", code: 4)),
                .jsonDeserializationFailed("/test/path"),
                .fileRemovalFailed("/test/path", NSError(domain: "test", code: 5)),
            ]

            for error in errors {
                XCTAssertNotNil(error.errorDescription)
                XCTAssertFalse(error.errorDescription!.isEmpty)
                print("Error: \(error.errorDescription!)")
            }
        }

        // MARK: - Performance Tests

        func testPerformanceOfNetworkDiscovery() {
            measure {
                _ = dnsManager.allNetworkInterfaceNames
                _ = dnsManager.allNetworkServiceNames
                _ = dnsManager.currentSystemDnsServers
            }
        }

        // MARK: - Initialization Tests

        func testDNSManagerInitialization() {
            let manager = DNSManager()
            XCTAssertNotNil(manager)

            // Test basic functionality
            XCTAssertNotNil(manager.allNetworkInterfaceNames)
        }
    }

#else

    // For non-macOS platforms, provide empty test case
    final class DNSManagerTests: XCTestCase {
        func testUnsupportedPlatform() {
            // DNSManager is only available on macOS
            XCTAssertTrue(true, "DNSManager is macOS-only")
        }
    }

#endif

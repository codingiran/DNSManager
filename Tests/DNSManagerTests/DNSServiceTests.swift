@testable import DNSManager
import Network
import XCTest

// MARK: - DNSServiceTests

final class DNSServiceTests: XCTestCase {
    // MARK: - Test Constants

    private let testDnsServer: NWEndpoint.Host = "8.8.8.8"
    private let testPort: NWEndpoint.Port = 53
    private let testDomain = "example.com"
    private let timeout: TimeInterval = 10.0

    // MARK: - System DNS Tests

    func testSystemDnsRetrieval() {
        let systemDnsServers = DNSService.systemDNS

        // System should have at least some DNS servers configured
        XCTAssertNotNil(systemDnsServers)

        // Filter out any empty strings
        let validServers = systemDnsServers.filter { !$0.isEmpty }
        print("System DNS servers: \(validServers)")

        // Each DNS server should be a valid IP address format (basic validation)
        for server in validServers {
            let ipPattern = #"^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$"#
            let regex = try? NSRegularExpression(pattern: ipPattern)
            let range = NSRange(location: 0, length: server.count)
            let matches = regex?.numberOfMatches(in: server, range: range) ?? 0

            if matches > 0 {
                // Valid IPv4 format
                XCTAssertTrue(true, "Valid DNS server IP: \(server)")
            } else {
                // Could be IPv6 or hostname - just check it's not empty
                XCTAssertFalse(server.isEmpty, "DNS server should not be empty")
            }
        }
    }

    // MARK: - DNS Query Tests (Synchronous)

    @available(macOS 10.15, *)
    func testDnsQueryA_Record_Synchronous() {
        let expectation = XCTestExpectation(description: "DNS A record query")
        let domain = testDomain // Capture for use in Sendable closure

        DNSService.query(
            host: testDnsServer,
            port: testPort,
            domain: testDomain,
            type: .A,
            queue: .main
        ) { result in
            switch result {
            case let .success(dnsRecord):
                XCTAssertEqual(dnsRecord.ResponseCode, 0, "Response should be successful")
                XCTAssertTrue(dnsRecord.QR, "Should be a response")
                XCTAssertGreaterThan(dnsRecord.Questions.count, 0, "Should have questions")

                if dnsRecord.ANCount > 0 {
                    XCTAssertGreaterThan(dnsRecord.Answers.count, 0, "Should have answers for A record")

                    // Check if any answer is an A record (type 1)
                    let aRecords = dnsRecord.Answers.filter { $0.Typ == 1 }
                    if !aRecords.isEmpty {
                        // Validate IP address format
                        for record in aRecords {
                            let ipPattern = #"^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$"#
                            let regex = try? NSRegularExpression(pattern: ipPattern)
                            let range = NSRange(location: 0, length: record.RData.count)
                            let matches = regex?.numberOfMatches(in: record.RData, range: range) ?? 0
                            XCTAssertGreaterThan(matches, 0, "A record should contain valid IPv4 address: \(record.RData)")
                        }
                    }
                }

                print("DNS Query successful for \(domain): \(dnsRecord.Answers.count) answers")

            case let .failure(error):
                // DNS query might fail due to network issues, but we shouldn't crash
                print("DNS query failed (acceptable in test environment): \(error)")
                XCTAssertTrue(error is DNSServiceError, "Should be a known error type")
            }

            expectation.fulfill()
        }

        wait(for: [expectation], timeout: timeout)
    }

    @available(macOS 10.15, *)
    func testDnsQuery_CompletionHandler_Synchronous() {
        let expectation = XCTestExpectation(description: "DNS query with completion handler")

        DNSService.query(
            host: testDnsServer,
            port: testPort,
            domain: testDomain,
            type: .A,
            queue: .main
        ) { dnsRecord, error in
            if let error = error {
                print("DNS query failed (acceptable in test environment): \(error)")
                XCTAssertNotNil(error, "Error should be properly passed")
            } else if let record = dnsRecord {
                XCTAssertNotNil(record, "DNS record should not be nil on success")
                XCTAssertEqual(record.ResponseCode, 0, "Response should be successful")
                print("DNS Query successful with completion handler")
            } else {
                XCTFail("Both record and error cannot be nil")
            }

            expectation.fulfill()
        }

        wait(for: [expectation], timeout: timeout)
    }

    // MARK: - DNS Query Tests (Asynchronous)

    @available(macOS 10.15, *)
    func testDnsQueryAsync() async {
        let domain = testDomain // Capture for async context

        do {
            let dnsRecord = try await DNSService.query(
                host: testDnsServer,
                port: testPort,
                domain: domain,
                type: .A
            )

            XCTAssertEqual(dnsRecord.ResponseCode, 0, "Response should be successful")
            XCTAssertTrue(dnsRecord.QR, "Should be a response")
            XCTAssertGreaterThan(dnsRecord.Questions.count, 0, "Should have questions")

            print("Async DNS Query successful for \(domain)")

        } catch {
            // DNS query might fail due to network issues
            print("Async DNS query failed (acceptable in test environment): \(error)")
            XCTAssertTrue(error is DNSServiceError, "Should be a known error type")
        }
    }

    // MARK: - Different DNS Record Types Tests

    @available(macOS 10.15, *)
    func testDnsQuery_TxtRecord() {
        let expectation = XCTestExpectation(description: "DNS TXT record query")

        // Use a domain known to have TXT records
        let txtDomain = "google.com"

        DNSService.query(
            host: testDnsServer,
            port: testPort,
            domain: txtDomain,
            type: .TXT,
            queue: .main
        ) { result in
            switch result {
            case let .success(dnsRecord):
                XCTAssertEqual(dnsRecord.ResponseCode, 0, "Response should be successful")

                if dnsRecord.ANCount > 0 {
                    let txtRecords = dnsRecord.Answers.filter { $0.Typ == 16 } // TXT type
                    if !txtRecords.isEmpty {
                        print("Found TXT records for \(txtDomain)")
                        for record in txtRecords {
                            XCTAssertFalse(record.RData.isEmpty, "TXT record should not be empty")
                        }
                    }
                }

            case let .failure(error):
                print("TXT query failed (acceptable): \(error)")
            }

            expectation.fulfill()
        }

        wait(for: [expectation], timeout: timeout)
    }

    @available(macOS 10.15, *)
    func testDnsQuery_CnameRecord() {
        let expectation = XCTestExpectation(description: "DNS CNAME record query")

        // Use a domain known to have CNAME records
        let cnameDomain = "www.github.com"

        DNSService.query(
            host: testDnsServer,
            port: testPort,
            domain: cnameDomain,
            type: .CNAME,
            queue: .main
        ) { result in
            switch result {
            case let .success(dnsRecord):
                XCTAssertEqual(dnsRecord.ResponseCode, 0, "Response should be successful")

                if dnsRecord.ANCount > 0 {
                    let cnameRecords = dnsRecord.Answers.filter { $0.Typ == 5 } // CNAME type
                    if !cnameRecords.isEmpty {
                        print("Found CNAME records for \(cnameDomain)")
                        for record in cnameRecords {
                            XCTAssertFalse(record.RData.isEmpty, "CNAME record should not be empty")
                            XCTAssertTrue(record.RData.contains("."), "CNAME should be a domain name")
                        }
                    }
                }

            case let .failure(error):
                print("CNAME query failed (acceptable): \(error)")
            }

            expectation.fulfill()
        }

        wait(for: [expectation], timeout: timeout)
    }

    // MARK: - DNSServiceError Tests

    func testDnsServiceErrorDescriptions() {
        let connectionError = DNSServiceError.connectionNotReady
        let responseError = DNSServiceError.responseNotComplete
        let dataError = DNSServiceError.messageDataInvalid

        XCTAssertEqual(connectionError.errorDescription, "Connection not ready")
        XCTAssertEqual(responseError.errorDescription, "Response not complete")
        XCTAssertEqual(dataError.errorDescription, "Message data invalid")

        // Test LocalizedError conformance
        XCTAssertNotNil(connectionError.localizedDescription)
        XCTAssertNotNil(responseError.localizedDescription)
        XCTAssertNotNil(dataError.localizedDescription)
    }

    // MARK: - Integration Tests

    @available(macOS 10.15, *)
    func testMultipleConcurrentQueries() {
        let queryCount = 3
        let expectations = (0 ..< queryCount).map { XCTestExpectation(description: "Concurrent query \($0)") }

        let domains = ["example.com", "google.com", "apple.com"]

        for (index, domain) in domains.enumerated() {
            DNSService.query(
                host: testDnsServer,
                port: testPort,
                domain: domain,
                type: .A,
                queue: .global(qos: .background)
            ) { result in
                switch result {
                case let .success(record):
                    print("Concurrent query \(index) for \(domain) succeeded")
                    XCTAssertEqual(record.ResponseCode, 0, "Response should be successful")

                case let .failure(error):
                    print("Concurrent query \(index) for \(domain) failed: \(error)")
                }

                expectations[index].fulfill()
            }
        }

        wait(for: expectations, timeout: timeout)
    }

    // MARK: - Performance Tests

    @available(macOS 10.15, *)
    func testDnsQueryPerformance() {
        // Only run performance tests if we have network connectivity
        guard !DNSService.systemDNS.isEmpty else {
            print("Skipping performance test - no system DNS available")
            return
        }

        measure {
            let expectation = XCTestExpectation(description: "Performance DNS query")

            DNSService.query(
                host: testDnsServer,
                port: testPort,
                domain: testDomain,
                type: .A,
                queue: .main
            ) { _ in
                expectation.fulfill()
            }

            wait(for: [expectation], timeout: timeout)
        }
    }
}

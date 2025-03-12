@testable import DNSManager
import XCTest

final class DNSManagerTests: XCTestCase {
    func testExample() throws {
        // XCTest Documentation
        // https://developer.apple.com/documentation/xctest

        // Defining Test Cases and Test Methods
        // https://developer.apple.com/documentation/xctest/defining_test_cases_and_test_methods
    }

    func testDNS() async throws {
        do {
            let result = try await DNSService.query(domain: "www.apple.com")
            print(result)
        } catch {
            print(error)
        }
    }
}

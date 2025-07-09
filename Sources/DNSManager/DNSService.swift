//
//  DNSService.swift
//  DNSManager
//
//  Created by CodingIran on 2022/11/11.
//

import Foundation
import Network

enum DNSServiceError: LocalizedError, Sendable {
    case connectionNotReady
    case responseNotComplete
    case messageDataInvalid

    var errorDescription: String? {
        switch self {
        case .connectionNotReady:
            return "Connection not ready"
        case .responseNotComplete:
            return "Response not complete"
        case .messageDataInvalid:
            return "Message data invalid"
        }
    }
}

// https://developer.apple.com/documentation/network
@available(macOS 10.15, *)
@available(iOS 13, *)
public class DNSService: @unchecked Sendable {
    public static func query(host: NWEndpoint.Host = "8.8.8.8",
                             port: NWEndpoint.Port = 53,
                             domain: String,
                             type: DNSType = .A,
                             queue: DispatchQueue,
                             completion: @escaping @Sendable (Result<DNSRR, Swift.Error>) -> Void)
    {
        let connection = NWConnection(host: host, port: port, using: .udp)

        connection.stateUpdateHandler = { [weak connection] newState in
            guard let connection else { return }
            switch newState {
            case .ready:
                let q = DNSQuestion(Domain: domain, Typ: type.rawValue, Class: 0x1)
                let query = DNSRR(ID: 0xAAAA, RD: true, Questions: [q])
                connection.send(content: query.serialize(), completion: .contentProcessed { [weak connection] error in
                    guard let error else {
                        // no error, will callback to receiveMessage
                        return
                    }
                    cancel(connection)
                    completion(.failure(error))
                })
                connection.receiveMessage { [weak connection] data, _, isComplete, error in
                    defer {
                        cancel(connection)
                    }
                    if let error {
                        completion(.failure(error))
                        return
                    }
                    guard isComplete else {
                        // TODO: handle not complete response
                        completion(.failure(DNSServiceError.responseNotComplete))
                        return
                    }
                    guard let data else {
                        completion(.failure(DNSServiceError.messageDataInvalid))
                        return
                    }
                    let rr = DNSRR.deserialize(data: [UInt8](data))
                    completion(.success(rr))
                }
            case let .failed(error):
                cancel(connection)
                completion(.failure(error))
            case .cancelled:
                #if DEBUG
                    print("cancelled")
                #endif
            case .setup:
                #if DEBUG
                    print("setup")
                #endif
            case .preparing:
                #if DEBUG
                    print("preparing")
                #endif
            default:
                #if DEBUG
                    print("waiting")
                #endif
            }
        }
        connection.start(queue: queue)
    }

    public static func query(host: NWEndpoint.Host = "8.8.8.8",
                             port: NWEndpoint.Port = 53,
                             domain: String,
                             type: DNSType = .A,
                             queue: DispatchQueue,
                             completion: @escaping @Sendable (DNSRR?, Error?) -> Void)
    {
        query(host: host, port: port, domain: domain, type: type, queue: queue) { result in
            switch result {
            case let .success(rr):
                completion(rr, nil)
            case let .failure(error):
                completion(nil, error)
            }
        }
    }

    private static func cancel(_ connection: NWConnection?) {
        connection?.stateUpdateHandler = nil
        connection?.cancel()
    }
}

#if canImport(_Concurrency)

    public extension DNSService {
        private static let dispatchQueue = DispatchQueue(label: "com.codingiran.DNSManager")

        static func query(host: NWEndpoint.Host = "8.8.8.8",
                          port: NWEndpoint.Port = 53,
                          domain: String,
                          type: DNSType = .A) async throws -> DNSRR
        {
            return try await withCheckedThrowingContinuation { cont in
                self.query(host: host, port: port, domain: domain, type: type, queue: dispatchQueue) { result in
                    switch result {
                    case let .success(rr):
                        cont.resume(returning: rr)
                    case let .failure(error):
                        cont.resume(throwing: error)
                    }
                }
            }
        }
    }

#endif

#if compiler(>=6.0)
    private import SystemDNS
#else
    @_implementationOnly import SystemDNS
#endif

public extension DNSService {
    static var systemDNS: [String] {
        SystemDNS.getServers()
    }
}

//
//  DNS.swift
//  DNSManager
//
//  Created by CodingIran on 2022/11/11.
//

import Foundation
import Network

enum DNSServiceError: LocalizedError {
    case connectionNotReady
    case responseNotComplete
    
    var errorDescription: String? {
        switch self {
        case .connectionNotReady:
            return "Connection not ready"
        case .responseNotComplete:
            return "Response not complete"
        }
    }
}

// https://developer.apple.com/documentation/network
@available(macOS 10.15, *)
@available(iOS 13, *)
public class DNSService {
    public static func query(host: NWEndpoint.Host = "8.8.8.8", port: NWEndpoint.Port = 53, domain: String, type: DNSType = .A, queue: DispatchQueue, completion: @escaping (DNSRR?, Error?) -> Void) {
        let connection = NWConnection(host: host, port: port, using: .udp)
        
        connection.stateUpdateHandler = { newState in
            switch newState {
            case .ready:
                let q = DNSQuestion(Domain: domain, Typ: type.rawValue, Class: 0x1)
                let query = DNSRR(ID: 0xAAAA, RD: true, Questions: [q])
                connection.send(content: query.serialize(), completion: NWConnection.SendCompletion.contentProcessed { error in
                    if error != nil {
                        connection.stateUpdateHandler = nil
                        connection.cancel()
                        completion(nil, error)
                    }
                })
                
                connection.receiveMessage { data, _, isComplete, error in
                    if error != nil {
                        connection.stateUpdateHandler = nil
                        connection.cancel()
                        completion(nil, error)
                        return
                    }
                    
                    if !isComplete {
                        connection.stateUpdateHandler = nil
                        connection.cancel()
                        // TODO: handle not complete response
                        completion(nil, DNSServiceError.responseNotComplete)
                        return
                    }
                    
                    let rr = DNSRR.deserialize(data: [UInt8](data!))
                    connection.stateUpdateHandler = nil
                    connection.cancel()
                    completion(rr, nil)
                }
                
            case .cancelled:
                print("cancelled")
            case .setup:
                print("setup")
            case .preparing:
                print("preparing")
            default:
                print("waiting")
            }
        }
        
        connection.start(queue: queue)
    }
}

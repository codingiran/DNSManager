# DNSManager

A Swift package for managing DNS settings and performing DNS queries on macOS systems.

## Features

- DNS Settings Management
  - Take over system DNS settings
  - Restore original DNS configurations
  - Backup and restore DNS settings
- DNS Query Support
  - Perform DNS queries using UDP
  - Support for different DNS record types (A, CNAME, TXT, etc.)
  - Async/await support for modern Swift applications

## Requirements

- macOS 10.15 or later

## Installation

### Swift Package Manager

Add the following to your `Package.swift` file:

```swift
dependencies: [
    .package(url: "https://github.com/yourusername/DNSManager.git", from: "1.0.0")
]
```

## Usage

### DNS Query Support 

```swift
import DNSManager
// Create a DNS query
DNSService.query(host: "8.8.8.8", // DNS server (default: 8.8.8.8)
port: 53, // DNS port (default: 53)
domain: "example.com",
type: .A, // DNS record type (default: A)
)   
```

### DNS Settings Management

```swift
let dnsManager = DNSManager()
// Take over system DNS settings
dnsManager.takeOverSystemDNS()
// Restore original DNS settings
dnsManager.restoreOriginalDNS()
// Backup DNS settings
dnsManager.backupDNS()
// Restore DNS settings
dnsManager.restoreDNS()
```

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

## Author

codingiran@gmail.com

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
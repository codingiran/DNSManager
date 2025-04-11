//
//  SystemDNS.h
//  DNSManager
//
//  Created by CodingIran on 2025/4/11.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SystemDNS : NSObject

+ (NSArray<NSString *> *)getSystemDnsServers;

@end

NS_ASSUME_NONNULL_END

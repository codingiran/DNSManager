//
//  SystemDNS.m
//  DNSManager
//
//  Created by CodingIran on 2025/4/11.
//

#import <Foundation/Foundation.h>
#import <resolv.h>
#include <arpa/inet.h>
#import "SystemDNS.h"

@implementation SystemDNS

+ (NSArray<NSString *> *)getSystemDnsServers {
    res_state res = malloc(sizeof(struct __res_state));
    int result = res_ninit(res);
    
    NSMutableArray<NSString *> *servers = [[NSMutableArray alloc] init];
    if (result == 0) {
        union res_9_sockaddr_union *addr_union = malloc(res->nscount * sizeof(union res_9_sockaddr_union));
        res_getservers(res, addr_union, res->nscount);
        
        for (int i = 0; i < res->nscount; i++) {
            if (addr_union[i].sin.sin_family == AF_INET) {
                char ip[INET_ADDRSTRLEN];
                inet_ntop(AF_INET, &(addr_union[i].sin.sin_addr), ip, INET_ADDRSTRLEN);
                NSString *dnsIP = [NSString stringWithUTF8String:ip];
                [servers addObject:dnsIP];
            } else if (addr_union[i].sin6.sin6_family == AF_INET6) {
                char ip[INET6_ADDRSTRLEN];
                inet_ntop(AF_INET6, &(addr_union[i].sin6.sin6_addr), ip, INET6_ADDRSTRLEN);
                NSString *dnsIP = [NSString stringWithUTF8String:ip];
                [servers addObject:dnsIP];
            }
        }
    }
    res_nclose(res);
    free(res);
    
    return [NSArray arrayWithArray:servers];
}

@end

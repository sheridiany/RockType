#import <Foundation/Foundation.h>
#import "RoarkTIdentifiers.h"

NS_ASSUME_NONNULL_BEGIN

// Translation service interface. Callers are authenticated by code signature;
// see docs/architecture.md "XPC 鉴权" for who may call what.
@protocol RoarkTTranslationXPCProtocol
// Health check used by M0 to prove the authenticated round trip.
- (void)pingWithReply:(void (^)(NSString *serviceVersion))reply
    NS_SWIFT_NAME(ping(reply:));
@end

NS_ASSUME_NONNULL_END

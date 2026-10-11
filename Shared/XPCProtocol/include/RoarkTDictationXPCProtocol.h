#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Direct, authenticated helper -> input method connection. No audio crosses it.
@protocol RoarkTDictationXPCProtocol
- (void)captureForApplicationPID:(int32_t)pid
                     withReply:(void (^)(NSString * _Nullable ticket, NSString * _Nullable applicationID))reply
    NS_SWIFT_NAME(capture(applicationPID:withReply:));
- (void)commitTicket:(NSString *)ticket text:(NSString *)text deadline:(NSTimeInterval)deadline
          withReply:(void (^)(BOOL accepted))reply
    NS_SWIFT_NAME(commit(ticket:text:deadline:withReply:));
- (void)cancelTicket:(NSString *)ticket NS_SWIFT_NAME(cancel(ticket:));
@end

NS_ASSUME_NONNULL_END

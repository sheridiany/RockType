#import <Foundation/Foundation.h>
#import "RoarkTDictationXPCProtocol.h"
#import "RoarkTIdentifiers.h"

NS_ASSUME_NONNULL_BEGIN

@protocol RoarkTTranslationXPCProtocol
// v2 only: a versioned string-only payload. Input method callers only.
- (void)translateCandidateWithSessionID:(NSString *)sessionID
                            generation:(int64_t)generation
                               request:(NSDictionary<NSString *, NSString *> *)request
                             withReply:(void (^)(int64_t generation,
                                                 NSString * _Nullable direction,
                                                 NSString * _Nullable translatedSource,
                                                 NSString * _Nullable translatedText,
                                                 NSError * _Nullable error))reply
    NS_SWIFT_NAME(translateCandidate(sessionID:generation:request:withReply:));

- (void)cancelWithSessionID:(NSString *)sessionID
          throughGeneration:(int64_t)generation
    NS_SWIFT_NAME(cancel(sessionID:throughGeneration:));

- (void)recordControllerInput;

- (void)controllerInputGenerationWithReply:(void (^)(int64_t generation,
                                                       NSError * _Nullable error))reply
    NS_SWIFT_NAME(controllerInputGeneration(reply:));

// Rendezvous only: registration is input-method-only, discovery main-app-only.
- (void)registerDictationEndpoint:(NSXPCListenerEndpoint *)endpoint;
- (void)dictationEndpointWithReply:(void (^)(NSXPCListenerEndpoint * _Nullable endpoint))reply
    NS_SWIFT_NAME(dictationEndpoint(reply:));
// Main App only. Unauthorized connections are invalidated.
- (void)pingWithReply:(void (^)(NSString *serviceVersion))reply
    NS_SWIFT_NAME(ping(reply:));
@end

// Main App text operations use a separate required interface. Candidate clients
// retain their narrow protocol and cannot call these methods by role checks.
@protocol RoarkTTextTranslationXPCProtocol <RoarkTTranslationXPCProtocol>
- (void)translateTextWithSessionID:(NSString *)sessionID
                       generation:(int64_t)generation
                             text:(NSString *)text
                           target:(NSString *)target
                        withReply:(void (^)(int64_t generation,
                                            NSString * _Nullable translatedText,
                                            NSError * _Nullable error))reply
    NS_SWIFT_NAME(translateText(sessionID:generation:text:target:withReply:));

- (void)cancelTextWithSessionID:(NSString *)sessionID
            throughGeneration:(int64_t)generation
    NS_SWIFT_NAME(cancelText(sessionID:throughGeneration:));
@end

NS_ASSUME_NONNULL_END

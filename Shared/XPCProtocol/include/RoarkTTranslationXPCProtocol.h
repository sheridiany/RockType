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

// Explicit input AI uses the same authenticated listener. Existing narrow clients
// may keep their interface; E-3 clients select this interface to call rewrite.
@protocol RoarkTInputAIXPCProtocol <RoarkTTextTranslationXPCProtocol>
// Main App only. Empty dictionary revokes configuration and in-flight requests.
// Required string keys: baseURL, model, apiKey, timeout (seconds, 0.1...120),
// rewritePrompt, polishPrompt, translatePrompt. Prompts use {{target}};
// the service appends the source. Memory-only; revoked on owner disconnect.
- (void)configureAI:(NSDictionary<NSString *, NSString *> *)config
         withReply:(void (^)(NSError * _Nullable error))reply
    NS_SWIFT_NAME(configureAI(config:withReply:));
// Input method only. action: rewrite | polish | translate. The caller must reject
// Secure Input AND password focus before sending, and compare generation/source
// to its current snapshot before showing or committing the result. cancel above
// cancels both ordinary translation and explicit AI for this connection/session.
- (void)rewriteCandidateWithSessionID:(NSString *)sessionID
                          generation:(int64_t)generation
                                text:(NSString *)text
                              action:(NSString *)action
                           withReply:(void (^)(int64_t generation,
                                               NSString * _Nullable source,
                                               NSString * _Nullable result,
                                               NSError * _Nullable error))reply
    NS_SWIFT_NAME(rewriteCandidate(sessionID:generation:text:action:withReply:));
@end

// NSError domain is the existing translation error domain. Input-AI codes:
// 100 invalid request/config, 101 not configured, 102 stale, 103 cancelled,
// 104 unauthorized, 105 Secure Input, 106 timeout, 107 authentication,
// 108 model unavailable, 109 rate limited, 110 network, 111 invalid response,
// 112 session capacity. Error userInfo never contains source or provider body.
NS_ASSUME_NONNULL_END

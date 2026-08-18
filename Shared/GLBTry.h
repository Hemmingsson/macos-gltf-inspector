#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef __cplusplus
extern "C" {
#endif

/// Runs `block` inside `@try/@catch` so Objective-C exceptions do not abort the process.
/// Returns YES on success. On NSException, fills `outError` (domain `GLBPreview`, code 1023)
/// with the exception reason and returns NO.
FOUNDATION_EXPORT BOOL GLBTry(void (^NS_NOESCAPE block)(void), NSError *_Nullable *_Nullable outError)
    NS_SWIFT_NAME(GLBCatchNSException(_:error:));

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END

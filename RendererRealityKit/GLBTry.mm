#import "GLBTry.h"

BOOL GLBTry(void (^NS_NOESCAPE block)(void), NSError *_Nullable *_Nullable outError) {
    @try {
        if (block) {
            block();
        }
        return YES;
    } @catch (NSException *exception) {
        if (outError != NULL) {
            NSString *reason = exception.reason;
            if (reason.length == 0) {
                reason = exception.name;
            }
            if (reason.length == 0) {
                reason = @"Unknown exception";
            }
            *outError = [NSError errorWithDomain:@"lol.mattias.gltf-inspector"
                                            code:1023
                                        userInfo:@{NSLocalizedDescriptionKey: reason}];
        }
        return NO;
    }
}

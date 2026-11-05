#import <Foundation/Foundation.h>
FOUNDATION_EXPORT void ActivationAccountFrame(void);
FOUNDATION_EXPORT BOOL ActivationAccessActive(void);
FOUNDATION_EXPORT void ActivationShowLogin(void);
FOUNDATION_EXPORT void ActivationFillExpiryParts(void *result);
FOUNDATION_EXPORT void ActivationSyncUsername(void *target,void(*assign)(void*,const char*,size_t));

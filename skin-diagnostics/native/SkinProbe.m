#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <dlfcn.h>
#include <stdint.h>

static UIButton *ProbeButton;
static BOOL ProbeBusy;
static UIWindow *HostWindow(void) {
    UIWindow *best=nil;
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if (![s isKindOfClass:UIWindowScene.class] || s.activationState!=UISceneActivationStateForegroundActive) continue;
        for (UIWindow *w in ((UIWindowScene *)s).windows) {
            if (w.hidden || w.alpha<0.1 || !w.rootViewController) continue;
            if (!best || w.windowLevel>best.windowLevel || (w.windowLevel==best.windowLevel && w.isKeyWindow)) best=w;
        }
    }
    return best;
}
static UIViewController *TopController(UIWindow *w) {
    UIViewController *v=w.rootViewController;
    while (v.presentedViewController && !v.presentedViewController.isBeingDismissed) v=v.presentedViewController;
    return v;
}
static BOOL RelevantClass(NSString *name) {
    static NSSet *wanted;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ wanted=[NSSet setWithArray:@[@"UserInfo",@"LocalPoolPlayer",@"CueWidget",@"VisualCue",@"MainManager",@"GameHUDTwoPlayerGame",@"MatchScreenPlayerWidget",@"PlayerAvatar",@"AvatarWidget"]]; });
    return [wanted containsObject:name];
}
static void InspectMethods(Class cls, BOOL meta, BOOL includeAll, NSMutableArray *out) {
    unsigned count=0;
    Method *methods=class_copyMethodList(meta?object_getClass(cls):cls,&count);
    for (unsigned i=0;i<count;i++) {
        IMP imp=method_getImplementation(methods[i]);
        Dl_info info={0};
        BOOL found=dladdr((const void *)imp,&info)!=0;
        NSString *module=found&&info.dli_fname?[@(info.dli_fname) lastPathComponent]:@"unknown";
        BOOL donor=[module isEqualToString:@"libswiftCoreImage.dylib"];
        BOOL current=[module isEqualToString:@"ninja"];
        if (!includeAll && !donor && !current) continue;
        uintptr_t relative=found?(uintptr_t)imp-(uintptr_t)info.dli_fbase:0;
        [out addObject:@{@"class":@(class_getName(cls)),@"method":@(sel_getName(method_getName(methods[i]))),@"classMethod":@(meta),@"types":@(method_getTypeEncoding(methods[i])?:""),@"implementationModule":module,@"relativeOffset":[NSString stringWithFormat:@"0x%llx",(unsigned long long)relative],@"donorImplementation":@(donor)}];
    }
    free(methods);
}
static NSDictionary *Collect(void) {
    unsigned count=0;
    Class __unsafe_unretained *classes=objc_copyClassList(&count);
    NSMutableArray *methods=[NSMutableArray array],*present=[NSMutableArray array];
    for (unsigned i=0;i<count;i++) {
        NSString *name=@(class_getName(classes[i]));
        BOOL relevant=RelevantClass(name);
        if (relevant) [present addObject:name];
        InspectMethods(classes[i],NO,relevant,methods);
        InspectMethods(classes[i],YES,relevant,methods);
    }
    free(classes);
    NSUInteger donorCount=0;
    for (NSDictionary *m in methods) if ([m[@"donorImplementation"] boolValue]) donorCount++;
    return @{@"format":@"SkinProbe-1",@"scope":@"Objective-C class/method metadata only; no account values, tokens, keys, identifiers or network requests",@"appVersion":[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"]?:@"",@"appBuild":[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"]?:@"",@"knownClassesPresent":present,@"donorMethodCount":@(donorCount),@"methods":methods,@"interpretation":@"Zero donor methods can mean hooks are not initialized or not implemented through Objective-C. This report does not activate Skins."};
}
@interface SkinProbeAction : NSObject
+ (void)run;
@end
@implementation SkinProbeAction
+ (void)run {
    if (ProbeBusy) return;
    ProbeBusy=YES;
    ProbeButton.enabled=NO;
    [ProbeButton setTitle:@"جارِ الفحص…" forState:UIControlStateNormal];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
        @autoreleasepool {
            NSDictionary *report=Collect();
            NSError *error=nil;
            NSData *data=[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:&error];
            NSURL *dir=[NSFileManager.defaultManager URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].firstObject;
            NSURL *file=[dir URLByAppendingPathComponent:@"SkinProbe-report.json"];
            BOOL saved=data && [data writeToURL:file options:NSDataWritingAtomic error:&error];
            NSString *message=error.localizedDescription?:@"تعذر حفظ تقرير الفحص";
            dispatch_async(dispatch_get_main_queue(), ^{
                ProbeBusy=NO;
                ProbeButton.enabled=YES;
                [ProbeButton setTitle:@"فحص Skins" forState:UIControlStateNormal];
                UIWindow *w=HostWindow();
                UIViewController *v=TopController(w);
                if (!v || v.isBeingPresented) return;
                if (!saved) {
                    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"الفحص" message:message preferredStyle:UIAlertControllerStyleAlert];
                    [alert addAction:[UIAlertAction actionWithTitle:@"حسناً" style:UIAlertActionStyleDefault handler:nil]];
                    [v presentViewController:alert animated:YES completion:nil];
                    return;
                }
                UIActivityViewController *share=[[UIActivityViewController alloc] initWithActivityItems:@[file] applicationActivities:nil];
                share.popoverPresentationController.sourceView=ProbeButton;
                share.popoverPresentationController.sourceRect=ProbeButton.bounds;
                [v presentViewController:share animated:YES completion:nil];
            });
        }
    });
}
@end
static void Attach(void) {
    if (ProbeBusy) return;
    UIWindow *w=HostWindow();
    if (!w) return;
    if (!ProbeButton) {
        ProbeButton=[UIButton buttonWithType:UIButtonTypeSystem];
        [ProbeButton setTitle:@"فحص Skins" forState:UIControlStateNormal];
        ProbeButton.backgroundColor=[UIColor colorWithRed:.40 green:.16 blue:.70 alpha:.95];
        [ProbeButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        ProbeButton.titleLabel.font=[UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        ProbeButton.layer.cornerRadius=14;
        ProbeButton.accessibilityLabel=@"إنشاء تقرير تشخيص Skins";
        [ProbeButton addTarget:SkinProbeAction.class action:@selector(run) forControlEvents:UIControlEventTouchUpInside];
    }
    if (ProbeButton.superview!=w) [w addSubview:ProbeButton];
    ProbeButton.frame=CGRectMake(w.safeAreaInsets.left+12,w.safeAreaInsets.top+68,112,34);
    [w bringSubviewToFront:ProbeButton];
}
__attribute__((constructor)) static void Start(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSTimer scheduledTimerWithTimeInterval:2 repeats:YES block:^(NSTimer *timer){(void)timer;Attach();}];
    });
}

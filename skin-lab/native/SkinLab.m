#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <dlfcn.h>
#include <stdint.h>
#include <string.h>
#include <stdlib.h>

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
static BOOL LabLevelEnabled,LabCueEnabled;
static int LabLevel=100,LabLeague=105,LabCue;
static const int LabLeagues[7]={105,109,107,101,104,108,106};
static _Thread_local unsigned LocalCreationDepth;
static __weak id LastLocalWidget,LastVisualCue;
static int LastCueId,LastCueLevel;
static NSMutableSet<NSNumber *> *SeenCueIds;
static char LocalMarker,OriginalStarParameters;
static id (*OriginalLocalFactory)(id,SEL);
static void (*OriginalStar)(id,SEL,int,int);
static void (*OriginalCue)(id,SEL,int,int,BOOL);
static void (*OriginalCueSetup)(id,SEL,int,int);
static NSString *HookStatus=@"جارِ انتظار دوال الرسم";
static void ShowLab(void);
static BOOL Access(void) {
    BOOL (*active)(void)=(BOOL(*)(void))dlsym(RTLD_DEFAULT,"ActivationAccessActive");
    return !active || active();
}
static void RememberCue(int cue) {
    if (!NSThread.isMainThread || cue<0 || cue>10000000) return;
    if (!SeenCueIds) SeenCueIds=[NSMutableSet set];
    [SeenCueIds addObject:@(cue)];
}
static void RefreshAppearance(void) {
    id widget=LastLocalWidget;
    NSArray *p=widget?objc_getAssociatedObject(widget,&OriginalStarParameters):nil;
    if (widget && p.count==2 && OriginalStar) {
        BOOL on=Access()&&LabLevelEnabled;
        OriginalStar(widget,sel_registerName("setupStarWithLeague:andLevel:"),on?LabLeague:[p[0] intValue],on?LabLevel:[p[1] intValue]);
    }
    id cue=LastVisualCue;
    if (cue && OriginalCue) {
        BOOL on=Access()&&LabCueEnabled&&[SeenCueIds containsObject:@(LabCue)];
        OriginalCue(cue,sel_registerName("setCueWidgetWithCueId:cueLevel:forOpponent:"),on?LabCue:LastCueId,LastCueLevel,NO);
    }
}
static void StarReplacement(id self,SEL cmd,int league,int level) {
    BOOL local=LocalCreationDepth>0 || [objc_getAssociatedObject(self,&LocalMarker) boolValue];
    if (NSThread.isMainThread) {
        objc_setAssociatedObject(self,&OriginalStarParameters,@[@(league),@(level)],OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (local) {
            objc_setAssociatedObject(self,&LocalMarker,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            LastLocalWidget=self;
        }
    }
    BOOL on=NSThread.isMainThread&&local&&Access()&&LabLevelEnabled;
    OriginalStar(self,cmd,on?LabLeague:league,on?LabLevel:level);
}
static id LocalFactoryReplacement(id self,SEL cmd) {
    LocalCreationDepth++;
    id result=OriginalLocalFactory(self,cmd);
    LocalCreationDepth--;
    if (result && NSThread.isMainThread) {
        objc_setAssociatedObject(result,&LocalMarker,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        LastLocalWidget=result;
        RefreshAppearance();
    }
    return result;
}
static void CueReplacement(id self,SEL cmd,int cue,int level,BOOL opponent) {
    if (!opponent && NSThread.isMainThread) {
        RememberCue(cue);
        LastVisualCue=self;
        LastCueId=cue;
        LastCueLevel=level;
    }
    BOOL on=NSThread.isMainThread&&!opponent&&Access()&&LabCueEnabled&&[SeenCueIds containsObject:@(LabCue)];
    OriginalCue(self,cmd,on?LabCue:cue,level,opponent);
}
static void CueSetupReplacement(id self,SEL cmd,int cue,int level) {
    RememberCue(cue);
    OriginalCueSetup(self,cmd,cue,level);
}
static BOOL Compatible(Method method,const char *result,const char **args,unsigned count) {
    if (!method || method_getNumberOfArguments(method)!=count) return NO;
    char *type=method_copyReturnType(method);
    BOOL ok=type&&strcmp(type,result)==0;
    free(type);
    for (unsigned i=0;i<count&&ok;i++) {
        type=method_copyArgumentType(method,i);
        ok=type&&strcmp(type,args[i])==0;
        free(type);
    }
    return ok;
}
static BOOL InstallOne(const char *className,const char *methodName,BOOL meta,IMP replacement,IMP *original,const char *result,const char **args,unsigned count) {
    if (*original) return YES;
    Class cls=objc_getClass(className);
    if (!cls) return NO;
    if (meta) cls=object_getClass(cls);
    SEL selector=sel_registerName(methodName);
    Method method=class_getInstanceMethod(cls,selector);
    if (!Compatible(method,result,args,count)) return NO;
    *original=method_getImplementation(method);
    class_replaceMethod(cls,selector,replacement,method_getTypeEncoding(method));
    return YES;
}
static void InstallLab(void) {
    static BOOL complete;
    if(complete) return;
    const char *factory[]={"@",":"};
    const char *star[]={"@",":","i","i"};
    const char *cue[]={"@",":","i","i","B"};
    BOOL starOK=InstallOne("MatchScreenPlayerWidget","setupStarWithLeague:andLevel:",NO,(IMP)StarReplacement,(IMP *)&OriginalStar,"v",star,4);
    BOOL localOK=starOK&&InstallOne("MatchScreenPlayerWidget","createLocalPlayerWidget",YES,(IMP)LocalFactoryReplacement,(IMP *)&OriginalLocalFactory,"@",factory,2);
    BOOL cueOK=InstallOne("VisualCue","setCueWidgetWithCueId:cueLevel:forOpponent:",NO,(IMP)CueReplacement,(IMP *)&OriginalCue,"v",cue,5);
    InstallOne("CueWidget","setupWithCueId:cueLevel:",NO,(IMP)CueSetupReplacement,(IMP *)&OriginalCueSetup,"v",star,4);
    complete=localOK&&cueOK&&OriginalCueSetup;
    HookStatus=[NSString stringWithFormat:@"النجمة والمستوى: %@\nالعصا: %@\nالتغيير محلي في الرسم فقط. النجمة تخص بطاقة اللاعب المحلي قبل المباراة.",localOK?@"تم الربط — يحتاج تجربة":@"لم تتطابق الدوال",cueOK?@"تم الربط — يحتاج تجربة":@"لم تتطابق الدوال"];
}
static void PresentLabAlert(UIAlertController *alert) {
    UIWindow *w=HostWindow();
    UIViewController *pending=w.rootViewController;
    while(pending.presentedViewController){ if(pending.presentedViewController.isBeingDismissed){dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.35*NSEC_PER_SEC)),dispatch_get_main_queue(),^{PresentLabAlert(alert);});return;} pending=pending.presentedViewController; }
    UIViewController *top=TopController(w);
    if (!top || top.isBeingPresented) return;
    if (alert.preferredStyle==UIAlertControllerStyleActionSheet) {
        alert.popoverPresentationController.sourceView=ProbeButton;
        alert.popoverPresentationController.sourceRect=ProbeButton.bounds;
    }
    [top presentViewController:alert animated:YES completion:nil];
}
static void SaveLab(void) {
    NSUserDefaults *prefs=NSUserDefaults.standardUserDefaults;
    [prefs setBool:LabLevelEnabled forKey:@"SkinLab.LevelEnabled"];
    [prefs setInteger:LabLevel forKey:@"SkinLab.Level"];
    [prefs setInteger:LabLeague forKey:@"SkinLab.League"];
    RefreshAppearance();
}
static void PickLevel(void) {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"المستوى المعروض" message:@"رقم تجميلي من 1 إلى 999؛ لا يغيّر مستوى الحساب." preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f){f.keyboardType=UIKeyboardTypeNumberPad;f.text=[NSString stringWithFormat:@"%d",LabLevel];}];
    [a addAction:[UIAlertAction actionWithTitle:@"إلغاء" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"حفظ" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){(void)action;NSString *s=a.textFields.firstObject.text;NSCharacterSet *bad=NSCharacterSet.decimalDigitCharacterSet.invertedSet;int n=s.intValue;if(s.length>0&&[s rangeOfCharacterFromSet:bad].location==NSNotFound&&n>=1&&n<=999){LabLevel=n;SaveLab();}}]];
    PresentLabAlert(a);
}
static void PickLeague(void) {
    NSArray *labels=@[@"بنفسجي",@"سماوي",@"أخضر",@"كهرماني",@"رمادي",@"أحمر",@"أزرق"];
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"لون النجمة" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSUInteger i=0;i<labels.count;i++) {
        int league=LabLeagues[i];
        [a addAction:[UIAlertAction actionWithTitle:labels[i] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){(void)action;LabLeague=league;SaveLab();}]];
    }
    [a addAction:[UIAlertAction actionWithTitle:@"إلغاء" style:UIAlertActionStyleCancel handler:nil]];
    PresentLabAlert(a);
}
static void PickCue(void) {
    NSArray *ids=[[SeenCueIds allObjects] sortedArrayUsingSelector:@selector(compare:)];
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"اختيار شكل العصا" message:ids.count?@"هذه أرقام أشكال عُرضت على الجهاز. يمكن عرض العصي في المتجر ثم الرجوع هنا. لا يتغير امتلاك العصا أو قوتها.":@"اعرض عصيًا في اللعبة أو المتجر أولاً، ثم افتح هذه القائمة مجدداً." preferredStyle:UIAlertControllerStyleActionSheet];
    NSUInteger limit=MIN(ids.count,(NSUInteger)40);
    for (NSUInteger i=0;i<limit;i++) {
        NSNumber *number=ids[i];
        [a addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"العصا %@",number] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){(void)action;LabCue=number.intValue;LabCueEnabled=YES;RefreshAppearance();}]];
    }
    [a addAction:[UIAlertAction actionWithTitle:@"إلغاء" style:UIAlertActionStyleCancel handler:nil]];
    PresentLabAlert(a);
}
static void ExportLab(void);
static void ShowLab(void) {
    NSString *message=[NSString stringWithFormat:@"نسخة تجريبية: التغييرات بصرية على هذا الجهاز.\n%@%@",HookStatus,Access()?@"":@"\nفعّل الاشتراك أولاً."];
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Skins — تجربة" message:message preferredStyle:UIAlertControllerStyleActionSheet];
    [a addAction:[UIAlertAction actionWithTitle:LabLevelEnabled?@"تعطيل نجمة ومستوى العرض":@"تفعيل نجمة ومستوى العرض" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){(void)action;LabLevelEnabled=!LabLevelEnabled;SaveLab();}]];
    [a addAction:[UIAlertAction actionWithTitle:@"اختيار المستوى" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){(void)action;PickLevel();}]];
    [a addAction:[UIAlertAction actionWithTitle:@"اختيار لون النجمة" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){(void)action;PickLeague();}]];
    [a addAction:[UIAlertAction actionWithTitle:@"اختيار شكل العصا" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){(void)action;PickCue();}]];
    [a addAction:[UIAlertAction actionWithTitle:@"إرجاع المظهر الأصلي" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action){(void)action;LabLevelEnabled=LabCueEnabled=NO;SaveLab();}]];
    [a addAction:[UIAlertAction actionWithTitle:@"مشاركة تقرير الربط" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){(void)action;ExportLab();}]];
    [a addAction:[UIAlertAction actionWithTitle:@"إغلاق" style:UIAlertActionStyleCancel handler:nil]];
    PresentLabAlert(a);
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
    return @{@"format":@"SkinLab-1",@"scope":@"Objective-C class/method metadata only; no account values, tokens, keys, identifiers or network requests",@"appVersion":[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"]?:@"",@"appBuild":[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"]?:@"",@"knownClassesPresent":present,@"donorMethodCount":@(donorCount),@"methods":methods,@"interpretation":@"Zero donor methods can mean hooks are not initialized or not implemented through Objective-C. This report does not activate Skins."};
}
@interface SkinProbeAction : NSObject
+ (void)run;
+ (void)exportReport;
@end
@implementation SkinProbeAction
+ (void)run { ShowLab(); }
+ (void)exportReport {
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
            NSURL *file=[dir URLByAppendingPathComponent:@"SkinLab-report.json"];
            BOOL saved=data && [data writeToURL:file options:NSDataWritingAtomic error:&error];
            NSString *message=error.localizedDescription?:@"تعذر حفظ تقرير الفحص";
            dispatch_async(dispatch_get_main_queue(), ^{
                ProbeBusy=NO;
                ProbeButton.enabled=YES;
                [ProbeButton setTitle:@"Skins تجربة" forState:UIControlStateNormal];
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
static void ExportLab(void) { [SkinProbeAction exportReport]; }
static void Attach(void) {
    InstallLab();
    if (ProbeBusy) return;
    UIWindow *w=HostWindow();
    if (!w) return;
    if (!ProbeButton) {
        ProbeButton=[UIButton buttonWithType:UIButtonTypeSystem];
        [ProbeButton setTitle:@"Skins تجربة" forState:UIControlStateNormal];
        ProbeButton.backgroundColor=[UIColor colorWithRed:.40 green:.16 blue:.70 alpha:.95];
        [ProbeButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        ProbeButton.titleLabel.font=[UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        ProbeButton.layer.cornerRadius=14;
        ProbeButton.accessibilityLabel=@"إعدادات المظهر التجريبية";
        [ProbeButton addTarget:SkinProbeAction.class action:@selector(run) forControlEvents:UIControlEventTouchUpInside];
    }
    if (ProbeButton.superview!=w) [w addSubview:ProbeButton];
    ProbeButton.frame=CGRectMake(w.safeAreaInsets.left+12,w.safeAreaInsets.top+68,112,34);
    [w bringSubviewToFront:ProbeButton];
}
__attribute__((constructor)) static void Start(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSUserDefaults *prefs=NSUserDefaults.standardUserDefaults;
        LabLevelEnabled=[prefs boolForKey:@"SkinLab.LevelEnabled"];
        int savedLevel=(int)[prefs integerForKey:@"SkinLab.Level"];
        if(savedLevel>=1&&savedLevel<=999) LabLevel=savedLevel;
        int savedLeague=(int)[prefs integerForKey:@"SkinLab.League"];
        for(unsigned i=0;i<7;i++) if(savedLeague==LabLeagues[i]) LabLeague=savedLeague;
        [NSTimer scheduledTimerWithTimeInterval:2 repeats:YES block:^(NSTimer *timer){(void)timer;Attach();}];
    });
}

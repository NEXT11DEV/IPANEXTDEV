#import "ActivationKit.h"
#import <UIKit/UIKit.h>
#import <Security/Security.h>
#include <stdatomic.h>
#include <stdbool.h>
static NSString *const Origin=@"https://activation-console.yousifjiboori.chatgpt.site";
static NSString *const Service=@"local.activation.account";
static NSDictionary *Account;
static NSTimeInterval ServerOffset;
static _Atomic(bool) Granted=false;
static UIWindow *Overlay;
static UIWindow *Previous;
static CFAbsoluteTime LastFrame=0;
static NSString *ReadSecret(NSString *name){
 NSDictionary *q=@{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,(__bridge id)kSecAttrService:Service,(__bridge id)kSecAttrAccount:name,(__bridge id)kSecReturnData:@YES,(__bridge id)kSecMatchLimit:(__bridge id)kSecMatchLimitOne};CFTypeRef value=NULL;
 if(SecItemCopyMatching((__bridge CFDictionaryRef)q,&value)!=errSecSuccess)return nil;
 NSData *d=CFBridgingRelease(value);return [[NSString alloc]initWithData:d encoding:NSUTF8StringEncoding];
}
static void WriteSecret(NSString *name,NSString *value){
 NSDictionary *q=@{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,(__bridge id)kSecAttrService:Service,(__bridge id)kSecAttrAccount:name};SecItemDelete((__bridge CFDictionaryRef)q);if(!value)return;
 NSMutableDictionary *a=[q mutableCopy];a[(__bridge id)kSecValueData]=[value dataUsingEncoding:NSUTF8StringEncoding];a[(__bridge id)kSecAttrAccessible]=(__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;SecItemAdd((__bridge CFDictionaryRef)a,NULL);
}
static void API(NSString *path,NSDictionary *body,void(^done)(NSDictionary *,NSString *)){
 NSMutableURLRequest *r=[NSMutableURLRequest requestWithURL:[NSURL URLWithString:[Origin stringByAppendingString:path]]];r.timeoutInterval=15;
 if(body){r.HTTPMethod=@"POST";[r setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];r.HTTPBody=[NSJSONSerialization dataWithJSONObject:body options:0 error:nil];}
 NSString *token=ReadSecret(@"session");if(token)[r setValue:[@"Bearer " stringByAppendingString:token] forHTTPHeaderField:@"Authorization"];
 [[[NSURLSession sharedSession]dataTaskWithRequest:r completionHandler:^(NSData *d,NSURLResponse *response,NSError *e){
  NSDictionary *j=d?[NSJSONSerialization JSONObjectWithData:d options:0 error:nil]:nil;
  if(![j isKindOfClass:NSDictionary.class])j=nil;
  NSInteger status=[response isKindOfClass:NSHTTPURLResponse.class]?((NSHTTPURLResponse*)response).statusCode:0;
  NSString *error=e?@"تعذر الاتصال بالسيرفر":(status<200||status>=300)?(j[@"error"]?:@"تعذر التحقق من الاشتراك"):nil;
  dispatch_async(dispatch_get_main_queue(),^{done(j,error);});
 }]resume];
}
@interface ActivationPanel:UIViewController
@property(nonatomic) BOOL accountMode;
@property(nonatomic,strong) UITextField *code;
@property(nonatomic,strong) UILabel *message;
@property(nonatomic,strong) UILabel *countdown;
@property(nonatomic,strong) UIButton *submit;
@property(nonatomic,strong) NSTimer *timer;
@property(nonatomic) NSTimeInterval expiry,serverOffset;
@end
static void Present(BOOL accountMode);
@implementation ActivationPanel
- (UILabel*)label:(NSString*)text size:(CGFloat)size color:(UIColor*)color{
 UILabel *l=[UILabel new];l.text=text;l.textColor=color;l.font=[UIFont systemFontOfSize:size weight:UIFontWeightRegular];l.textAlignment=NSTextAlignmentCenter;l.numberOfLines=0;return l;
}
- (void)viewDidLoad{
 [super viewDidLoad];self.view.backgroundColor=[UIColor colorWithWhite:0 alpha:.72];
 UIColor *teal=[UIColor colorWithRed:.20 green:.88 blue:.83 alpha:1];
 UIView *card=[UIView new];card.backgroundColor=[UIColor colorWithRed:.055 green:.085 blue:.11 alpha:1];card.layer.cornerRadius=20;card.layer.borderWidth=1;card.layer.borderColor=[teal colorWithAlphaComponent:.45].CGColor;card.translatesAutoresizingMaskIntoConstraints=NO;[self.view addSubview:card];
 [NSLayoutConstraint activateConstraints:@[[card.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],[card.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],[card.widthAnchor constraintEqualToAnchor:self.view.widthAnchor multiplier:.80],[card.heightAnchor constraintEqualToAnchor:self.view.heightAnchor multiplier:.84]]];
 UIStackView *stack=[UIStackView new];stack.axis=UILayoutConstraintAxisVertical;stack.alignment=UIStackViewAlignmentFill;stack.spacing=14;stack.translatesAutoresizingMaskIntoConstraints=NO;[card addSubview:stack];
 [NSLayoutConstraint activateConstraints:@[[stack.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],[stack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:28],[stack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-28],[stack.topAnchor constraintGreaterThanOrEqualToAnchor:card.topAnchor constant:18],[stack.bottomAnchor constraintLessThanOrEqualToAnchor:card.bottomAnchor constant:-18]]];
 [stack addArrangedSubview:[self label:self.accountMode?@"الحساب":@"مرحباً بعودتك" size:25 color:UIColor.whiteColor]];
 self.message=[self label:@"" size:13 color:teal];
 if(self.accountMode){
  [stack addArrangedSubview:[self label:@"ينتهي الاشتراك خلال" size:13 color:teal]];
  self.countdown=[self label:@"—" size:29 color:UIColor.whiteColor];[stack addArrangedSubview:self.countdown];
  [stack addArrangedSubview:[self label:Account[@"name"]?:@"الحساب" size:20 color:UIColor.whiteColor]];
  [stack addArrangedSubview:[self label:@"الاشتراك فعّال" size:13 color:teal]];
  self.expiry=[Account[@"expires"] doubleValue]/1000.0;self.serverOffset=[Account[@"serverTime"] doubleValue]/1000.0-NSDate.date.timeIntervalSince1970;
  self.timer=[NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(updateCounter) userInfo:nil repeats:YES];[self updateCounter];
  UIButton *close=[UIButton buttonWithType:UIButtonTypeSystem];[close setTitle:@"العودة إلى اللعبة" forState:UIControlStateNormal];[close setTitleColor:teal forState:UIControlStateNormal];[close addTarget:self action:@selector(closePanel) forControlEvents:UIControlEventTouchUpInside];[stack addArrangedSubview:close];
 }else{
  [stack addArrangedSubview:[self label:@"أدخل كود التفعيل الخاص بك" size:14 color:[UIColor colorWithWhite:.7 alpha:1]]];
  self.code=[UITextField new];self.code.borderStyle=UITextBorderStyleRoundedRect;self.code.backgroundColor=[UIColor colorWithWhite:.15 alpha:1];self.code.textColor=UIColor.whiteColor;self.code.placeholder=@"ABCDE-FGHIJ-KLMNO-PQRST";self.code.textAlignment=NSTextAlignmentCenter;self.code.font=[UIFont monospacedSystemFontOfSize:16 weight:UIFontWeightRegular];self.code.autocorrectionType=UITextAutocorrectionTypeNo;self.code.autocapitalizationType=UITextAutocapitalizationTypeAllCharacters;self.code.spellCheckingType=UITextSpellCheckingTypeNo;[self.code.heightAnchor constraintEqualToConstant:46].active=YES;[stack addArrangedSubview:self.code];
  self.submit=[UIButton buttonWithType:UIButtonTypeSystem];self.submit.backgroundColor=teal;self.submit.layer.cornerRadius=10;[self.submit setTitle:@"تفعيل الاشتراك" forState:UIControlStateNormal];[self.submit setTitleColor:UIColor.blackColor forState:UIControlStateNormal];[self.submit.heightAnchor constraintEqualToConstant:44].active=YES;[self.submit addTarget:self action:@selector(activate) forControlEvents:UIControlEventTouchUpInside];[stack addArrangedSubview:self.submit];
 }
 [stack addArrangedSubview:self.message];
}
- (void)updateCounter{self.expiry=[Account[@"expires"] doubleValue]/1000.0;self.serverOffset=ServerOffset;NSInteger left=MAX(0,(NSInteger)(self.expiry-NSDate.date.timeIntervalSince1970-self.serverOffset));self.countdown.text=[NSString stringWithFormat:@"%02ld يوم  :  %02ld ساعة  :  %02ld دقيقة  :  %02ld ثانية",(long)(left/86400),(long)(left%86400/3600),(long)(left%3600/60),(long)(left%60)];if(left==0){Granted=NO;self.message.text=@"انتهت مدة الاشتراك";[self.timer invalidate];dispatch_async(dispatch_get_main_queue(),^{Present(NO);});}}
- (void)activate{NSString *code=[[self.code.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]uppercaseString];if(code.length!=23){self.message.text=@"تحقق من صيغة كود التفعيل";return;}self.submit.enabled=NO;self.message.text=@"جارِ التحقق…";NSString *device=ReadSecret(@"installation");if(!device){device=NSUUID.UUID.UUIDString;WriteSecret(@"installation",device);}__weak typeof(self) weakSelf=self;
 API(@"/api/activate",@{@"code":code,@"device":device},^(NSDictionary *j,NSString *error){__strong typeof(weakSelf) s=weakSelf;if(!s)return;s.submit.enabled=YES;if(error){s.message.text=error;return;}if(![j[@"token"]isKindOfClass:NSString.class]||![j[@"account"]isKindOfClass:NSDictionary.class]){s.message.text=@"استجابة غير صالحة";return;}Account=j[@"account"];ServerOffset=[Account[@"serverTime"] doubleValue]/1000.0-NSDate.date.timeIntervalSince1970;Granted=[Account[@"status"]isEqual:@"active"];WriteSecret(@"session",j[@"token"]);if(Granted)[s closePanel];else s.message.text=@"الاشتراك غير فعّال";});
}
- (void)closePanel{if(!Granted)return;[self.timer invalidate];Overlay.hidden=YES;[Previous makeKeyWindow];}
- (void)dealloc{[_timer invalidate];}
@end
static void Present(BOOL accountMode){
 if(!NSThread.isMainThread){dispatch_async(dispatch_get_main_queue(),^{Present(accountMode);});return;}
 if(Overlay&&!Overlay.hidden){if(!accountMode&&[Overlay.rootViewController isKindOfClass:ActivationPanel.class]&&((ActivationPanel*)Overlay.rootViewController).accountMode){[((ActivationPanel*)Overlay.rootViewController).timer invalidate];Overlay.hidden=YES;}else return;}
 UIWindowScene *scene=nil;for(UIScene *s in UIApplication.sharedApplication.connectedScenes)if([s isKindOfClass:UIWindowScene.class]&&s.activationState==UISceneActivationStateForegroundActive){scene=(UIWindowScene*)s;break;}if(!scene)return;
 for(UIWindow *w in scene.windows)if(w.isKeyWindow&&w!=Overlay){Previous=w;break;}
 if(!Overlay){Overlay=[[UIWindow alloc]initWithWindowScene:scene];Overlay.frame=scene.coordinateSpace.bounds;Overlay.windowLevel=UIWindowLevelAlert+1;}
 ActivationPanel *panel=[ActivationPanel new];panel.accountMode=accountMode;Overlay.rootViewController=panel;[Overlay makeKeyAndVisible];
}
BOOL ActivationAccessActive(void){@synchronized(ActivationPanel.class){return Granted;}}
void ActivationShowLogin(void){Present(NO);}
void ActivationAccountFrame(void){CFAbsoluteTime now=CFAbsoluteTimeGetCurrent();BOOL enter;@synchronized(ActivationPanel.class){enter=now-LastFrame>.7;LastFrame=now;}if(enter)Present(Granted);}
static void Validate(void){if(!ReadSecret(@"session")){Granted=NO;Present(NO);return;}API(@"/api/account",nil,^(NSDictionary *j,NSString *error){if(error||![j[@"account"]isKindOfClass:NSDictionary.class]){Granted=NO;Present(NO);return;}Account=j[@"account"];ServerOffset=[Account[@"serverTime"] doubleValue]/1000.0-NSDate.date.timeIntervalSince1970;Granted=[Account[@"status"]isEqual:@"active"];if(!Granted)Present(NO);else if(Overlay&&!Overlay.hidden&&[Overlay.rootViewController isKindOfClass:ActivationPanel.class]&&!((ActivationPanel*)Overlay.rootViewController).accountMode){Overlay.hidden=YES;[Previous makeKeyWindow];}});}
__attribute__((constructor))static void StartActivation(void){dispatch_async(dispatch_get_main_queue(),^{[NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){Validate();}];[NSTimer scheduledTimerWithTimeInterval:45 repeats:YES block:^(NSTimer *t){Validate();}];dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),^{Validate();});});}

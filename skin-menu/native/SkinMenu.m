#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <QuartzCore/QuartzCore.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <dlfcn.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>
#include <string.h>
#include <stdlib.h>
#include <math.h>

static NSObject *Lock;
static _Atomic int LevelOn,LevelValue,LeagueValue,CueValue,FrameValue,AvatarValue;
static _Atomic bool Dirty,CueCurrentlyOpponent;
static _Atomic unsigned CueCalls,StarCalls,HUDCalls,FrameCalls,AvatarCalls,DrawCalls,OffMainCalls;
static _Atomic bool LocalHUDFound;
static NSMutableDictionary *CueImages,*FrameImages,*AvatarImages,*CueDefinitions;
static __weak id LastLobby;
static char LobbyArgsKey;
static _Thread_local unsigned LocalCueDepth;
static _Thread_local int CueRenderScope;
static _Atomic unsigned LobbyCalls,CueAppearanceApplied,CueRootCalls;
static __weak id LastCueWidget;
static char CueRootArgsKey;
static void (*OldCueRoot)(id,SEL,id,int,BOOL);
static void ConfigureAccountLinks(void);
static void BootstrapViews(void);
static _Atomic bool AccountLinksConfigured;
static void (*OldLobby)(id,SEL,id,id);
static void (*OldLobbyAvatar)(id,SEL),(*OldLobbyFrame)(id,SEL);
static void (*OldCueDefinition)(id,SEL,id,int,int,BOOL);
static int NativeLocalSide(id hud);
static NSMutableSet *CueIDs,*FrameIDs,*AvatarIDs,*PendingImages;
static NSMutableArray *CaptureQueue;
static __weak id LastCue,LastWidget,LastHUD,LastAvatar;
static int OriginalCueID,OriginalCueLevel,HUDSide;
static char LocalKey,StarArgsKey,HUD1ArgsKey,HUD2ArgsKey,FrameArgsKey,AvatarArgsKey;
static _Thread_local unsigned LocalDepth;
static id (*OldLocalFactory)(id,SEL);
static void (*OldStar)(id,SEL,int,int);
static void (*OldCue)(id,SEL,int,int,BOOL);
static void (*OldCueSetup)(id,SEL,int,int);
static void (*OldDraw)(id,SEL);
static void (*OldHUD1)(id,SEL,unsigned,unsigned);
static void (*OldHUD2)(id,SEL,unsigned,unsigned);
static void (*OldHUDAllAvatar)(id,SEL,id,int,id,id,int,unsigned);
static void (*OldFrame)(id,SEL,unsigned,unsigned,BOOL);
static void (*OldAvatar)(id,SEL,int);
static uintptr_t NinjaBase;
static BOOL NinjaVerified;
static NSString *HookDescription=@"بانتظار تهيئة الربط";
static BOOL Access(void) { BOOL (*f)(void)=(BOOL(*)(void))dlsym(RTLD_DEFAULT,"ActivationAccessActive");return f&&f(); }
static BOOL Local(id node) {
    for(int i=0;i<10 && node;i++) {
        if([objc_getAssociatedObject(node,&LocalKey) boolValue]) return YES;
        SEL p=sel_registerName("parent");
        if(![node respondsToSelector:p]) break;
        node=((id(*)(id,SEL))objc_msgSend)(node,p);
    }
    return NO;
}
static id ObjectCall(id obj,const char *name) {
    SEL s=sel_registerName(name);if(!obj||![obj respondsToSelector:s]) return nil;
    Method m=class_getInstanceMethod(object_getClass(obj),s);
    char *r=m?method_copyReturnType(m):NULL;BOOL ok=r&&r[0]=='@';free(r);
    return ok?((id(*)(id,SEL))objc_msgSend)(obj,s):nil;
}
static BOOL OwnID(id playerID,id offlineID) {
    Class c=objc_getClass("UserInfo");id info=ObjectCall(c,"sharedUserInfo");id own=ObjectCall(info,"miniclipId");
    if(![own isKindOfClass:NSString.class]||![(NSString *)own length]) return NO;
    return [own isEqual:playerID]||[own isEqual:offlineID];
}
static NSMutableSet *IDs(int kind) { return kind==0?CueIDs:kind==1?FrameIDs:AvatarIDs; }
static NSMutableDictionary *Images(int kind) { return kind==0?CueImages:kind==1?FrameImages:AvatarImages; }
static BOOL Known(int kind,int value) { if(value<0)return NO;@synchronized(Lock){return [IDs(kind) containsObject:@(value)];} }
static void Observe(int kind,int value,id node) {
    if(value<0||value>10000000||!node)return;
    NSString *key=[NSString stringWithFormat:@"%d:%d",kind,value];
    @synchronized(Lock) {
        [IDs(kind) addObject:@(value)];
        if(!Images(kind)[@(value)]&&![PendingImages containsObject:key]&&CaptureQueue.count<48) {
            [PendingImages addObject:key];[CaptureQueue addObject:@{@"kind":@(kind),@"id":@(value),@"node":node,@"key":key}];
        }
    }
}
static void MarkAvatar(id avatar) { if(avatar){objc_setAssociatedObject(avatar,&LocalKey,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);@synchronized(Lock){LastAvatar=avatar;}atomic_store(&Dirty,true);} }
static void NewStar(id self,SEL cmd,int league,int level) {
    atomic_fetch_add(&StarCalls,1);if(!NSThread.isMainThread)atomic_fetch_add(&OffMainCalls,1);
    objc_setAssociatedObject(self,&StarArgsKey,@[@(league),@(level)],OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    BOOL local=LocalDepth||Local(self);
    if(local){objc_setAssociatedObject(self,&LocalKey,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);@synchronized(Lock){LastWidget=self;}}
    BOOL on=local&&Access()&&atomic_load(&LevelOn);
    OldStar(self,cmd,on?atomic_load(&LeagueValue):league,on?atomic_load(&LevelValue):level);
}
static id NewLocal(id self,SEL cmd) {
    LocalDepth++;id result=OldLocalFactory(self,cmd);LocalDepth--;
    if(result){objc_setAssociatedObject(result,&LocalKey,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);@synchronized(Lock){LastWidget=result;}MarkAvatar(ObjectCall(result,"playerAvatar"));atomic_store(&Dirty,true);}
    return result;
}
static void NewCue(id self,SEL cmd,int cue,int level,BOOL opponent) {
    atomic_fetch_add(&CueCalls,1);if(!NSThread.isMainThread)atomic_fetch_add(&OffMainCalls,1);
    atomic_store(&CueCurrentlyOpponent,opponent);int previousScope=CueRenderScope;CueRenderScope=opponent?-1:1;
    if(!opponent){@synchronized(Lock){LastCue=self;OriginalCueID=cue;OriginalCueLevel=level;}LocalCueDepth++;}
    OldCue(self,cmd,cue,level,opponent);
    if(!opponent)LocalCueDepth--;CueRenderScope=previousScope;
}
static void NewCueSetup(id self,SEL cmd,int cue,int level) {OldCueSetup(self,cmd,cue,level);}
static void NewCueDefinition(id self,SEL cmd,id definition,int product,int level,BOOL force) { OldCueDefinition(self,cmd,definition,product,level,force); }
static void NewCueRoot(id self,SEL cmd,id definition,int product,BOOL force){
    atomic_fetch_add(&CueRootCalls,1);
    if(definition&&product>=0){@synchronized(Lock){CueDefinitions[@(product)]=definition;}objc_setAssociatedObject(self,&CueRootArgsKey,@[definition,@(product),@(force)],OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
    BOOL local=CueRenderScope>0||(CueRenderScope==0&&Local(self));if(CueRenderScope!=0)objc_setAssociatedObject(self,&LocalKey,@(CueRenderScope>0),OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if(local){@synchronized(Lock){LastCueWidget=self;}}
    int selected=atomic_load(&CueValue);id replacement=nil;@synchronized(Lock){replacement=CueDefinitions[@(selected)];}
    BOOL apply=local&&Access()&&selected>=0&&replacement;
    OldCueRoot(self,cmd,apply?replacement:definition,product,apply?YES:force);
    if(apply)atomic_fetch_add(&CueAppearanceApplied,1);else Observe(0,product,ObjectCall(self,"getCueSprite"));
}
static void MarkLobbyAvatar(id self){Ivar field=class_getInstanceVariable(object_getClass(self),"_playerAvatar");const char *type=field?ivar_getTypeEncoding(field):NULL;if(type&&type[0]=='@')MarkAvatar(object_getIvar(self,field));}
static void NewLobbyAvatar(id self,SEL cmd){OldLobbyAvatar(self,cmd);MarkLobbyAvatar(self);}
static void NewLobbyFrame(id self,SEL cmd){OldLobbyFrame(self,cmd);MarkLobbyAvatar(self);}
static void NewLobby(id self,SEL cmd,id league,id level){
    atomic_fetch_add(&LobbyCalls,1);objc_setAssociatedObject(self,&LobbyArgsKey,@[league?:NSNull.null,level?:NSNull.null],OBJC_ASSOCIATION_RETAIN_NONATOMIC);@synchronized(Lock){LastLobby=self;}
    BOOL on=Access()&&atomic_load(&LevelOn);OldLobby(self,cmd,on?@(atomic_load(&LeagueValue)):league,on?@(atomic_load(&LevelValue)):level);MarkLobbyAvatar(self);
}
static void HUDStar(id self,SEL cmd,unsigned league,unsigned level,int side) {
    atomic_fetch_add(&HUDCalls,1);objc_setAssociatedObject(self,side==1?&HUD1ArgsKey:&HUD2ArgsKey,@[@(league),@(level)],OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    int nativeSide=NativeLocalSide(self);BOOL local=NO;@synchronized(Lock){if(LastHUD!=self){HUDSide=0;atomic_store(&LocalHUDFound,false);}LastHUD=self;if(nativeSide){HUDSide=nativeSide;atomic_store(&LocalHUDFound,true);}local=HUDSide==side;}
    BOOL on=local&&Access()&&atomic_load(&LevelOn);
    (side==1?OldHUD1:OldHUD2)(self,cmd,on?(unsigned)atomic_load(&LeagueValue):league,on?(unsigned)atomic_load(&LevelValue):level);
}
static void NewHUD1(id self,SEL cmd,unsigned league,unsigned level){HUDStar(self,cmd,league,level,1);}
static void NewHUD2(id self,SEL cmd,unsigned league,unsigned level){HUDStar(self,cmd,league,level,2);}
static void NewHUDAllAvatar(id self,SEL cmd,id avatar,int fallback,id playerID,id offlineID,int selected,unsigned rank) {
    if(OwnID(playerID,offlineID)) {
        MarkAvatar(avatar);
        // Identify which player slot owns this avatar from the game's existing avatar properties.
        id p1=ObjectCall(self,"player1Avatar"),p2=ObjectCall(self,"player2Avatar");
        int side=avatar==p1?1:avatar==p2?2:0;
        if(side){@synchronized(Lock){LastHUD=self;HUDSide=side;}atomic_store(&LocalHUDFound,true);atomic_store(&Dirty,true);}
    }
    OldHUDAllAvatar(self,cmd,avatar,fallback,playerID,offlineID,selected,rank);
}
static void NewFrame(id self,SEL cmd,unsigned product,unsigned fallback,BOOL shader) {
    atomic_fetch_add(&FrameCalls,1);objc_setAssociatedObject(self,&FrameArgsKey,@[@(product),@(fallback),@(shader)],OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    int chosen=atomic_load(&FrameValue);BOOL local=Local(self);if(local){@synchronized(Lock){LastAvatar=self;}}
    OldFrame(self,cmd,local&&Access()&&Known(1,chosen)?(unsigned)chosen:product,fallback,shader);
    Observe(1,(int)product,ObjectCall(self,"avatarFrame"));
}
static void NewAvatar(id self,SEL cmd,int avatar) {
    atomic_fetch_add(&AvatarCalls,1);objc_setAssociatedObject(self,&AvatarArgsKey,@(avatar),OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    BOOL local=Local(self);if(local){@synchronized(Lock){LastAvatar=self;}}
    int chosen=atomic_load(&AvatarValue);OldAvatar(self,cmd,local&&Access()&&Known(2,chosen)?chosen:avatar);Observe(2,avatar,self);
}
static void RefreshOnRenderThread(void) {
    id candidate=nil;@synchronized(Lock){candidate=LastHUD;}if(candidate){int inferred=NativeLocalSide(candidate);if(inferred){@synchronized(Lock){if(HUDSide!=inferred)atomic_store(&Dirty,true);HUDSide=inferred;}atomic_store(&LocalHUDFound,true);}}
    if(!atomic_exchange(&Dirty,false))return;
    id cue,widget,hud,avatar,lobby,cueWidget;int cueID,cueLevel,side;
    @synchronized(Lock){cue=LastCue;widget=LastWidget;hud=LastHUD;avatar=LastAvatar;lobby=LastLobby;cueWidget=LastCueWidget;cueID=OriginalCueID;cueLevel=OriginalCueLevel;side=HUDSide;}
    BOOL access=Access(),on=access&&atomic_load(&LevelOn);
    NSArray *lp=lobby?objc_getAssociatedObject(lobby,&LobbyArgsKey):nil;
    if(lobby&&lp.count==2&&OldLobby)OldLobby(lobby,sel_registerName("updateUserLeagueStarForLeague:withLevel:"),on?@(atomic_load(&LeagueValue)):(lp[0]==NSNull.null?nil:lp[0]),on?@(atomic_load(&LevelValue)):(lp[1]==NSNull.null?nil:lp[1]));
    NSArray *star=widget?objc_getAssociatedObject(widget,&StarArgsKey):nil;
    if(widget&&star.count==2&&OldStar)OldStar(widget,sel_registerName("setupStarWithLeague:andLevel:"),on?atomic_load(&LeagueValue):[star[0] intValue],on?atomic_load(&LevelValue):[star[1] intValue]);
    NSArray *hp=hud?objc_getAssociatedObject(hud,side==1?&HUD1ArgsKey:&HUD2ArgsKey):nil;
    if(hud&&hp.count==2&&side&&(side==1?OldHUD1:OldHUD2)){
        SEL selector=sel_registerName(side==1?"setupPlayer1StartForPlayerLeague:forPlayerRating:":"setupPlayer2StartForPlayerLeague:forPlayerRating:");
        // The installed original selector may be the alternate spelling on another build.
        (side==1?OldHUD1:OldHUD2)(hud,selector,on?(unsigned)atomic_load(&LeagueValue):[hp[0] unsignedIntValue],on?(unsigned)atomic_load(&LevelValue):[hp[1] unsignedIntValue]);
    }
    if(!atomic_load(&CueCurrentlyOpponent)){
        NSArray *params=cueWidget?objc_getAssociatedObject(cueWidget,&CueRootArgsKey):nil;
        if(cueWidget&&params.count==3&&OldCueRoot){int selected=atomic_load(&CueValue);id definition=nil;@synchronized(Lock){definition=CueDefinitions[@(selected)];}BOOL apply=access&&selected>=0&&definition;OldCueRoot(cueWidget,sel_registerName("setupWithCueSpriteDefinition:productId:forceSpriteDef:"),apply?definition:params[0],[params[1] intValue],apply?YES:[params[2] boolValue]);if(apply)atomic_fetch_add(&CueAppearanceApplied,1);}
        else if(cue&&OldCue){int previousScope=CueRenderScope;CueRenderScope=1;LocalCueDepth++;OldCue(cue,sel_registerName("setCueWidgetWithCueId:cueLevel:forOpponent:"),cueID,cueLevel,NO);LocalCueDepth--;CueRenderScope=previousScope;}
    }
    NSArray *fp=avatar?objc_getAssociatedObject(avatar,&FrameArgsKey):nil;
    if(avatar&&fp.count==3&&OldFrame){int selected=atomic_load(&FrameValue);OldFrame(avatar,sel_registerName("loadAvatarFrameWithProductId:fallbackRank:andShouldUseShader:"),access&&Known(1,selected)?(unsigned)selected:[fp[0] unsignedIntValue],[fp[1] unsignedIntValue],[fp[2] boolValue]);}
    NSNumber *ap=avatar?objc_getAssociatedObject(avatar,&AvatarArgsKey):nil;
    if(avatar&&ap&&OldAvatar){int selected=atomic_load(&AvatarValue);OldAvatar(avatar,sel_registerName("loadWithAvatarID:"),access&&Known(2,selected)?selected:ap.intValue);}
}
static void (*OldSlot1)(id,SEL,id,id,int,unsigned);
static void (*OldSlot2)(id,SEL,id,id,int,unsigned);
static void SlotAvatar(id self,SEL cmd,id player,id offline,int selected,unsigned rank,int side){
    if(OwnID(player,offline)){@synchronized(Lock){LastHUD=self;HUDSide=side;}atomic_store(&LocalHUDFound,true);atomic_store(&Dirty,true);}
    (side==1?OldSlot1:OldSlot2)(self,cmd,player,offline,selected,rank);
}
static void NewSlot1(id self,SEL cmd,id p,id o,int s,unsigned r){SlotAvatar(self,cmd,p,o,s,r,1);}
static void NewSlot2(id self,SEL cmd,id p,id o,int s,unsigned r){SlotAvatar(self,cmd,p,o,s,r,2);}
static char TypeAt(Method m,unsigned index){char *t=method_copyArgumentType(m,index);char v=t?t[0]:0;free(t);return v;}
static BOOL Args(Method m,const char *ret,const char **args,unsigned count){
    if(!m||method_getNumberOfArguments(m)!=count)return NO;char *t=method_copyReturnType(m);BOOL ok=t&&strcmp(t,ret)==0;free(t);
    for(unsigned i=0;i<count&&ok;i++){t=method_copyArgumentType(m,i);ok=t&&strcmp(t,args[i])==0;free(t);}return ok;
}
static int NativeLocalSide(id hud){
    id manager=ObjectCall(objc_getClass("GameManager"),"sharedGameManager"),player=ObjectCall(manager,"player");if(!hud||!player)return 0;
    const char *args[]={"@",":","@"};const char *names[]={"isPlayer1:","isPlayer2:"};
    for(int i=0;i<2;i++){SEL sel=sel_registerName(names[i]);Method m=class_getInstanceMethod(object_getClass(hud),sel);if(Args(m,"B",args,3)&&((BOOL(*)(id,SEL,id))objc_msgSend)(hud,sel,player))return i+1;}return 0;
}
static BOOL Install(const char *cn,const char *mn,BOOL meta,IMP replacement,IMP *old,const char *ret,const char **args,unsigned n){
    if(*old)return YES;Class cls=objc_getClass(cn);if(!cls)return NO;if(meta)cls=object_getClass(cls);SEL sel=sel_registerName(mn);Method m=class_getInstanceMethod(cls,sel);if(!Args(m,ret,args,n))return NO;
    *old=method_getImplementation(m);class_replaceMethod(cls,sel,replacement,method_getTypeEncoding(m));return YES;
}
static UIImage *Snapshot(id node){
    if(!ObjectCall(objc_getClass("EAGLContext"),"currentContext"))return nil;
    SEL sizeS=sel_registerName("contentSize"),posS=sel_registerName("position"),setPosS=sel_registerName("setPosition:"),visitS=sel_registerName("visit");
    NSMethodSignature *sizeSig=[node methodSignatureForSelector:sizeS],*posSig=[node methodSignatureForSelector:posS];
    if(sizeSig.methodReturnLength!=sizeof(CGSize)||posSig.methodReturnLength!=sizeof(CGPoint)||![node respondsToSelector:setPosS]||![node respondsToSelector:visitS])return nil;
    CGSize size=((CGSize(*)(id,SEL))objc_msgSend)(node,sizeS);CGPoint position=((CGPoint(*)(id,SEL))objc_msgSend)(node,posS);
    if(!isfinite(size.width)||!isfinite(size.height)||size.width<1||size.height<1||size.width>8192||size.height>8192)return nil;
    SEL sxS=sel_registerName("scaleX"),syS=sel_registerName("scaleY"),setSX=sel_registerName("setScaleX:"),setSY=sel_registerName("setScaleY:");
    Method mx=class_getInstanceMethod(object_getClass(node),sxS),my=class_getInstanceMethod(object_getClass(node),syS);
    char *rx=mx?method_copyReturnType(mx):NULL,*ry=my?method_copyReturnType(my):NULL;
    BOOL scalable=rx&&ry&&rx[0]=='f'&&ry[0]=='f'&&[node respondsToSelector:setSX]&&[node respondsToSelector:setSY];free(rx);free(ry);
    if(!scalable&&MAX(size.width,size.height)>700)return nil;
    float oldX=scalable?((float(*)(id,SEL))objc_msgSend)(node,sxS):1,oldY=scalable?((float(*)(id,SEL))objc_msgSend)(node,syS):1;
    CGFloat factor=scalable?MIN(1,480/MAX(size.width,size.height)):1;CGFloat width=ceil(size.width*factor)+12,height=ceil(size.height*factor)+12;
    Class rtClass=objc_getClass("CCRenderTexture");SEL create=sel_registerName("renderTextureWithWidth:height:");Method factory=rtClass?class_getClassMethod(rtClass,create):NULL;
    if(!factory||method_getNumberOfArguments(factory)!=4)return nil;
    id rt=nil;char type=TypeAt(factory,2);if(TypeAt(factory,3)!=type)return nil;
    if(type=='i')rt=((id(*)(id,SEL,int,int))objc_msgSend)(rtClass,create,(int)width,(int)height);
    else if(type=='f')rt=((id(*)(id,SEL,float,float))objc_msgSend)(rtClass,create,(float)width,(float)height);
    else if(type=='d')rt=((id(*)(id,SEL,double,double))objc_msgSend)(rtClass,create,width,height);
    SEL begin=sel_registerName("beginWithClear:g:b:a:"),end=sel_registerName("end");
    Method bm=rt?class_getInstanceMethod(object_getClass(rt),begin):NULL;const char *clearArgs[]={"@",":","f","f","f","f"};
    if(!rt||!Args(bm,"v",clearArgs,6)||![rt respondsToSelector:end]||![rt respondsToSelector:sel_registerName("getUIImage")])return nil;
    CGPoint anchor=CGPointMake(.5,.5);SEL anchorS=sel_registerName("anchorPoint");NSMethodSignature *as=[node methodSignatureForSelector:anchorS];if(as.methodReturnLength==sizeof(CGPoint))anchor=((CGPoint(*)(id,SEL))objc_msgSend)(node,anchorS);
    SEL rotS=sel_registerName("rotation"),setRot=sel_registerName("setRotation:");Method rm=class_getInstanceMethod(object_getClass(node),rotS);char *rr=rm?method_copyReturnType(rm):NULL;BOOL rotate=rr&&rr[0]=='f'&&[node respondsToSelector:setRot];free(rr);float oldRot=rotate?((float(*)(id,SEL))objc_msgSend)(node,rotS):0;
    UIImage *image=nil;BOOL begun=NO;
    @try {
        if(scalable){((void(*)(id,SEL,float))objc_msgSend)(node,setSX,(float)factor);((void(*)(id,SEL,float))objc_msgSend)(node,setSY,(float)factor);}
        if(rotate)((void(*)(id,SEL,float))objc_msgSend)(node,setRot,0);
        ((void(*)(id,SEL,CGPoint))objc_msgSend)(node,setPosS,CGPointMake(6+anchor.x*size.width*factor,6+anchor.y*size.height*factor));
        ((void(*)(id,SEL,float,float,float,float))objc_msgSend)(rt,begin,0,0,0,0);begun=YES;
        ((void(*)(id,SEL))objc_msgSend)(node,visitS);((void(*)(id,SEL))objc_msgSend)(rt,end);begun=NO;
        id result=ObjectCall(rt,"getUIImage");if([result isKindOfClass:UIImage.class])image=result;
    } @catch(NSException *exception){(void)exception;image=nil;}
    @finally {
        if(begun)((void(*)(id,SEL))objc_msgSend)(rt,end);
        ((void(*)(id,SEL,CGPoint))objc_msgSend)(node,setPosS,position);
        if(scalable){((void(*)(id,SEL,float))objc_msgSend)(node,setSX,oldX);((void(*)(id,SEL,float))objc_msgSend)(node,setSY,oldY);}
        if(rotate)((void(*)(id,SEL,float))objc_msgSend)(node,setRot,oldRot);
    }
    if(image.size.height>image.size.width*2.5)image=[UIImage imageWithCGImage:image.CGImage scale:image.scale orientation:UIImageOrientationRight];
    return image;
}
static void ProcessCapture(void){
    NSDictionary *job=nil;@synchronized(Lock){if(CaptureQueue.count){job=CaptureQueue.firstObject;[CaptureQueue removeObjectAtIndex:0];}}
    if(!job)return;UIImage *image=Snapshot(job[@"node"]);@synchronized(Lock){[PendingImages removeObject:job[@"key"]];if(image)Images([job[@"kind"] intValue])[job[@"id"]]=image;}
}
static void NewDraw(id self,SEL cmd){unsigned frame=atomic_fetch_add(&DrawCalls,1);@autoreleasepool{ConfigureAccountLinks();if(frame%30==0)BootstrapViews();RefreshOnRenderThread();ProcessCapture();}OldDraw(self,cmd);}
static void InstallHooks(void){
    static BOOL complete;if(complete)return;
    const char *factory[]={"@",":"},*pair[]={"@",":","i","i"},*cue[]={"@",":","i","i","B"},*hud[]={"@",":","I","I"},*slot[]={"@",":","@","@","i","I"},*allAvatar[]={"@",":","@","i","@","@","i","I"},*frame[]={"@",":","I","I","B"},*avatar[]={"@",":","i"};
    BOOL star=Install("MatchScreenPlayerWidget","setupStarWithLeague:andLevel:",NO,(IMP)NewStar,(IMP *)&OldStar,"v",pair,4);
    BOOL local=star&&Install("MatchScreenPlayerWidget","createLocalPlayerWidget",YES,(IMP)NewLocal,(IMP *)&OldLocalFactory,"@",factory,2);
    const char *definitionArgs[]={"@",":","@","i","i","B"},*lobbyArgs[]={"@",":","@","@"};
    const char *rootArgs[]={"@",":","@","i","B"};
    BOOL rootOK=Install("CueWidget","setupWithCueSpriteDefinition:productId:forceSpriteDef:",NO,(IMP)NewCueRoot,(IMP *)&OldCueRoot,"v",rootArgs,5);
    BOOL definitionOK=Install("CueWidget","setupWithCueSpriteDefinition:productId:cueLevel:forceSpriteDef:",NO,(IMP)NewCueDefinition,(IMP *)&OldCueDefinition,"v",definitionArgs,6);
    Install("TopBarUserProfileButton","updateUserAvatar",NO,(IMP)NewLobbyAvatar,(IMP *)&OldLobbyAvatar,"v",factory,2);
    Install("TopBarUserProfileButton","updateAvatarFrame",NO,(IMP)NewLobbyFrame,(IMP *)&OldLobbyFrame,"v",factory,2);
    BOOL lobbyOK=Install("TopBarUserProfileButton","updateUserLeagueStarForLeague:withLevel:",NO,(IMP)NewLobby,(IMP *)&OldLobby,"v",lobbyArgs,4);
    BOOL cueOK=Install("VisualCue","setCueWidgetWithCueId:cueLevel:forOpponent:",NO,(IMP)NewCue,(IMP *)&OldCue,"v",cue,5);
    Install("CueWidget","setupWithCueId:cueLevel:",NO,(IMP)NewCueSetup,(IMP *)&OldCueSetup,"v",pair,4);
    BOOL h1=Install("GameHUDTwoPlayerGame","setupPlayer1StartForPlayerLeague:forPlayerRating:",NO,(IMP)NewHUD1,(IMP *)&OldHUD1,"v",hud,4);
    BOOL h2=Install("GameHUDTwoPlayerGame","setupPlayer2StartForPlayerLeague:forPlayerRating:",NO,(IMP)NewHUD2,(IMP *)&OldHUD2,"v",hud,4);
    Install("GameHUDTwoPlayerGame","setupPlayer1AvatarWithPlayerID:offlineReservedPlayerID:selectedAvatarID:cueCollectionRank:",NO,(IMP)NewSlot1,(IMP *)&OldSlot1,"v",slot,6);
    Install("GameHUDTwoPlayerGame","setupPlayer2AvatarWithPlayerID:offlineReservedPlayerID:selectedAvatarID:cueCollectionRank:",NO,(IMP)NewSlot2,(IMP *)&OldSlot2,"v",slot,6);
    Install("GameHUDTwoPlayerGame","setupPlayerAvatar:defaultAvatarImageType:playerID:offlineReservedPlayerID:selectedAvatarID:cueCollectionRank:",NO,(IMP)NewHUDAllAvatar,(IMP *)&OldHUDAllAvatar,"v",allAvatar,8);
    BOOL frameOK=Install("PlayerAvatar","loadAvatarFrameWithProductId:fallbackRank:andShouldUseShader:",NO,(IMP)NewFrame,(IMP *)&OldFrame,"v",frame,5);
    BOOL avatarOK=Install("PlayerAvatar","loadWithAvatarID:",NO,(IMP)NewAvatar,(IMP *)&OldAvatar,"v",avatar,3);
    BOOL draw=Install("CCDirector","drawScene",NO,(IMP)NewDraw,(IMP *)&OldDraw,"v",factory,2);
    HookDescription=[NSString stringWithFormat:@"الرسم %@ • العصا %@ • النجمة %@ • الإطار %@ • الصورة %@",draw?@"✓":@"—",cueOK?@"✓":@"—",(h1&&h2&&local)?@"✓":@"—",frameOK?@"✓":@"—",avatarOK?@"✓":@"—"];
    complete=draw&&cueOK&&rootOK&&definitionOK&&lobbyOK&&h1&&h2&&local&&frameOK&&avatarOK&&OldSlot1&&OldSlot2&&OldHUDAllAvatar;
}
static UIWindow *Window(void){UIWindow *best=nil;for(UIScene *s in UIApplication.sharedApplication.connectedScenes){if(![s isKindOfClass:UIWindowScene.class]||s.activationState!=UISceneActivationStateForegroundActive)continue;for(UIWindow *w in ((UIWindowScene *)s).windows)if(!w.hidden&&w.alpha>.1&&w.rootViewController&&(!best||w.windowLevel>best.windowLevel||(w.windowLevel==best.windowLevel&&w.isKeyWindow)))best=w;}return best;}
static UIViewController *Top(void){UIViewController *v=Window().rootViewController;while(v.presentedViewController&&!v.presentedViewController.isBeingDismissed)v=v.presentedViewController;return v;}
static void FindNinja(void){
    static const unsigned char expected[16]={229,113,182,73,150,137,56,48,158,232,56,170,23,83,57,79};
    if(NinjaVerified)return;
    for(uint32_t i=0;i<_dyld_image_count();i++){
        const char *name=_dyld_get_image_name(i);if(!name||!strstr(name,"/ninja.framework/ninja"))continue;
        const struct mach_header_64 *h=(const struct mach_header_64 *)_dyld_get_image_header(i);if(h->magic!=MH_MAGIC_64)continue;
        const uint8_t *p=(const uint8_t *)h+sizeof(*h);for(uint32_t j=0;j<h->ncmds;j++){
            const struct load_command *c=(const struct load_command *)p;
            if(c->cmd==LC_UUID&&memcmp(((const struct uuid_command *)p)->uuid,expected,16)==0){NinjaBase=(uintptr_t)h;NinjaVerified=YES;return;}p+=c->cmdsize;
        }
    }
}
static void ConfigureAccountLinks(void){
    if(AccountLinksConfigured||!NinjaVerified||!*(volatile unsigned char *)(NinjaBase+0x1113a5))return;
    const char *url="https://t.me/YG8_1";
    void *(*assign)(void*,const char*,size_t)=(void *(*)(void*,const char*,size_t))(NinjaBase+0x8241c);
    assign((void *)(NinjaBase+0x10fef8),url,strlen(url));assign((void *)(NinjaBase+0x10ff10),url,strlen(url));AccountLinksConfigured=YES;
}
static id FindProfileNode(void){
    id director=ObjectCall(objc_getClass("CCDirector"),"sharedDirector"),scene=ObjectCall(director,"runningScene");if(!scene)return nil;
    NSMutableArray *queue=[NSMutableArray arrayWithObject:scene];NSUInteger index=0;Class target=objc_getClass("TopBarUserProfileButton");
    while(index<queue.count&&index<5000){id node=queue[index++];if(target&&[node isKindOfClass:target])return node;id kids=ObjectCall(node,"children");if([kids conformsToProtocol:@protocol(NSFastEnumeration)])for(id child in kids)if(child&&queue.count<5000)[queue addObject:child];}return nil;
}
static void BootstrapViews(void){
    id lobby=nil;@synchronized(Lock){lobby=LastLobby;}
    if(!lobby){lobby=FindProfileNode();SEL update=sel_registerName("updateUserInfo");const char *a[]={"@",":"};if(lobby&&Args(class_getInstanceMethod(object_getClass(lobby),update),"v",a,2))((void(*)(id,SEL))objc_msgSend)(lobby,update);}
    id existingHUD=nil;@synchronized(Lock){existingHUD=LastHUD;}if(!existingHUD)return;id gm=ObjectCall(objc_getClass("GameManager"),"sharedGameManager"),hud=ObjectCall(gm,"gameHUD");Class cls=objc_getClass("GameHUDTwoPlayerGame");
    if(cls&&[hud isKindOfClass:cls]){@synchronized(Lock){LastHUD=hud;}int side=NativeLocalSide(hud);if(side){@synchronized(Lock){HUDSide=side;}atomic_store(&LocalHUDFound,true);}}
}
typedef struct {float x,y,w,h;} MenuRect;
static CGRect Convert(MenuRect r,UIWindow *w){int sw=*(volatile int *)(NinjaBase+0x1113b0),sh=*(volatile int *)(NinjaBase+0x1113b4);if(sw<1||sh<1)return CGRectZero;return CGRectMake(r.x*w.bounds.size.width/sw,r.y*w.bounds.size.height/sh,r.w*w.bounds.size.width/sw,r.h*w.bounds.size.height/sh);}
static UIColor *Cyan(void){return [UIColor colorWithRed:0 green:.94 blue:.95 alpha:1];}
static UIColor *Dark(void){return [UIColor colorWithRed:.075 green:.10 blue:.13 alpha:1];}
static UIImage *Asset(NSString *name){Dl_info d={0};if(!dladdr((const void *)Asset,&d)||!d.dli_fname)return nil;NSString *dir=[@(d.dli_fname) stringByDeletingLastPathComponent];return [UIImage imageWithContentsOfFile:[dir stringByAppendingPathComponent:name]];}
static void Changed(void){NSUserDefaults *p=NSUserDefaults.standardUserDefaults;[p setInteger:atomic_load(&LevelOn) forKey:@"SkinMenu.LevelOn"];[p setInteger:atomic_load(&LevelValue) forKey:@"SkinMenu.Level"];[p setInteger:atomic_load(&LeagueValue) forKey:@"SkinMenu.League"];atomic_store(&Dirty,true);}
static void Export(void){
    NSDictionary *report=@{@"format":@"SkinMenu-4",@"cueRootInstalled":@(OldCueRoot!=NULL),@"cueRootCalls":@(atomic_load(&CueRootCalls)),@"accountLinksConfigured":@(AccountLinksConfigured),@"lobbyHookInstalled":@(OldLobby!=NULL),@"cueDefinitionHookInstalled":@(OldCueDefinition!=NULL),@"lobbyCalls":@(atomic_load(&LobbyCalls)),@"cueAppearanceApplied":@(atomic_load(&CueAppearanceApplied)),@"displayLevel":@(atomic_load(&LevelValue)),@"displayLeague":@(atomic_load(&LeagueValue)),@"selectedCueProduct":@(atomic_load(&CueValue)),@"engineMatched":@(NinjaVerified),@"accessActive":@(Access()),@"levelEnabled":@(atomic_load(&LevelOn)),@"localHUDIdentified":@(atomic_load(&LocalHUDFound)),@"calls":@{@"cue":@(atomic_load(&CueCalls)),@"preMatchStar":@(atomic_load(&StarCalls)),@"matchStar":@(atomic_load(&HUDCalls)),@"frame":@(atomic_load(&FrameCalls)),@"avatar":@(atomic_load(&AvatarCalls)),@"draw":@(atomic_load(&DrawCalls)),@"offMain":@(atomic_load(&OffMainCalls))},@"scope":@"No user identifiers, tokens or keys; only renderer call counts and integration state",@"hooks":HookDescription};
    NSError *e=nil;NSData *data=[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:&e];NSURL *dir=[NSFileManager.defaultManager URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].firstObject;NSURL *file=[dir URLByAppendingPathComponent:@"SkinMenu-report.json"];
    if(!data||![data writeToURL:file options:NSDataWritingAtomic error:&e])return;
    UIActivityViewController *s=[[UIActivityViewController alloc]initWithActivityItems:@[file] applicationActivities:nil];UIViewController *top=Top();if(!top)return;s.popoverPresentationController.sourceView=top.view;s.popoverPresentationController.sourceRect=CGRectMake(CGRectGetMidX(top.view.bounds),CGRectGetMidY(top.view.bounds),1,1);[top presentViewController:s animated:YES completion:nil];
}
@interface SkinMenuView : UIView
@property(nonatomic,strong) UIView *bar;
@property(nonatomic,strong) UIScrollView *body;
@property(nonatomic,strong) NSArray<UIButton *> *tabs;
@property(nonatomic,strong) UILabel *profileTitle,*levelLabel,*valueLabel,*galleryTitle,*note;
@property(nonatomic,strong) UISlider *slider;
@property(nonatomic,strong) UISegmentedControl *segments;
@property(nonatomic,strong) NSMutableArray<UIButton *> *stars,*tiles;
@property(nonatomic,strong) UIButton *reportButton,*restoreButton;
@property(nonatomic) BOOL skins;
@property(nonatomic) NSInteger kind;
@property(nonatomic) NSUInteger revision;
@property(nonatomic) unsigned ticks;
- (void)tick;
@end
@implementation SkinMenuView
- (UILabel *)label:(NSString *)text color:(UIColor *)color size:(CGFloat)size {UILabel *l=[UILabel new];l.text=text;l.textColor=color;l.font=[UIFont systemFontOfSize:size weight:UIFontWeightRegular];return l;}
- (instancetype)initWithFrame:(CGRect)frame {
    if((self=[super initWithFrame:frame])){
        self.semanticContentAttribute=UISemanticContentAttributeForceLeftToRight;self.backgroundColor=UIColor.clearColor;self.bar=[UIView new];self.bar.backgroundColor=Dark();[self addSubview:self.bar];
        NSArray *titles=@[@"ESP",@"AutoPlay",@"Queue",@"Skins",@"Account"],*files=@[@"ESP.png",@"autoplay_on.png",@"queue.png",@"",@"account.png"];
        NSMutableArray *tabs=[NSMutableArray array];
        for(NSInteger i=0;i<5;i++){
            UIButton *b=[UIButton buttonWithType:UIButtonTypeCustom];b.tag=i;[b addTarget:self action:@selector(tab:) forControlEvents:UIControlEventTouchUpInside];
            UIImage *image=i==3?[UIImage systemImageNamed:@"flame.fill"]:Asset(files[i]);UIImageView *icon=[[UIImageView alloc]initWithImage:[image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];icon.tag=11;icon.contentMode=UIViewContentModeScaleAspectFit;[b addSubview:icon];UILabel *title=[self label:titles[i] color:UIColor.grayColor size:14];title.tag=12;title.textAlignment=NSTextAlignmentCenter;[b addSubview:title];UIView *line=[UIView new];line.tag=13;line.backgroundColor=Cyan();line.layer.cornerRadius=1;[b addSubview:line];[self.bar addSubview:b];[tabs addObject:b];
        }self.tabs=tabs;
        self.body=[UIScrollView new];self.body.backgroundColor=[UIColor colorWithRed:.055 green:.085 blue:.10 alpha:1];self.body.showsVerticalScrollIndicator=YES;self.body.indicatorStyle=UIScrollViewIndicatorStyleWhite;[self addSubview:self.body];
        self.profileTitle=[self label:@"Profile Level" color:Cyan() size:16];[self.body addSubview:self.profileTitle];self.stars=[NSMutableArray array];
        NSArray *colors=@[@"magenta",@"cyan",@"green",@"amber",@"gunmetal",@"red",@"blue"];
        for(int i=0;i<7;i++){UIButton *b=[UIButton buttonWithType:UIButtonTypeCustom];b.tag=i;b.layer.cornerRadius=6;[b setImage:Asset([NSString stringWithFormat:@"league_star_%@.png",colors[i]]) forState:UIControlStateNormal];b.imageView.contentMode=UIViewContentModeScaleAspectFit;[b addTarget:self action:@selector(star:) forControlEvents:UIControlEventTouchUpInside];[self.body addSubview:b];[self.stars addObject:b];}
        self.levelLabel=[self label:@"Level" color:UIColor.whiteColor size:19];[self.body addSubview:self.levelLabel];self.valueLabel=[self label:@"100" color:Cyan() size:18];self.valueLabel.textAlignment=NSTextAlignmentRight;[self.body addSubview:self.valueLabel];
        self.slider=[UISlider new];self.slider.minimumValue=1;self.slider.maximumValue=999;self.slider.minimumTrackTintColor=Cyan();self.slider.maximumTrackTintColor=[UIColor colorWithWhite:.22 alpha:1];[self.slider addTarget:self action:@selector(level:) forControlEvents:UIControlEventValueChanged];[self.body addSubview:self.slider];
        self.segments=[[UISegmentedControl alloc]initWithItems:@[@"Cue",@"Frame",@"Avatar"]];self.segments.selectedSegmentIndex=0;self.segments.selectedSegmentTintColor=Cyan();self.segments.backgroundColor=[UIColor colorWithWhite:.17 alpha:1];[self.segments setTitleTextAttributes:@{NSForegroundColorAttributeName:UIColor.whiteColor,NSFontAttributeName:[UIFont systemFontOfSize:17]} forState:UIControlStateNormal];[self.segments setTitleTextAttributes:@{NSForegroundColorAttributeName:UIColor.blackColor} forState:UIControlStateSelected];[self.segments addTarget:self action:@selector(segment:) forControlEvents:UIControlEventValueChanged];[self.body addSubview:self.segments];
        self.galleryTitle=[self label:@"Cue Skin" color:Cyan() size:16];[self.body addSubview:self.galleryTitle];self.note=[self label:@"اعرض العناصر في اللعبة أو المتجر مرة واحدة لتظهر صورها هنا." color:[UIColor colorWithWhite:.7 alpha:1] size:12];self.note.numberOfLines=0;[self.body addSubview:self.note];self.tiles=[NSMutableArray array];
        self.restoreButton=[UIButton buttonWithType:UIButtonTypeSystem];[self.restoreButton setTitle:@"إرجاع المظهر الأصلي" forState:UIControlStateNormal];self.restoreButton.tintColor=Cyan();[self.restoreButton addTarget:self action:@selector(restore) forControlEvents:UIControlEventTouchUpInside];[self.body addSubview:self.restoreButton];
        self.reportButton=[UIButton buttonWithType:UIButtonTypeSystem];[self.reportButton setTitle:@"مشاركة تقرير المشكلة" forState:UIControlStateNormal];self.reportButton.tintColor=Cyan();[self.reportButton addTarget:self action:@selector(report) forControlEvents:UIControlEventTouchUpInside];[self.body addSubview:self.reportButton];
        self.kind=0;self.revision=NSUIntegerMax;self.body.hidden=YES;
    }return self;
}
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {for(UIView *v in self.subviews)if(!v.hidden&&v.alpha>.01&&[v pointInside:[self convertPoint:point toView:v] withEvent:event])return YES;return NO;}
- (void)tab:(UIButton *)button {
    self.skins=button.tag==3;if(button.tag==4)atomic_store(&AccountLinksConfigured,false);int original=(int)(button.tag==4?3:button.tag);if(self.skins)original=3;
    if(NinjaVerified){*(volatile int *)(NinjaBase+0x1113fc)=original;*(volatile unsigned char *)(NinjaBase+0x1113b8)=1;}
    self.body.hidden=!self.skins;self.revision=NSUIntegerMax;[self setNeedsLayout];[self tick];
}
- (void)star:(UIButton *)button {static const int codes[7]={105,109,107,101,104,108,106};atomic_store(&LeagueValue,codes[button.tag]);atomic_store(&LevelOn,1);Changed();[self setNeedsLayout];}
- (void)level:(UISlider *)slider {atomic_store(&LevelValue,(int)lroundf(slider.value));atomic_store(&LevelOn,1);Changed();self.valueLabel.text=[NSString stringWithFormat:@"%d",atomic_load(&LevelValue)];}
- (void)segment:(UISegmentedControl *)s {self.kind=s.selectedSegmentIndex;self.revision=NSUIntegerMax;[self rebuild];}
- (void)choose:(UIButton *)b {if(self.kind==0)atomic_store(&CueValue,(int)b.tag);else if(self.kind==1)atomic_store(&FrameValue,(int)b.tag);else atomic_store(&AvatarValue,(int)b.tag);atomic_store(&Dirty,true);self.revision=NSUIntegerMax;[self rebuild];}
- (void)restore {atomic_store(&LevelOn,0);atomic_store(&CueValue,-1);atomic_store(&FrameValue,-1);atomic_store(&AvatarValue,-1);Changed();self.revision=NSUIntegerMax;[self rebuild];}
- (void)report {Export();}
- (void)developer {[UIApplication.sharedApplication openURL:[NSURL URLWithString:@"https://t.me/YG8_1"] options:@{} completionHandler:nil];}
- (void)rebuild {
    NSArray *ids;NSDictionary *images;@synchronized(Lock){ids=[[IDs((int)self.kind) allObjects] sortedArrayUsingSelector:@selector(compare:)];images=[Images((int)self.kind) copy];}
    NSUInteger revision=ids.count*1000+images.count+(NSUInteger)self.kind*100000;
    if(revision==self.revision)return;self.revision=revision;
    for(UIView *v in self.tiles)[v removeFromSuperview];[self.tiles removeAllObjects];
    NSMutableArray *values=[NSMutableArray arrayWithObject:@(-1)];if(ids.count)[values addObjectsFromArray:ids];
    for(NSNumber *number in values){UIButton *b=[UIButton buttonWithType:UIButtonTypeCustom];b.tag=number.integerValue;b.layer.cornerRadius=7;b.clipsToBounds=YES;b.backgroundColor=[UIColor colorWithWhite:.18 alpha:1];b.imageView.contentMode=UIViewContentModeScaleAspectFit;
        if(number.intValue<0){[b setTitle:@"Off" forState:UIControlStateNormal];[b setTitleColor:UIColor.lightGrayColor forState:UIControlStateNormal];}
        else if(images[number]){[b setImage:images[number] forState:UIControlStateNormal];}
        else{[b setTitle:[NSString stringWithFormat:@"%@ · انتظار الصورة",number] forState:UIControlStateNormal];b.titleLabel.font=[UIFont systemFontOfSize:11];}
        [b addTarget:self action:@selector(choose:) forControlEvents:UIControlEventTouchUpInside];[self.body addSubview:b];[self.tiles addObject:b];
    }self.galleryTitle.text=@[@"Cue Skin",@"Avatar Frame",@"Avatar"][(NSUInteger)self.kind];[self setNeedsLayout];
}
- (void)layoutSubviews {
    [super layoutSubviews];CGFloat bw=self.bar.bounds.size.width/5,bh=self.bar.bounds.size.height;
    int native=NinjaVerified?*(volatile int *)(NinjaBase+0x1113fc):0;NSInteger selected=self.skins?3:native==3?4:native;
    for(UIButton *b in self.tabs){b.frame=CGRectMake(b.tag*bw,0,bw,bh);UIImageView *icon=(UIImageView *)[b viewWithTag:11];UILabel *title=(UILabel *)[b viewWithTag:12];UIView *line=[b viewWithTag:13];CGFloat ih=MIN(36,bh*.52);icon.frame=CGRectMake((bw-ih)/2,3,ih,ih);title.frame=CGRectMake(0,ih+4,bw,MAX(16,bh-ih-8));line.frame=CGRectMake(bw*.24,bh-2,bw*.52,2);BOOL on=b.tag==selected;icon.tintColor=on?Cyan():UIColor.grayColor;title.textColor=on?UIColor.whiteColor:UIColor.grayColor;line.hidden=!on;}
    CGFloat width=self.body.bounds.size.width,pad=14,inside=width-pad*2,y=8;
    self.profileTitle.frame=CGRectMake(pad,y,inside,24);y+=30;CGFloat cell=inside/7,starH=MIN(92,cell*.95);
    static const int codes[7]={105,109,107,101,104,108,106};
    for(UIButton *b in self.stars){b.frame=CGRectMake(pad+b.tag*cell,y,cell-5,starH);b.backgroundColor=atomic_load(&LevelOn)&&atomic_load(&LeagueValue)==codes[b.tag]?Cyan():UIColor.clearColor;}
    y+=starH+8;self.levelLabel.frame=CGRectMake(pad,y,inside/2,26);self.valueLabel.frame=CGRectMake(pad+inside/2,y,inside/2,26);self.valueLabel.text=[NSString stringWithFormat:@"%d",atomic_load(&LevelValue)];y+=29;
    self.slider.frame=CGRectMake(pad,y,inside,32);if(!self.slider.tracking)self.slider.value=(float)atomic_load(&LevelValue);y+=44;
    self.segments.frame=CGRectMake(pad,y,inside,42);y+=49;self.galleryTitle.frame=CGRectMake(pad,y,inside,24);y+=31;
    CGFloat gap=7,tileW=(inside-gap*2)/3,tileH=self.kind==0?MAX(56,MIN(88,tileW*.28)):MAX(75,MIN(115,tileW*.5));
    int chosen=self.kind==0?atomic_load(&CueValue):self.kind==1?atomic_load(&FrameValue):atomic_load(&AvatarValue);
    for(NSUInteger i=0;i<self.tiles.count;i++){UIButton *b=self.tiles[i];b.frame=CGRectMake(pad+(i%3)*(tileW+gap),y+(i/3)*(tileH+gap),tileW,tileH);b.layer.borderWidth=b.tag==chosen?2:0;b.layer.borderColor=Cyan().CGColor;}
    y+=ceil(self.tiles.count/3.0)*(tileH+gap)+8;
    NSString *status=Access()?@"تغييرات المظهر محلية. الصور من العناصر التي عُرضت على الجهاز.":@"التفعيل غير نشط؛ الخيارات لن تُطبّق حتى تفعيل الاشتراك.";
    self.note.text=[status stringByAppendingString:@"\nاعرض العناصر في اللعبة أو المتجر مرة واحدة لتظهر صورها هنا."];self.note.textColor=Access()?[UIColor colorWithWhite:.65 alpha:1]:[UIColor colorWithRed:1 green:.5 blue:.5 alpha:1];self.note.frame=CGRectMake(pad,y,inside,48);y+=50;
    self.restoreButton.frame=CGRectMake(pad,y,inside/2,36);self.reportButton.frame=CGRectMake(pad+inside/2,y,inside/2,36);y+=46;self.body.contentSize=CGSizeMake(width,y);
}
- (void)tick {
    FindNinja();InstallHooks();UIWindow *w=Window();if(!w||!NinjaVerified){self.hidden=YES;return;}
    if(self.superview!=w)[w addSubview:self];self.frame=w.bounds;
    BOOL visible=*(volatile unsigned char *)(NinjaBase+0x1113a5)&&*(volatile int *)(NinjaBase+0x1113f8)>0;
    self.hidden=!visible;if(!visible)return;
    MenuRect (*panel)(void)=(MenuRect(*)(void))(NinjaBase+0x9db40),(*content)(void)=(MenuRect(*)(void))(NinjaBase+0xa66b8);
    CGRect p=Convert(panel(),w),c=Convert(content(),w);if(!isfinite(p.origin.x)||!isfinite(c.origin.y)||p.size.width<100||p.size.height<100){self.hidden=YES;return;}
    CGFloat header=MAX(42,MIN(p.size.height*.30,c.origin.y-p.origin.y-3));self.bar.frame=CGRectMake(p.origin.x+6,p.origin.y+2,MAX(100,p.size.width-42),header+1);
    CGRect bodyRect=CGRectIntersection(CGRectMake(p.origin.x+5,p.origin.y+header+3,p.size.width-10,p.size.height-header-8),w.bounds);if(CGRectIsNull(bodyRect)||bodyRect.size.height<20){self.hidden=YES;return;}self.body.frame=bodyRect;self.body.hidden=!self.skins;[w bringSubviewToFront:self];
    self.ticks++;if(self.ticks%8==0&&self.skins)[self rebuild];[self setNeedsLayout];
}
@end
@interface SkinDeveloperLink : NSObject
+ (void)open;
@end
@implementation SkinDeveloperLink
+ (void)open {[UIApplication.sharedApplication openURL:[NSURL URLWithString:@"https://t.me/YG8_1"] options:@{} completionHandler:nil];}
@end
static char DeveloperWired;
static void WireLoginDeveloper(void){
    Class panel=objc_getClass("ActivationPanel");if(!panel)return;
    for(UIScene *scene in UIApplication.sharedApplication.connectedScenes){
        if(![scene isKindOfClass:UIWindowScene.class]||scene.activationState!=UISceneActivationStateForegroundActive)continue;
        for(UIWindow *window in ((UIWindowScene *)scene).windows){
            UIViewController *root=window.rootViewController;if(window.hidden||![root isKindOfClass:panel])continue;
            for(NSString *key in @[@"telegram",@"resellers"]){id control=ObjectCall(root,key.UTF8String);if(![control isKindOfClass:UIButton.class]||objc_getAssociatedObject(control,&DeveloperWired))continue;
            UIButton *button=control;[button removeTarget:root action:sel_registerName("openWebsite") forControlEvents:UIControlEventTouchUpInside];[button addTarget:SkinDeveloperLink.class action:@selector(open) forControlEvents:UIControlEventTouchUpInside];button.accessibilityLabel=@"المطور @YG8_1";objc_setAssociatedObject(button,&DeveloperWired,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
        }
    }
}
static SkinMenuView *Menu;
@interface SkinMenuClock : NSObject
+ (void)tick:(CADisplayLink *)link;
@end
@implementation SkinMenuClock
+ (void)tick:(CADisplayLink *)link {(void)link;WireLoginDeveloper();[Menu tick];}
@end
__attribute__((constructor)) static void Start(void){dispatch_async(dispatch_get_main_queue(),^{
    Lock=[NSObject new];CueDefinitions=[NSMutableDictionary dictionary];CueImages=[NSMutableDictionary dictionary];FrameImages=[NSMutableDictionary dictionary];AvatarImages=[NSMutableDictionary dictionary];CueIDs=[NSMutableSet set];FrameIDs=[NSMutableSet set];AvatarIDs=[NSMutableSet set];PendingImages=[NSMutableSet set];CaptureQueue=[NSMutableArray array];
    NSUserDefaults *p=NSUserDefaults.standardUserDefaults;int level=(int)[p integerForKey:@"SkinMenu.Level"];atomic_store(&LevelValue,level>=1&&level<=999?level:100);int league=(int)[p integerForKey:@"SkinMenu.League"];BOOL validLeague=league==105||league==109||league==107||league==101||league==104||league==108||league==106;atomic_store(&LeagueValue,validLeague?league:105);atomic_store(&LevelOn,(int)[p integerForKey:@"SkinMenu.LevelOn"]);atomic_store(&CueValue,-1);atomic_store(&FrameValue,-1);atomic_store(&AvatarValue,-1);
    Menu=[[SkinMenuView alloc]initWithFrame:CGRectZero];Menu.hidden=YES;CADisplayLink *clock=[CADisplayLink displayLinkWithTarget:SkinMenuClock.class selector:@selector(tick:)];clock.preferredFramesPerSecond=20;[clock addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
});}

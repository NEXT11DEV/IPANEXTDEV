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
#include <CommonCrypto/CommonDigest.h>
#import <ImageIO/ImageIO.h>
#include "ActivationDigest.h"

static NSObject *Lock;
static _Atomic int LevelOn,LevelValue,LeagueValue,CueValue,FrameValue,AvatarValue;
static _Thread_local BOOL Refreshing;
static void MarkDirty(void);
static _Atomic bool Dirty,CueCurrentlyOpponent,WantThumbnails,DiscoveryRequested;
static _Atomic bool IntegrityVerified;
static uintptr_t ActivationTextStart,ActivationTextEnd;
static _Atomic unsigned OwnMaxMicros,BaseMaxMicros,SlowOwnFrames;
static NSMapTable *ObservedNodes;
static NSMutableSet *ThumbnailPending,*ThumbnailMissing;
static _Atomic unsigned ThumbnailRequests,ThumbnailReady;
static void BootstrapStep(void);
static _Atomic unsigned CueCalls,StarCalls,HUDCalls,FrameCalls,AvatarCalls,DrawCalls,OffMainCalls;
static _Atomic bool LocalHUDFound;
static BOOL Access(void);
static NSMutableDictionary *CueImages,*FrameImages,*AvatarImages,*CueNativeIDs,*ThumbnailSources;
static uintptr_t MainBase;
static _Atomic unsigned CatalogCount;
static void LoadCueCatalogStep(void);
static int SelectedCueID(int fallback){int selected=atomic_load(&CueValue);NSNumber *native=nil;@synchronized(Lock){native=CueNativeIDs[@(selected)];}return Access()&&native?native.intValue:fallback;}

static __weak id LastLobby,LastTrophy;
static void (*OldTrophy)(id,SEL,id,id);
static _Atomic unsigned TrophyCalls;
static char LobbyArgsKey;
static _Thread_local unsigned LocalCueDepth;
static _Thread_local int CueRenderScope;
static _Atomic unsigned LobbyCalls,CueAppearanceApplied,CueRootCalls;
static __weak id LastCueWidget;
static void (*OldCueRoot)(id,SEL,id,int,BOOL);
static void ConfigureAccountLinks(void);

static _Atomic bool AccountLinksConfigured;
static void (*OldLobby)(id,SEL,id,id);
static void (*OldLobbyAvatar)(id,SEL),(*OldLobbyFrame)(id,SEL);
static void (*OldCueDefinition)(id,SEL,id,int,int,BOOL);
static int NativeLocalSide(id hud);
static id FieldObject(id object,const char *name);
static NSMutableSet *CueIDs,*FrameIDs,*AvatarIDs;

static __weak id LastCue,LastWidget,LastHUD,LastAvatar,ActualManager;
static void (*OldManagerCue)(id,SEL);
static void (*OldManagerStarted)(id,SEL,const void *);
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
static void MarkDirty(void){if(!Refreshing)atomic_store(&Dirty,true);}
static BOOL RawAccess(void){
    BOOL (*active)(void)=(BOOL(*)(void))dlsym(RTLD_DEFAULT,"ActivationAccessActive");uintptr_t address=(uintptr_t)active;
    return active&&address>=ActivationTextStart&&address<ActivationTextEnd&&active();
}
__attribute__((visibility("default"))) BOOL SkinFeatureAccess(void){return atomic_load(&IntegrityVerified)&&RawAccess();}
static BOOL Access(void){return SkinFeatureAccess();}
static void VerifyActivation(void){
    static const unsigned char expected[32]=ACTIVATION_TEXT_DIGEST;
    for(uint32_t i=0;i<_dyld_image_count();i++){
        const char *name=_dyld_get_image_name(i);if(!name||!strstr(name,"/ActivationKit.framework/ActivationKit"))continue;
        const struct mach_header_64 *h=(const struct mach_header_64 *)_dyld_get_image_header(i);if(h->magic!=MH_MAGIC_64)continue;
        const uint8_t *p=(const uint8_t *)h+sizeof(*h);
        for(uint32_t j=0;j<h->ncmds;j++){const struct load_command *cmd=(const struct load_command *)p;
            if(cmd->cmd==LC_SEGMENT_64){const struct segment_command_64 *seg=(const struct segment_command_64 *)p;const struct section_64 *sections=(const struct section_64 *)(seg+1);
                for(uint32_t k=0;k<seg->nsects;k++){const struct section_64 *section=&sections[k];if(strncmp(section->sectname,"__text",16)||section->size!=ACTIVATION_TEXT_SIZE)continue;
                    const unsigned char *code=(const unsigned char *)h+section->addr;unsigned char digest[CC_SHA256_DIGEST_LENGTH];CC_SHA256(code,(CC_LONG)section->size,digest);
                    if(!memcmp(digest,expected,32)){ActivationTextStart=(uintptr_t)code;ActivationTextEnd=ActivationTextStart+section->size;atomic_store(&IntegrityVerified,true);}return;
                }
            }p+=cmd->cmdsize;
        }
    }
}
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
    id info=ObjectCall(objc_getClass("UserInfo"),"sharedUserInfo");
    for(NSString *name in @[@"userId",@"miniclipId"]){id own=ObjectCall(info,name.UTF8String);if([own isKindOfClass:NSString.class]&&[(NSString *)own length]&&([own isEqual:playerID]||[own isEqual:offlineID]))return YES;}return NO;
}
static NSMutableSet *IDs(int kind) { return kind==0?CueIDs:kind==1?FrameIDs:AvatarIDs; }
static NSMutableDictionary *Images(int kind) { return kind==0?CueImages:kind==1?FrameImages:AvatarImages; }
static BOOL Known(int kind,int value) { if(value<0)return NO;@synchronized(Lock){return [IDs(kind) containsObject:@(value)];} }
static void Observe(int kind,int value,id node){
    if(value<0||value>10000000||!node)return;NSString *key=[NSString stringWithFormat:@"%d:%d",kind,value];
    @synchronized(Lock){[IDs(kind) addObject:@(value)];[ObservedNodes setObject:node forKey:key];}
}
static void MarkAvatar(id avatar) { if(avatar){objc_setAssociatedObject(avatar,&LocalKey,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);@synchronized(Lock){LastAvatar=avatar;}MarkDirty();} }
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
    if(result){objc_setAssociatedObject(result,&LocalKey,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);@synchronized(Lock){LastWidget=result;}MarkAvatar(ObjectCall(result,"playerAvatar"));MarkDirty();}
    return result;
}
static void NewCue(id self,SEL cmd,int cue,int level,BOOL opponent) {
    atomic_fetch_add(&CueCalls,1);if(!NSThread.isMainThread)atomic_fetch_add(&OffMainCalls,1);
    atomic_store(&CueCurrentlyOpponent,opponent);int previousScope=CueRenderScope;CueRenderScope=opponent?-1:1;
    if(!opponent){@synchronized(Lock){LastCue=self;OriginalCueID=cue;OriginalCueLevel=level;}LocalCueDepth++;}
    OldCue(self,cmd,opponent?cue:SelectedCueID(cue),level,opponent);
    id widget=FieldObject(self,"_cueWidget");
    if(widget){objc_setAssociatedObject(widget,&LocalKey,@(!opponent),OBJC_ASSOCIATION_RETAIN_NONATOMIC);if(!opponent){@synchronized(Lock){LastCueWidget=widget;}MarkDirty();}}
    if(!opponent)LocalCueDepth--;CueRenderScope=previousScope;
}
static void NewCueSetup(id self,SEL cmd,int cue,int level) {OldCueSetup(self,cmd,cue,level);}
static void NewCueDefinition(id self,SEL cmd,id definition,int product,int level,BOOL force) { OldCueDefinition(self,cmd,definition,product,level,force); }
static void NewCueRoot(id self,SEL cmd,id definition,int product,BOOL force){
    atomic_fetch_add(&CueRootCalls,1);
    
    BOOL local=CueRenderScope>0||(CueRenderScope==0&&Local(self));if(CueRenderScope!=0)objc_setAssociatedObject(self,&LocalKey,@(CueRenderScope>0),OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if(local){@synchronized(Lock){LastCueWidget=self;}}
    // Keep the game's own definition, gameplay scaling and product resolution.
    OldCueRoot(self,cmd,definition,product,force);
    if(local&&atomic_load(&CueValue)==product)atomic_fetch_add(&CueAppearanceApplied,1);
    Observe(0,product,ObjectCall(self,"getCueSprite"));
}
static void MarkLobbyAvatar(id self){Ivar field=class_getInstanceVariable(object_getClass(self),"_playerAvatar");const char *type=field?ivar_getTypeEncoding(field):NULL;if(type&&type[0]=='@')MarkAvatar(object_getIvar(self,field));}
static void NewLobbyAvatar(id self,SEL cmd){OldLobbyAvatar(self,cmd);MarkLobbyAvatar(self);}
static void NewLobbyFrame(id self,SEL cmd){OldLobbyFrame(self,cmd);MarkLobbyAvatar(self);}
static void UpdateLobbyView(id self,SEL cmd,id league,id level,BOOL trophy){
    if(trophy)atomic_fetch_add(&TrophyCalls,1);else atomic_fetch_add(&LobbyCalls,1);
    objc_setAssociatedObject(self,&LobbyArgsKey,@[league?:NSNull.null,level?:NSNull.null],OBJC_ASSOCIATION_RETAIN_NONATOMIC);@synchronized(Lock){if(trophy)LastTrophy=self;else LastLobby=self;}
    BOOL on=Access()&&atomic_load(&LevelOn);(trophy?OldTrophy:OldLobby)(self,cmd,on?@(atomic_load(&LeagueValue)):league,on?@(atomic_load(&LevelValue)):level);MarkLobbyAvatar(self);
}
static void NewLobby(id self,SEL cmd,id league,id level){UpdateLobbyView(self,cmd,league,level,NO);}
static void NewTrophy(id self,SEL cmd,id league,id level){UpdateLobbyView(self,cmd,league,level,YES);}
static void HUDStar(id self,SEL cmd,unsigned league,unsigned level,int side) {
    atomic_fetch_add(&HUDCalls,1);objc_setAssociatedObject(self,side==1?&HUD1ArgsKey:&HUD2ArgsKey,@[@(league),@(level)],OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    int nativeSide=NativeLocalSide(self);BOOL local=NO;@synchronized(Lock){if(LastHUD!=self){HUDSide=0;atomic_store(&LocalHUDFound,false);}LastHUD=self;if(nativeSide){HUDSide=nativeSide;atomic_store(&LocalHUDFound,true);}local=HUDSide==side;}
    if(local)MarkAvatar(FieldObject(self,side==1?"_player1Avatar":"_player2Avatar"));
    BOOL on=local&&Access()&&atomic_load(&LevelOn);
    (side==1?OldHUD1:OldHUD2)(self,cmd,on?(unsigned)atomic_load(&LeagueValue):league,on?(unsigned)atomic_load(&LevelValue):level);
}
static void NewHUD1(id self,SEL cmd,unsigned league,unsigned level){HUDStar(self,cmd,league,level,1);}
static void NewHUD2(id self,SEL cmd,unsigned league,unsigned level){HUDStar(self,cmd,league,level,2);}
static void NewHUDAllAvatar(id self,SEL cmd,id avatar,int fallback,id playerID,id offlineID,int selected,unsigned rank) {
    if(OwnID(playerID,offlineID)) {
        MarkAvatar(avatar);
        // Identify which player slot owns this avatar from the game's existing avatar properties.
        id p1=FieldObject(self,"_player1Avatar"),p2=FieldObject(self,"_player2Avatar");
        int side=avatar==p1?1:avatar==p2?2:0;
        if(side){@synchronized(Lock){LastHUD=self;HUDSide=side;}atomic_store(&LocalHUDFound,true);MarkDirty();}
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
    id candidate=nil;@synchronized(Lock){candidate=LastHUD;}if(candidate&&(atomic_load(&Dirty)||(!atomic_load(&LocalHUDFound)&&atomic_load(&DrawCalls)%30==0))){int inferred=NativeLocalSide(candidate);if(inferred){@synchronized(Lock){if(HUDSide!=inferred)MarkDirty();HUDSide=inferred;}atomic_store(&LocalHUDFound,true);}}
    if(!atomic_exchange(&Dirty,false))return;Refreshing=YES;
    id cue,widget,hud,avatar,lobby,trophy;int cueID,cueLevel,side;
    @synchronized(Lock){cue=LastCue;widget=LastWidget;hud=LastHUD;avatar=LastAvatar;lobby=LastLobby;trophy=LastTrophy;cueID=OriginalCueID;cueLevel=OriginalCueLevel;side=HUDSide;}
    BOOL access=Access(),on=access&&atomic_load(&LevelOn);
    NSArray *lp=lobby?objc_getAssociatedObject(lobby,&LobbyArgsKey):nil;
    if(lobby&&lp.count==2&&OldLobby)OldLobby(lobby,sel_registerName("updateUserLeagueStarForLeague:withLevel:"),on?@(atomic_load(&LeagueValue)):(lp[0]==NSNull.null?nil:lp[0]),on?@(atomic_load(&LevelValue)):(lp[1]==NSNull.null?nil:lp[1]));
    NSArray *tp=trophy?objc_getAssociatedObject(trophy,&LobbyArgsKey):nil;
    if(trophy&&tp.count==2&&OldTrophy)OldTrophy(trophy,sel_registerName("updateUserLeagueStarForLeague:withLevel:"),on?@(atomic_load(&LeagueValue)):(tp[0]==NSNull.null?nil:tp[0]),on?@(atomic_load(&LevelValue)):(tp[1]==NSNull.null?nil:tp[1]));
    NSArray *star=widget?objc_getAssociatedObject(widget,&StarArgsKey):nil;
    if(widget&&star.count==2&&OldStar)OldStar(widget,sel_registerName("setupStarWithLeague:andLevel:"),on?atomic_load(&LeagueValue):[star[0] intValue],on?atomic_load(&LevelValue):[star[1] intValue]);
    NSArray *hp=hud?objc_getAssociatedObject(hud,side==1?&HUD1ArgsKey:&HUD2ArgsKey):nil;
    if(hud&&hp.count==2&&side&&(side==1?OldHUD1:OldHUD2)){
        SEL selector=sel_registerName(side==1?"setupPlayer1StartForPlayerLeague:forPlayerRating:":"setupPlayer2StartForPlayerLeague:forPlayerRating:");
        // The installed original selector may be the alternate spelling on another build.
        (side==1?OldHUD1:OldHUD2)(hud,selector,on?(unsigned)atomic_load(&LeagueValue):[hp[0] unsignedIntValue],on?(unsigned)atomic_load(&LevelValue):[hp[1] unsignedIntValue]);
    }
    if(!atomic_load(&CueCurrentlyOpponent)&&cue&&OldCue){int previousScope=CueRenderScope;CueRenderScope=1;LocalCueDepth++;
        OldCue(cue,sel_registerName("setCueWidgetWithCueId:cueLevel:forOpponent:"),SelectedCueID(cueID),cueLevel,NO);
        LocalCueDepth--;CueRenderScope=previousScope;
    }
    NSArray *fp=avatar?objc_getAssociatedObject(avatar,&FrameArgsKey):nil;
    if(avatar&&fp.count==3&&OldFrame){int selected=atomic_load(&FrameValue);OldFrame(avatar,sel_registerName("loadAvatarFrameWithProductId:fallbackRank:andShouldUseShader:"),access&&Known(1,selected)?(unsigned)selected:[fp[0] unsignedIntValue],[fp[1] unsignedIntValue],[fp[2] boolValue]);}
    NSNumber *ap=avatar?objc_getAssociatedObject(avatar,&AvatarArgsKey):nil;
    if(avatar&&ap&&OldAvatar){int selected=atomic_load(&AvatarValue);OldAvatar(avatar,sel_registerName("loadWithAvatarID:"),access&&Known(2,selected)?selected:ap.intValue);}
    Refreshing=NO;
}
static void (*OldSlot1)(id,SEL,id,id,int,unsigned);
static void (*OldSlot2)(id,SEL,id,id,int,unsigned);
static void SlotAvatar(id self,SEL cmd,id player,id offline,int selected,unsigned rank,int side){
    if(OwnID(player,offline)){@synchronized(Lock){LastHUD=self;HUDSide=side;}atomic_store(&LocalHUDFound,true);MarkDirty();}
    (side==1?OldSlot1:OldSlot2)(self,cmd,player,offline,selected,rank);
}
static void NewSlot1(id self,SEL cmd,id p,id o,int s,unsigned r){SlotAvatar(self,cmd,p,o,s,r,1);}
static void NewSlot2(id self,SEL cmd,id p,id o,int s,unsigned r){SlotAvatar(self,cmd,p,o,s,r,2);}
static BOOL Args(Method m,const char *ret,const char **args,unsigned count){
    if(!m||method_getNumberOfArguments(m)!=count)return NO;char *t=method_copyReturnType(m);BOOL ok=t&&strcmp(t,ret)==0;free(t);
    for(unsigned i=0;i<count&&ok;i++){t=method_copyArgumentType(m,i);ok=t&&strcmp(t,args[i])==0;free(t);}return ok;
}
static id FieldObject(id object,const char *name){if(!object)return nil;Ivar ivar=class_getInstanceVariable(object_getClass(object),name);const char *type=ivar?ivar_getTypeEncoding(ivar):NULL;return type&&type[0]=='@'?object_getIvar(object,ivar):nil;}
static void NewManagerCue(id self,SEL cmd){@synchronized(Lock){ActualManager=self;}OldManagerCue(self,cmd);MarkDirty();}
static void NewManagerStarted(id self,SEL cmd,const void *event){@synchronized(Lock){ActualManager=self;}OldManagerStarted(self,cmd,event);}
static int NativeLocalSide(id hud){
    id manager=nil;@synchronized(Lock){manager=ActualManager;}if(!manager)manager=ObjectCall(objc_getClass("GameManager"),"sharedGameManager");
    id player=ObjectCall(manager,"player");if(!player)player=FieldObject(manager,"mPlayer");if(!hud||!player)return 0;
    // Slot rendering is a separate child, not the GameHUD that owns player identities.
    id owner=ObjectCall(manager,"gameHUD");if(!owner)owner=FieldObject(manager,"mGameHUD");
    id renderer=FieldObject(owner,"_gameHUDTwoPlayerGame");
    if(hud!=owner&&hud!=renderer)return 0;
    const char *args[]={"@",":","@"};const char *names[]={"isPlayer1:","isPlayer2:"};
    for(int i=0;i<2;i++){SEL sel=sel_registerName(names[i]);Method m=class_getInstanceMethod(object_getClass(owner),sel);if(Args(m,"B",args,3)&&((BOOL(*)(id,SEL,id))objc_msgSend)(owner,sel,player))return i+1;}
    id localID=FieldObject(player,"mId");for(int side=1;side<=2;side++){id slot=FieldObject(owner,side==1?"_player1":"_player2");if(slot==player)return side;id otherID=FieldObject(slot,"mId");if([localID isKindOfClass:NSString.class]&&[(NSString *)localID length]&&[localID isEqual:otherID])return side;}return 0;
}
static BOOL Install(const char *cn,const char *mn,BOOL meta,IMP replacement,IMP *old,const char *ret,const char **args,unsigned n){
    if(*old)return YES;Class cls=objc_getClass(cn);if(!cls)return NO;if(meta)cls=object_getClass(cls);SEL sel=sel_registerName(mn);Method m=class_getInstanceMethod(cls,sel);if(!Args(m,ret,args,n))return NO;
    *old=method_getImplementation(m);class_replaceMethod(cls,sel,replacement,method_getTypeEncoding(m));return YES;
}
// Read the source image rather than rendering live game nodes into an OpenGL texture.
static NSString *ThumbnailName(id node){
    id name=ObjectCall(node,"finalTextureName");if([name isKindOfClass:NSString.class]&&[name length])return name;
    id child=FieldObject(node,"mPlayerImage");name=ObjectCall(child,"finalTextureName");return [name isKindOfClass:NSString.class]?name:nil;
}
static UIImage *SmallThumbnail(NSData *data,NSString *path){
 CGImageSourceRef source=data?CGImageSourceCreateWithData((__bridge CFDataRef)data,NULL):CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path],NULL);if(!source)return nil;
 NSDictionary *options=@{(__bridge id)kCGImageSourceCreateThumbnailFromImageAlways:@YES,(__bridge id)kCGImageSourceThumbnailMaxPixelSize:@320,(__bridge id)kCGImageSourceCreateThumbnailWithTransform:@YES};CGImageRef image=CGImageSourceCreateThumbnailAtIndex(source,0,(__bridge CFDictionaryRef)options);CFRelease(source);if(!image)return nil;UIImage *result=[UIImage imageWithCGImage:image];CGImageRelease(image);return result;
}
static void ProcessCapture(void){
    if(!atomic_load(&WantThumbnails))return;
    NSNumber *value=nil;int kindFound=0;NSString *key=nil,*catalogSource=nil;id node=nil;
    @synchronized(Lock){
        if(ThumbnailPending.count>=4)return;
        for(int kind=0;kind<3&&!value;kind++)for(NSNumber *candidate in IDs(kind)){
            NSString *candidateKey=[NSString stringWithFormat:@"%d:%@",kind,candidate];
            if(Images(kind)[candidate]||[ThumbnailPending containsObject:candidateKey]||[ThumbnailMissing containsObject:candidateKey])continue;
            id observed=[ObservedNodes objectForKey:candidateKey];NSString *source=ThumbnailSources[candidateKey];if(observed||source.length){value=candidate;kindFound=kind;key=candidateKey;node=observed;catalogSource=source;break;}
        }
    }
    if(!value)return;NSString *name=catalogSource?:ThumbnailName(node);if(!name.length)return;
    @synchronized(Lock){[ThumbnailPending addObject:key];}
    NSString *sourceName=[name copy];int sourceKind=kindFound;NSNumber *sourceValue=value;NSString *sourceKey=key;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
        NSString *path=[sourceName hasPrefix:@"/"]?sourceName:[NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:sourceName];
        UIImage *local=SmallThumbnail(nil,path);
        if(local){@synchronized(Lock){Images(sourceKind)[sourceValue]=local;[ThumbnailPending removeObject:sourceKey];}atomic_fetch_add(&ThumbnailReady,1);return;}
        NSString *filename=sourceName.lastPathComponent;
        // Use only a cue filename actually requested by the game's sprite definition.
        if(![filename.pathExtension.lowercaseString isEqualToString:@"png"]){@synchronized(Lock){[ThumbnailPending removeObject:sourceKey];[ThumbnailMissing addObject:sourceKey];}return;}
        NSURLComponents *url=[NSURLComponents componentsWithString:@"https://v56-mobile-live-config.pool.miniclippt.com/client/40/"];
        url.path=[url.path stringByAppendingString:filename];NSURLRequest *request=[NSURLRequest requestWithURL:url.URL cachePolicy:NSURLRequestReturnCacheDataElseLoad timeoutInterval:12];
        atomic_fetch_add(&ThumbnailRequests,1);
        [[NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data,NSURLResponse *response,NSError *error){
            BOOL ok=!error&&[response isKindOfClass:NSHTTPURLResponse.class]&&((NSHTTPURLResponse *)response).statusCode==200&&data.length>0&&data.length<=3*1024*1024;
            UIImage *image=ok?SmallThumbnail(data,nil):nil;
            @synchronized(Lock){[ThumbnailPending removeObject:sourceKey];if(image)Images(sourceKind)[sourceValue]=image;else [ThumbnailMissing addObject:sourceKey];}
            if(image)atomic_fetch_add(&ThumbnailReady,1);
        }] resume];
    });
}
static void MaxCounter(_Atomic unsigned *counter,unsigned value){unsigned old=atomic_load(counter);while(value>old&&!atomic_compare_exchange_weak(counter,&old,value)){};}
static void NewDraw(id self,SEL cmd){
    unsigned frame=atomic_fetch_add(&DrawCalls,1);CFAbsoluteTime start=CFAbsoluteTimeGetCurrent();
    @autoreleasepool{ConfigureAccountLinks();BootstrapStep();LoadCueCatalogStep();RefreshOnRenderThread();if(frame%30==0)ProcessCapture();}
    CFAbsoluteTime after=CFAbsoluteTimeGetCurrent();unsigned own=(unsigned)MAX(0,(after-start)*1000000);MaxCounter(&OwnMaxMicros,own);if(own>50000)atomic_fetch_add(&SlowOwnFrames,1);
    OldDraw(self,cmd);MaxCounter(&BaseMaxMicros,(unsigned)MAX(0,(CFAbsoluteTimeGetCurrent()-after)*1000000));
}
static void InstallHooks(void){
    static BOOL complete;if(complete)return;
    const char *factory[]={"@",":"},*pair[]={"@",":","i","i"},*cue[]={"@",":","i","i","B"},*hud[]={"@",":","I","I"},*slot[]={"@",":","@","@","i","I"},*allAvatar[]={"@",":","@","i","@","@","i","I"},*frame[]={"@",":","I","I","B"},*avatar[]={"@",":","i"};
    const char *eventArgs[]={"@",":","r^v"};
    Install("GameManager","setActiveVisualCue",NO,(IMP)NewManagerCue,(IMP *)&OldManagerCue,"v",factory,2);
    Install("GameManager","networkEventGameStarted:",NO,(IMP)NewManagerStarted,(IMP *)&OldManagerStarted,"v",eventArgs,3);
    BOOL star=Install("MatchScreenPlayerWidget","setupStarWithLeague:andLevel:",NO,(IMP)NewStar,(IMP *)&OldStar,"v",pair,4);
    BOOL local=star&&Install("MatchScreenPlayerWidget","createLocalPlayerWidget",YES,(IMP)NewLocal,(IMP *)&OldLocalFactory,"@",factory,2);
    const char *definitionArgs[]={"@",":","@","i","i","B"},*lobbyArgs[]={"@",":","@","@"};
    const char *rootArgs[]={"@",":","@","i","B"};
    BOOL rootOK=Install("CueWidget","setupWithCueSpriteDefinition:productId:forceSpriteDef:",NO,(IMP)NewCueRoot,(IMP *)&OldCueRoot,"v",rootArgs,5);
    BOOL definitionOK=Install("CueWidget","setupWithCueSpriteDefinition:productId:cueLevel:forceSpriteDef:",NO,(IMP)NewCueDefinition,(IMP *)&OldCueDefinition,"v",definitionArgs,6);
    Install("TopBarUserProfileButton","updateUserAvatar",NO,(IMP)NewLobbyAvatar,(IMP *)&OldLobbyAvatar,"v",factory,2);
    Install("TopBarUserProfileButton","updateAvatarFrame",NO,(IMP)NewLobbyFrame,(IMP *)&OldLobbyFrame,"v",factory,2);
    BOOL trophyOK=Install("TopBarTrophyButton","updateUserLeagueStarForLeague:withLevel:",NO,(IMP)NewTrophy,(IMP *)&OldTrophy,"v",lobbyArgs,4);
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
    complete=draw&&cueOK&&rootOK&&definitionOK&&lobbyOK&&trophyOK&&h1&&h2&&local&&frameOK&&avatarOK&&OldSlot1&&OldSlot2&&OldHUDAllAvatar;
}
static UIWindow *Window(void){UIWindow *best=nil;for(UIScene *s in UIApplication.sharedApplication.connectedScenes){if(![s isKindOfClass:UIWindowScene.class]||s.activationState!=UISceneActivationStateForegroundActive)continue;for(UIWindow *w in ((UIWindowScene *)s).windows)if(!w.hidden&&w.alpha>.1&&w.rootViewController&&(!best||w.windowLevel>best.windowLevel||(w.windowLevel==best.windowLevel&&w.isKeyWindow)))best=w;}return best;}
static UIViewController *Top(void){UIViewController *v=Window().rootViewController;while(v.presentedViewController&&!v.presentedViewController.isBeingDismissed)v=v.presentedViewController;return v;}
static NSString *PNGSource(id object,int depth){
 if(depth>5)return nil;if([object isKindOfClass:NSString.class]){NSString *name=[object lastPathComponent];return [name hasPrefix:@"Shop_"]&&[name.pathExtension.lowercaseString isEqualToString:@"png"]?name:nil;}
 if([object isKindOfClass:NSDictionary.class]){NSUInteger count=0;for(id key in object){if(++count>64)break;NSString *found=PNGSource(object[key],depth+1);if(found)return found;}}
 if([object isKindOfClass:NSArray.class]){NSUInteger count=0;for(id value in object){if(++count>64)break;NSString *found=PNGSource(value,depth+1);if(found)return found;}}return nil;
}
static void LoadCueCatalogStep(void){
 static NSArray *rows;static NSUInteger index;static BOOL complete;static CFAbsoluteTime retry;
 if(complete||!MainBase||!NinjaVerified||!Access())return;
 id manager=nil;@synchronized(Lock){manager=ActualManager;}if(!manager)manager=ObjectCall(objc_getClass("GameManager"),"sharedGameManager");SEL started=sel_registerName("isGameStarted");if([manager respondsToSelector:started]&&((BOOL(*)(id,SEL))objc_msgSend)(manager,started))return;
 if(!rows){if(CFAbsoluteTimeGetCurrent()<retry)return;retry=CFAbsoluteTimeGetCurrent()+3;
  id config=ObjectCall(objc_getClass("MCConfigurationDataCpp"),"sharedMCConfigurationDataCpp");SEL table=sel_registerName("tableWithId:");const char *args[]={"@",":","@"};
  if(!Args(class_getInstanceMethod(object_getClass(config),table),"@",args,3))return;id result=((id(*)(id,SEL,id))objc_msgSend)(config,table,@"cueList");if(![result isKindOfClass:NSArray.class]||![result count])return;rows=result;
 }
 if(index>=rows.count||atomic_load(&CatalogCount)>=256){rows=nil;complete=YES;return;}
 id row=rows[index++];if(![row isKindOfClass:NSDictionary.class]||![row[@"id"]respondsToSelector:@selector(intValue)])return;int cue=[row[@"id"]intValue];if(cue<0||cue>1000000)return;
 int (*productForCue)(int,int)=(int(*)(int,int))(MainBase+0xa3d778);int product=productForCue(cue,-1);if(product<0||product>10000000)return;
 id (*spriteDefinition)(int,int,BOOL,id,BOOL)=(id(*)(int,int,BOOL,id,BOOL))(MainBase+0x8b8574);
 id definition=spriteDefinition(product,0,NO,nil,NO);NSString *source=PNGSource(definition,0)?:PNGSource(row,0);NSNumber *key=@(product);
 @synchronized(Lock){if(!CueNativeIDs[key])atomic_fetch_add(&CatalogCount,1);CueNativeIDs[key]=@(cue);[CueIDs addObject:key];if(source)ThumbnailSources[[NSString stringWithFormat:@"0:%d",product]]=source;}
}
static void FindNinja(void){
    static const unsigned char expected[16]={229,113,182,73,150,137,56,48,158,232,56,170,23,83,57,79};
    if(!MainBase){const struct mach_header_64 *h=(const struct mach_header_64 *)_dyld_get_image_header(0);if(h&&h->magic==MH_MAGIC_64){const uint8_t *p=(const uint8_t *)h+sizeof(*h);for(uint32_t j=0;j<h->ncmds;j++){const struct load_command *c=(const struct load_command *)p;if(c->cmd==LC_UUID&&!memcmp(((const struct uuid_command *)p)->uuid,EXPECTED_GAME_UUID,16)){MainBase=(uintptr_t)h;break;}p+=c->cmdsize;}}}
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
static void BootstrapStep(void){
    static NSMutableArray *queue;static NSUInteger index,visited;
    id lobby=nil,trophy=nil;@synchronized(Lock){lobby=LastLobby;trophy=LastTrophy;}
    if(lobby||trophy){queue=nil;atomic_store(&DiscoveryRequested,false);return;}
    if(!queue){if(!atomic_exchange(&DiscoveryRequested,false))return;id director=ObjectCall(objc_getClass("CCDirector"),"sharedDirector");queue=[NSMutableArray array];for(NSString *key in @[@"runningScene",@"notificationNode"]){id root=ObjectCall(director,key.UTF8String);if(root)[queue addObject:root];}index=visited=0;}
    Class a=objc_getClass("TopBarUserProfileButton"),b=objc_getClass("TopBarTrophyButton");id found=nil;
    for(unsigned step=0;step<24&&index<queue.count&&visited<768;step++,visited++){
        id node=queue[index++];if((a&&[node isKindOfClass:a])||(b&&[node isKindOfClass:b])){found=node;break;}
        id children=ObjectCall(node,"children");if([children conformsToProtocol:@protocol(NSFastEnumeration)])for(id child in children){if(queue.count>=1024)break;if(child)[queue addObject:child];}
    }
    if(found){queue=nil;SEL update=sel_registerName("updateUserInfo");const char *args[]={"@",":"};if(Args(class_getInstanceMethod(object_getClass(found),update),"v",args,2))((void(*)(id,SEL))objc_msgSend)(found,update);return;}
    if(index>=queue.count||visited>=768)queue=nil;
}
typedef struct {float x,y,w,h;} MenuRect;
static CGRect Convert(MenuRect r,UIWindow *w){int sw=*(volatile int *)(NinjaBase+0x1113b0),sh=*(volatile int *)(NinjaBase+0x1113b4);if(sw<1||sh<1)return CGRectZero;return CGRectMake(r.x*w.bounds.size.width/sw,r.y*w.bounds.size.height/sh,r.w*w.bounds.size.width/sw,r.h*w.bounds.size.height/sh);}
static UIColor *Cyan(void){return [UIColor colorWithRed:0 green:.94 blue:.95 alpha:1];}
static UIColor *Dark(void){return [UIColor colorWithRed:.075 green:.10 blue:.13 alpha:1];}
static UIImage *Asset(NSString *name){Dl_info d={0};if(!dladdr((const void *)Asset,&d)||!d.dli_fname)return nil;NSString *dir=[@(d.dli_fname) stringByDeletingLastPathComponent];return [UIImage imageWithContentsOfFile:[dir stringByAppendingPathComponent:name]];}
static void Changed(void){NSUserDefaults *p=NSUserDefaults.standardUserDefaults;[p setInteger:atomic_load(&CueValue) forKey:@"SkinMenu.Cue"];[p setInteger:atomic_load(&FrameValue) forKey:@"SkinMenu.Frame"];[p setInteger:atomic_load(&AvatarValue) forKey:@"SkinMenu.Avatar"];[p setInteger:atomic_load(&LevelOn) forKey:@"SkinMenu.LevelOn"];[p setInteger:atomic_load(&LevelValue) forKey:@"SkinMenu.Level"];[p setInteger:atomic_load(&LeagueValue) forKey:@"SkinMenu.League"];MarkDirty();atomic_store(&DiscoveryRequested,true);}
static void Export(void){
    NSDictionary *report=@{@"format":@"SkinMenu-8",@"cueCatalogCount":@(atomic_load(&CatalogCount)),@"cueApplication":@"Native VisualCue ID; no shop-definition substitution",@"updateHandling":@"Original v5 game executable; no update hooks",@"thumbnailRequests":@(atomic_load(&ThumbnailRequests)),@"thumbnailReady":@(atomic_load(&ThumbnailReady)),@"actualManagerCaptured":@(ActualManager!=nil),@"gameManagerPresent":@(ObjectCall(objc_getClass("GameManager"),"sharedGameManager")!=nil),@"localPlayerPresent":@(ObjectCall(ObjectCall(objc_getClass("GameManager"),"sharedGameManager"),"player")!=nil),@"activationTextVerified":@(atomic_load(&IntegrityVerified)),@"trophyHookInstalled":@(OldTrophy!=NULL),@"trophyCalls":@(atomic_load(&TrophyCalls)),@"ownFrameWorstMs":@(atomic_load(&OwnMaxMicros)/1000.0),@"gameFrameWorstMs":@(atomic_load(&BaseMaxMicros)/1000.0),@"ownSlowFrames":@(atomic_load(&SlowOwnFrames)),@"cueRootInstalled":@(OldCueRoot!=NULL),@"cueRootCalls":@(atomic_load(&CueRootCalls)),@"accountLinksConfigured":@(AccountLinksConfigured),@"lobbyHookInstalled":@(OldLobby!=NULL),@"cueDefinitionHookInstalled":@(OldCueDefinition!=NULL),@"lobbyCalls":@(atomic_load(&LobbyCalls)),@"cueAppearanceApplied":@(atomic_load(&CueAppearanceApplied)),@"displayLevel":@(atomic_load(&LevelValue)),@"displayLeague":@(atomic_load(&LeagueValue)),@"selectedCueProduct":@(atomic_load(&CueValue)),@"engineMatched":@(NinjaVerified),@"accessActive":@(Access()),@"levelEnabled":@(atomic_load(&LevelOn)),@"localHUDIdentified":@(atomic_load(&LocalHUDFound)),@"calls":@{@"cue":@(atomic_load(&CueCalls)),@"preMatchStar":@(atomic_load(&StarCalls)),@"matchStar":@(atomic_load(&HUDCalls)),@"frame":@(atomic_load(&FrameCalls)),@"avatar":@(atomic_load(&AvatarCalls)),@"draw":@(atomic_load(&DrawCalls)),@"offMain":@(atomic_load(&OffMainCalls))},@"scope":@"No user identifiers, tokens or keys; only renderer call counts and integration state",@"hooks":HookDescription};
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
@property(nonatomic,strong) NSArray<NSNumber *> *galleryValues;
@property(nonatomic) unsigned ticks;
@property(nonatomic) int previousNativeTab;
@property(nonatomic) BOOL previousAccess;
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
        self.slider=[UISlider new];self.slider.minimumValue=1;self.slider.maximumValue=999;self.slider.minimumTrackTintColor=Cyan();self.slider.maximumTrackTintColor=[UIColor colorWithWhite:.22 alpha:1];[self.slider addTarget:self action:@selector(levelPreview:) forControlEvents:UIControlEventValueChanged];[self.slider addTarget:self action:@selector(level:) forControlEvents:UIControlEventTouchUpInside|UIControlEventTouchUpOutside|UIControlEventTouchCancel];[self.body addSubview:self.slider];
        self.segments=[[UISegmentedControl alloc]initWithItems:@[@"Cue",@"Frame",@"Avatar"]];self.segments.selectedSegmentIndex=0;self.segments.selectedSegmentTintColor=Cyan();self.segments.backgroundColor=[UIColor colorWithWhite:.17 alpha:1];[self.segments setTitleTextAttributes:@{NSForegroundColorAttributeName:UIColor.whiteColor,NSFontAttributeName:[UIFont systemFontOfSize:17]} forState:UIControlStateNormal];[self.segments setTitleTextAttributes:@{NSForegroundColorAttributeName:UIColor.blackColor} forState:UIControlStateSelected];[self.segments addTarget:self action:@selector(segment:) forControlEvents:UIControlEventValueChanged];[self.body addSubview:self.segments];
        self.galleryTitle=[self label:@"Cue Skin" color:Cyan() size:16];[self.body addSubview:self.galleryTitle];self.note=[self label:@"تظهر هنا العناصر التي رصدتها اللعبة؛ المعاينة لا تعني امتلاك العنصر." color:[UIColor colorWithWhite:.7 alpha:1] size:12];self.note.numberOfLines=0;[self.body addSubview:self.note];self.tiles=[NSMutableArray array];
        self.restoreButton=[UIButton buttonWithType:UIButtonTypeSystem];[self.restoreButton setTitle:@"إرجاع المظهر الأصلي" forState:UIControlStateNormal];self.restoreButton.tintColor=Cyan();[self.restoreButton addTarget:self action:@selector(restore) forControlEvents:UIControlEventTouchUpInside];[self.body addSubview:self.restoreButton];
        self.reportButton=[UIButton buttonWithType:UIButtonTypeSystem];[self.reportButton setTitle:@"مشاركة تقرير المشكلة" forState:UIControlStateNormal];self.reportButton.tintColor=Cyan();[self.reportButton addTarget:self action:@selector(report) forControlEvents:UIControlEventTouchUpInside];[self.body addSubview:self.reportButton];
        self.kind=0;self.revision=NSUIntegerMax;self.body.hidden=YES;
    }return self;
}
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {for(UIView *v in self.subviews)if(!v.hidden&&v.alpha>.01&&[v pointInside:[self convertPoint:point toView:v] withEvent:event])return YES;return NO;}
- (void)tab:(UIButton *)button {
    self.skins=button.tag==3;if(button.tag==4)atomic_store(&AccountLinksConfigured,false);int original=(int)(button.tag==4?3:button.tag);if(self.skins)original=3;
    if(NinjaVerified){*(volatile int *)(NinjaBase+0x1113fc)=original;*(volatile unsigned char *)(NinjaBase+0x1113b8)=1;}
    self.body.hidden=!self.skins;if(self.skins)atomic_store(&DiscoveryRequested,true);self.revision=NSUIntegerMax;[self setNeedsLayout];[self tick];
}
- (void)star:(UIButton *)button {static const int codes[7]={105,109,107,101,104,108,106};atomic_store(&LeagueValue,codes[button.tag]);atomic_store(&LevelOn,1);Changed();[self setNeedsLayout];}
- (void)levelPreview:(UISlider *)slider {self.valueLabel.text=[NSString stringWithFormat:@"%d",(int)lroundf(slider.value)];}
- (void)level:(UISlider *)slider {atomic_store(&LevelValue,(int)lroundf(slider.value));atomic_store(&LevelOn,1);Changed();self.valueLabel.text=[NSString stringWithFormat:@"%d",atomic_load(&LevelValue)];}
- (void)segment:(UISegmentedControl *)s {self.kind=s.selectedSegmentIndex;self.galleryValues=nil;self.revision=NSUIntegerMax;[self rebuild];}
- (void)choose:(UIButton *)b {if(self.kind==0)atomic_store(&CueValue,(int)b.tag);else if(self.kind==1)atomic_store(&FrameValue,(int)b.tag);else atomic_store(&AvatarValue,(int)b.tag);Changed();self.revision=NSUIntegerMax;[self rebuild];}
- (void)restore {atomic_store(&LevelOn,0);atomic_store(&CueValue,-1);atomic_store(&FrameValue,-1);atomic_store(&AvatarValue,-1);Changed();self.revision=NSUIntegerMax;[self rebuild];}
- (void)report {Export();}
- (void)developer {[UIApplication.sharedApplication openURL:[NSURL URLWithString:@"https://t.me/YG8_1"] options:@{} completionHandler:nil];}
- (void)rebuild {
    NSArray *ids;NSDictionary *images;@synchronized(Lock){ids=[[IDs((int)self.kind) allObjects] sortedArrayUsingSelector:@selector(compare:)];images=[Images((int)self.kind) copy];}
    NSUInteger revision=ids.count*1000+images.count+(NSUInteger)self.kind*100000;
    if(revision==self.revision)return;self.revision=revision;
    NSMutableArray *values=[NSMutableArray arrayWithObject:@(-1)];for(NSNumber *value in ids)if(self.kind!=1||value.intValue>0)[values addObject:value];
    if([self.galleryValues isEqualToArray:values]&&self.tiles.count==values.count){for(UIButton *button in self.tiles){UIImage *image=images[@(button.tag)];if(image){[button setTitle:nil forState:UIControlStateNormal];[button setImage:image forState:UIControlStateNormal];}}[self setNeedsLayout];return;}
    self.galleryValues=[values copy];for(UIView *v in self.tiles)[v removeFromSuperview];[self.tiles removeAllObjects];
    for(NSNumber *number in values){UIButton *b=[UIButton buttonWithType:UIButtonTypeCustom];b.tag=number.integerValue;b.layer.cornerRadius=7;b.clipsToBounds=YES;b.backgroundColor=[UIColor colorWithWhite:.18 alpha:1];b.imageView.contentMode=UIViewContentModeScaleAspectFit;
        if(number.intValue<0){[b setTitle:@"Off" forState:UIControlStateNormal];[b setTitleColor:UIColor.lightGrayColor forState:UIControlStateNormal];}
        else if(images[number]){[b setImage:images[number] forState:UIControlStateNormal];b.accessibilityLabel=[NSString stringWithFormat:@"عنصر %@",number];}
        else{[b setTitle:[NSString stringWithFormat:@"%@ · المعاينة غير متاحة",number] forState:UIControlStateNormal];b.titleLabel.font=[UIFont systemFontOfSize:11];}
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
    y+=starH+8;self.levelLabel.frame=CGRectMake(pad,y,inside/2,26);self.valueLabel.frame=CGRectMake(pad+inside/2,y,inside/2,26);if(!self.slider.tracking)self.valueLabel.text=[NSString stringWithFormat:@"%d",atomic_load(&LevelValue)];y+=29;
    self.slider.frame=CGRectMake(pad,y,inside,32);if(!self.slider.tracking)self.slider.value=(float)atomic_load(&LevelValue);y+=44;
    self.segments.frame=CGRectMake(pad,y,inside,42);y+=49;self.galleryTitle.frame=CGRectMake(pad,y,inside,24);y+=31;
    CGFloat gap=7,tileW=(inside-gap*2)/3,tileH=self.kind==0?MAX(56,MIN(88,tileW*.28)):MAX(75,MIN(115,tileW*.5));
    int chosen=self.kind==0?atomic_load(&CueValue):self.kind==1?atomic_load(&FrameValue):atomic_load(&AvatarValue);
    for(NSUInteger i=0;i<self.tiles.count;i++){UIButton *b=self.tiles[i];b.frame=CGRectMake(pad+(i%3)*(tileW+gap),y+(i/3)*(tileH+gap),tileW,tileH);b.layer.borderWidth=b.tag==chosen?2:0;b.layer.borderColor=Cyan().CGColor;}
    y+=ceil(self.tiles.count/3.0)*(tileH+gap)+8;
    NSString *status=Access()?@"تغييرات المظهر محلية. القائمة تعرض العناصر التي رصدتها اللعبة فقط.":@"التفعيل غير نشط؛ الخيارات لن تُطبّق حتى تفعيل الاشتراك.";
    if(!atomic_load(&IntegrityVerified))status=@"تعذر التحقق من مكتبة التفعيل؛ شارك تقرير المشكلة.";self.note.text=[status stringByAppendingString:@"\nتظهر هنا العناصر التي رصدتها اللعبة؛ المعاينة لا تعني امتلاك العنصر."];self.note.textColor=Access()?[UIColor colorWithWhite:.65 alpha:1]:[UIColor colorWithRed:1 green:.5 blue:.5 alpha:1];self.note.frame=CGRectMake(pad,y,inside,48);y+=50;
    self.restoreButton.frame=CGRectMake(pad,y,inside/2,36);self.reportButton.frame=CGRectMake(pad+inside/2,y,inside/2,36);y+=46;self.body.contentSize=CGSizeMake(width,y);
}
- (void)tick {
    FindNinja();InstallHooks();UIWindow *w=Window();BOOL (*loginVisible)(void)=(BOOL(*)(void))dlsym(RTLD_DEFAULT,"ActivationLoginVisible");BOOL login=loginVisible&&(uintptr_t)loginVisible>=ActivationTextStart&&(uintptr_t)loginVisible<ActivationTextEnd&&loginVisible();if(!w||!NinjaVerified||login){self.hidden=YES;atomic_store(&WantThumbnails,false);return;}
    if(self.superview!=w)[w addSubview:self];self.frame=w.bounds;
    BOOL visible=*(volatile unsigned char *)(NinjaBase+0x1113a5)&&*(volatile int *)(NinjaBase+0x1113f8)>0;
    self.hidden=!visible;atomic_store(&WantThumbnails,visible&&self.skins);if(!visible)return;
    MenuRect (*panel)(void)=(MenuRect(*)(void))(NinjaBase+0x9db40),(*content)(void)=(MenuRect(*)(void))(NinjaBase+0xa66b8);
    CGRect p=Convert(panel(),w),c=Convert(content(),w);if(!isfinite(p.origin.x)||!isfinite(c.origin.y)||p.size.width<100||p.size.height<100){self.hidden=YES;return;}
    CGRect priorBar=self.bar.frame,priorBody=self.body.frame;CGFloat header=MAX(42,MIN(p.size.height*.30,c.origin.y-p.origin.y-3));self.bar.frame=CGRectMake(p.origin.x+6,p.origin.y+2,MAX(100,p.size.width-42),header+1);
    CGRect bodyRect=CGRectIntersection(CGRectMake(p.origin.x+5,p.origin.y+header+3,p.size.width-10,p.size.height-header-8),w.bounds);if(CGRectIsNull(bodyRect)||bodyRect.size.height<20){self.hidden=YES;return;}self.body.frame=bodyRect;self.body.hidden=!self.skins;[w bringSubviewToFront:self];
    self.ticks++;if(self.ticks%8==0&&self.skins)[self rebuild];int native=*(volatile int *)(NinjaBase+0x1113fc);BOOL active=Access();if(!CGRectEqualToRect(priorBar,self.bar.frame)||!CGRectEqualToRect(priorBody,self.body.frame)||native!=self.previousNativeTab||active!=self.previousAccess)[self setNeedsLayout];self.previousNativeTab=native;self.previousAccess=active;
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
    VerifyActivation();Lock=[NSObject new];ObservedNodes=[NSMapTable strongToWeakObjectsMapTable];ThumbnailPending=[NSMutableSet set];ThumbnailMissing=[NSMutableSet set];CueNativeIDs=[NSMutableDictionary dictionary];ThumbnailSources=[NSMutableDictionary dictionary];CueImages=[NSMutableDictionary dictionary];FrameImages=[NSMutableDictionary dictionary];AvatarImages=[NSMutableDictionary dictionary];CueIDs=[NSMutableSet set];FrameIDs=[NSMutableSet set];AvatarIDs=[NSMutableSet set];
    NSUserDefaults *p=NSUserDefaults.standardUserDefaults;int level=(int)[p integerForKey:@"SkinMenu.Level"];atomic_store(&LevelValue,level>=1&&level<=999?level:100);int league=(int)[p integerForKey:@"SkinMenu.League"];BOOL validLeague=league==105||league==109||league==107||league==101||league==104||league==108||league==106;atomic_store(&LeagueValue,validLeague?league:105);atomic_store(&LevelOn,(int)[p integerForKey:@"SkinMenu.LevelOn"]);for(int kind=0;kind<3;kind++){NSString *key=@[@"SkinMenu.Cue",@"SkinMenu.Frame",@"SkinMenu.Avatar"][kind];NSInteger value=[p objectForKey:key]?[p integerForKey:key]:-1;int chosen=value>=-1&&value<=10000000?(int)value:-1;if(kind==0)atomic_store(&CueValue,chosen);else if(kind==1)atomic_store(&FrameValue,chosen);else atomic_store(&AvatarValue,chosen);}
    Menu=[[SkinMenuView alloc]initWithFrame:CGRectZero];Menu.hidden=YES;CADisplayLink *clock=[CADisplayLink displayLinkWithTarget:SkinMenuClock.class selector:@selector(tick:)];clock.preferredFramesPerSecond=20;[clock addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
});}


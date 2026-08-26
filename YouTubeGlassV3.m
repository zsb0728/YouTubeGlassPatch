#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

// YouTube 21.33.6 — verified against two on-device hierarchy captures.
// Keep original YTPivotBarView/buttons/gestures. Official flags extend Feed behind the bar.
// Replace only the verified full-width UIBlurEffect and 20%-white item container visually.
static const void *kYTGBaseKey=&kYTGBaseKey,*kYTGLensKey=&kYTGLensKey;
static IMP gPivotLayoutIMP,gItemSetSelectedIMP; static BOOL gPivotHooked,gItemHooked;
static BOOL YTGYes(id s,SEL c){return YES;} static BOOL YTGNo(id s,SEL c){return NO;}
static BOOL YTGIsBool(Method m){if(!m||method_getNumberOfArguments(m)!=2)return NO;char*t=method_copyReturnType(m);BOOL ok=t&&(t[0]=='B'||t[0]=='c'||t[0]=='C');if(t)free(t);return ok;}
static BOOL YTGFlag(const char*n,BOOL*v){static const char*yes[]={"isFrostedPivotBarPermitted","isLiquidGlassAvailable","computeIsLiquidGlassAvailable","useLiquidGlassStyling","mainAppCoreClientEnableModernIaFrostedBottomBar","mainAppCoreClientEnableModernIaFrostedBottomBarStartupScheduler","mainAppCoreClientEnableModernIaFrostedPivotBar","mainAppCoreClientEnableModernIaFrostedPivotBarClipped","mainAppCoreClientEnableModernIaFrostedPivotBarInvalidateOnMarginChange","mainAppCoreClientEnableModernIaFrostedPivotBarUpdatedBackdrop","mainAppCoreClientIosEnableModernIaFrostedBottomBarFixForSearch","mainAppCoreClientScheduleModernIaFrostedPivotBarInitializationAfterStartup"};if(!strcmp(n,"optOutOfFrostedPivotBar")){*v=NO;return YES;}for(NSUInteger i=0;i<sizeof(yes)/sizeof(yes[0]);i++)if(!strcmp(n,yes[i])){*v=YES;return YES;}return NO;}
static void YTGHookFlags(Class c){unsigned n=0;Method*l=class_copyMethodList(c,&n);for(unsigned i=0;i<n;i++){BOOL v=NO;if(YTGFlag(sel_getName(method_getName(l[i])),&v)&&YTGIsBool(l[i]))method_setImplementation(l[i],v?(IMP)YTGYes:(IMP)YTGNo);}free(l);}
static void YTGEnableFlags(void){int n=objc_getClassList(NULL,0);if(n<=0)return;Class*c=(__unsafe_unretained Class*)calloc(n,sizeof(Class));n=objc_getClassList(c,n);for(int i=0;i<n;i++){YTGHookFlags(c[i]);YTGHookFlags(object_getClass(c[i]));}free(c);}
static BOOL YTGItem(UIView*v){return [NSStringFromClass(v.class)isEqualToString:@"YTPivotBarItemView"];}
static void YTGCollect(UIView*v,NSMutableArray*out){for(UIView*s in v.subviews){if(YTGItem(s)){if(!s.hidden&&s.alpha>.01&&s.bounds.size.width>20)[out addObject:s];}else if(s!=objc_getAssociatedObject(v,kYTGBaseKey)&&s!=objc_getAssociatedObject(v,kYTGLensKey))YTGCollect(s,out);}}
static BOOL YTGSelected(UIView*v){SEL s=sel_registerName("selected");return[v respondsToSelector:s]&&((BOOL(*)(id,SEL))objc_msgSend)(v,s);}
static void YTGClear(UIView*v){v.opaque=NO;v.backgroundColor=UIColor.clearColor;v.layer.backgroundColor=nil;}
static BOOL YTGDirectFullBlur(UIView*v,UIView*host){if(![v isKindOfClass:UIVisualEffectView.class])return NO;CGRect r=[v convertRect:v.bounds toView:host];return r.size.width>host.bounds.size.width*.9&&r.size.height>60&&r.size.height<100&&[((UIVisualEffectView*)v).effect isKindOfClass:UIBlurEffect.class];}
static __weak UIView *gYTGCurrentPivot; static CADisplayLink *gYTGGuardLink;
static UIVisualEffectView*YTGGlass(BOOL interactive) API_AVAILABLE(ios(26.0)){UIGlassEffect*e=[UIGlassEffect effectWithStyle:UIGlassEffectStyleClear];e.interactive=interactive;UIVisualEffectView*v=[[UIVisualEffectView alloc]initWithEffect:e];v.userInteractionEnabled=NO;v.opaque=NO;v.backgroundColor=UIColor.clearColor;v.layer.backgroundColor=nil;v.cornerConfiguration=[UICornerConfiguration capsuleConfiguration];return v;}
static void YTGRefreshGlass(UIVisualEffectView*v,BOOL interactive) API_AVAILABLE(ios(26.0)){if(!v)return;UIGlassEffect*e=[UIGlassEffect effectWithStyle:UIGlassEffectStyleClear];e.interactive=interactive;v.effect=e;YTGClear(v);v.cornerConfiguration=[UICornerConfiguration capsuleConfiguration];v.userInteractionEnabled=NO;}
static void YTGFailOpen(UIView*host){UIVisualEffectView*a=objc_getAssociatedObject(host,kYTGBaseKey),*b=objc_getAssociatedObject(host,kYTGLensKey);a.hidden=YES;b.hidden=YES;for(UIView*s in host.subviews)if(YTGDirectFullBlur(s,host)){s.hidden=NO;} }
static void YTGStyle(UIView*host) API_AVAILABLE(ios(26.0)){
 if(!host.window||host.bounds.size.width<300||host.bounds.size.height<60)return;
 NSMutableArray*items=[NSMutableArray array];YTGCollect(host,items);if(items.count<2||items.count>7){YTGFailOpen(host);return;}
 [items sortUsingComparator:^NSComparisonResult(UIView*a,UIView*b){CGRect x=[a convertRect:a.bounds toView:host],y=[b convertRect:b.bounds toView:host];return CGRectGetMinX(x)<CGRectGetMinX(y)?NSOrderedAscending:NSOrderedDescending;}];
 UIView*itemContainer=((UIView*)items.firstObject).superview;if(!itemContainer||itemContainer.superview!=host){YTGFailOpen(host);return;}
 UIVisualEffectView*officialBlur=nil;for(UIView*s in host.subviews)if(YTGDirectFullBlur(s,host)){officialBlur=(UIVisualEffectView*)s;break;}
 // Runtime guard from A/B capture: only mutate when direct button container and official 440x82 blur exist.
 if(!officialBlur){YTGFailOpen(host);return;}
 UIVisualEffectView*base=objc_getAssociatedObject(host,kYTGBaseKey),*lens=objc_getAssociatedObject(host,kYTGLensKey);
 if(!base){base=YTGGlass(NO);lens=YTGGlass(YES);[host insertSubview:base aboveSubview:officialBlur];[host insertSubview:lens aboveSubview:base];objc_setAssociatedObject(host,kYTGBaseKey,base,OBJC_ASSOCIATION_RETAIN_NONATOMIC);objc_setAssociatedObject(host,kYTGLensKey,lens,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
 YTGRefreshGlass(base,NO);YTGRefreshGlass(lens,YES);
 // Verified visual-only surfaces. Never change frames, interaction, gestures, ancestors, Feed, or player.
 officialBlur.hidden=YES;officialBlur.userInteractionEnabled=NO;YTGClear(host);YTGClear(itemContainer);
 for(UIView*s in host.subviews)if(s!=base&&s!=lens&&s!=officialBlur&&s!=itemContainer&&s.bounds.size.height<=2)YTGClear(s);
 gYTGCurrentPivot=host;
 CGFloat safe=host.safeAreaInsets.bottom;if(safe<1&&host.window)safe=host.window.safeAreaInsets.bottom;
 // 对齐 82pt 原底栏与抖音原生悬浮玻璃比例：62pt 胶囊，56pt 选中透镜。
 CGFloat h=62.0,side=24.0;CGRect capsule=CGRectMake(side,0.0,host.bounds.size.width-side*2.0,h);base.frame=capsule;base.hidden=NO;
 UIView*selected=items.firstObject;for(UIView*i in items)if(YTGSelected(i)){selected=i;break;}CGRect ir=[selected convertRect:selected.bounds toView:host];CGFloat lh=56.0;CGFloat x=MAX(CGRectGetMinX(capsule)+3,CGRectGetMinX(ir)+5),mx=MIN(CGRectGetMaxX(capsule)-3,CGRectGetMaxX(ir)-5);lens.frame=CGRectMake(x,3.0,MAX(28.0,mx-x),lh);lens.hidden=NO;
 [host insertSubview:base belowSubview:itemContainer];[host insertSubview:lens belowSubview:itemContainer];base.userInteractionEnabled=NO;lens.userInteractionEnabled=NO;host.clipsToBounds=NO;
}
static void YTGGuardTick(CADisplayLink*link){
 UIView*host=gYTGCurrentPivot;if(!host||!host.window||host.hidden||host.alpha<.01)return;
 // YouTube 在播放器返回的独立事务中会重开 blur/20% 白底，未必触发 pivot layout。
 // 只在它真的复发时调用已带结构守卫的 YTGStyle；稳定帧纯读取，不改布局。
 UIVisualEffectView*base=objc_getAssociatedObject(host,kYTGBaseKey);BOOL dirty=!base||base.hidden;
 if(!dirty)for(UIView*s in host.subviews)if(YTGDirectFullBlur(s,host)&&!s.hidden){dirty=YES;break;}
 if(!dirty){NSMutableArray*a=[NSMutableArray array];YTGCollect(host,a);UIView*c=a.count?((UIView*)a.firstObject).superview:nil;if(c&&c.backgroundColor&&CGColorGetAlpha(c.backgroundColor.CGColor)>.01)dirty=YES;}
 if(dirty&&@available(iOS 26.0,*))YTGStyle(host);
}
@interface YTGGuardRelay:NSObject @end
@implementation YTGGuardRelay
+(void)tick:(CADisplayLink*)link{YTGGuardTick(link);}
@end
static void YTGEnsureGuard(void){if(gYTGGuardLink)return;gYTGGuardLink=[CADisplayLink displayLinkWithTarget:YTGGuardRelay.class selector:@selector(tick:)];gYTGGuardLink.preferredFrameRateRange=CAFrameRateRangeMake(1,10,2);[gYTGGuardLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];}
static void YTGPivotLayout(UIView*self,SEL cmd){if(gPivotLayoutIMP)((void(*)(id,SEL))gPivotLayoutIMP)(self,cmd);if(@available(iOS 26.0,*)){YTGStyle(self);YTGEnsureGuard();}}
static UIView*YTGPivotAncestor(UIView*v){for(UIView*p=v.superview;p;p=p.superview)if([NSStringFromClass(p.class)isEqualToString:@"YTPivotBarView"])return p;return nil;}
static void YTGItemSetSelected(id self,SEL cmd,BOOL selected){if(gItemSetSelectedIMP)((void(*)(id,SEL,BOOL))gItemSetSelectedIMP)(self,cmd,selected);UIView*p=YTGPivotAncestor(self);if(p)dispatch_async(dispatch_get_main_queue(),^{[p setNeedsLayout];});}
static void YTGInstall(void){Class p=objc_getClass("YTPivotBarView");Method pm=p?class_getInstanceMethod(p,@selector(layoutSubviews)):NULL;if(pm&&!gPivotHooked){gPivotHooked=YES;gPivotLayoutIMP=method_getImplementation(pm);const char*t=method_getTypeEncoding(pm);if(!class_addMethod(p,@selector(layoutSubviews),(IMP)YTGPivotLayout,t))method_setImplementation(class_getInstanceMethod(p,@selector(layoutSubviews)),(IMP)YTGPivotLayout);}Class i=objc_getClass("YTPivotBarItemView");SEL ss=sel_registerName("setSelected:");Method sm=i?class_getInstanceMethod(i,ss):NULL;if(sm&&!gItemHooked){gItemHooked=YES;gItemSetSelectedIMP=method_getImplementation(sm);const char*t=method_getTypeEncoding(sm);if(!class_addMethod(i,ss,(IMP)YTGItemSetSelected,t))method_setImplementation(class_getInstanceMethod(i,ss),(IMP)YTGItemSetSelected);}}
__attribute__((constructor(101)))static void YTGStart(void){YTGEnableFlags();dispatch_async(dispatch_get_main_queue(),^{YTGInstall();for(NSNumber*d in @[@0.05,@0.2,@0.5,@1.0])dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(d.doubleValue*NSEC_PER_SEC)),dispatch_get_main_queue(),^{YTGInstall();});});}

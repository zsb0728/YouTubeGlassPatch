#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

static const void *kYTGlassKey = &kYTGlassKey;
static const void *kYTNativeTabKey = &kYTNativeTabKey;
static const void *kYTNativeDelegateKey = &kYTNativeDelegateKey;
static const void *kYTNativeControllerKey = &kYTNativeControllerKey;
static const void *kYTNativeWrapperKey = &kYTNativeWrapperKey;
static const void *kYTPortalKey = &kYTPortalKey;
static const void *kYTPortalSourceKey = &kYTPortalSourceKey;
static const void *kYTItemSignatureKey = &kYTItemSignatureKey;
static const void *kYTFeedKey = &kYTFeedKey;
static const void *kYTConfiguredKey = &kYTConfiguredKey;

@interface YTGWeakBox : NSObject
@property(nonatomic,weak) id value;
@end
@implementation YTGWeakBox @end

static __weak UIView *gYTPivot;
static __weak UIView *gYTWrapper;
static NSInteger gYTWatchControllerCount;
static BOOL gYTSystemTabHidden;
static BOOL gYTOverlayReady;
static __weak UIView *gYTWatchBranch;
static const void *kYTWatchActiveKey = &kYTWatchActiveKey;
static IMP gYTWatchWillAppearIMP;
static IMP gYTWatchWillDisappearIMP;
static IMP gYTWatchDidDisappearIMP;
static void InstallNativeTabBar(UIView *pivot);
static void SetPersistentSystemTabBarHidden(BOOL hidden,BOOL animated);
static BOOL PreparePortalForCurrentFeed(void);
static void StopPlaybackAfterWatchExit(id watchController);

@interface YTGPassThroughView : UIView
@property(nonatomic,weak) UITabBar *tabBar;
@end
@implementation YTGPassThroughView
- (UIView*)hitTest:(CGPoint)point withEvent:(UIEvent*)event {
    if(self.tabBar){CGPoint p=[self convertPoint:point toView:self.tabBar];if([self.tabBar pointInside:p withEvent:event])return [self.tabBar hitTest:p withEvent:event];}
    return nil;
}
@end

@interface YTGNativeTabDelegate : NSObject <UITabBarControllerDelegate>
@property(nonatomic,weak) UIView *pivot;
@property(nonatomic,strong) NSArray<UIView*> *pivotItems;
@property(nonatomic) BOOL syncing;
@end
@implementation YTGNativeTabDelegate
- (void)tabBarController:(UITabBarController*)controller didSelectViewController:(UIViewController*)viewController {
    if(self.syncing)return; NSInteger i=controller.selectedIndex;
    if(i<0||i>=(NSInteger)self.pivotItems.count)return;
    UIView *original=self.pivotItems[i]; SEL tap=sel_registerName("didTapButton"); SEL doTap=sel_registerName("doTap");
    if([original respondsToSelector:tap])((void(*)(id,SEL))objc_msgSend)(original,tap);
    else if([original respondsToSelector:doTap])((void(*)(id,SEL))objc_msgSend)(original,doTap);
}
@end
typedef NS_ENUM(NSInteger, YTGKind) { YTGKindPivot, YTGKindPivotItem, YTGKindChip, YTGKindChipBar, YTGKindHeader, YTGKindSubheader, YTGKindAsyncCollection };
typedef struct { Class cls; IMP original; YTGKind kind; } YTGHook;
static YTGHook gHooks[12]; static int gHookCount = 0;

static id NewNativeGlass(BOOL interactive) API_AVAILABLE(ios(26.0)) {
    Class cls = NSClassFromString(@"UIGlassEffect"); if (!cls) return nil;
    id effect = nil; SEL factory = sel_registerName("effectWithStyle:");
    if ([cls respondsToSelector:factory]) effect = ((id(*)(id,SEL,NSInteger))objc_msgSend)(cls,factory,0);
    if (!effect) {
        id obj = ((id(*)(id,SEL))objc_msgSend)(cls,@selector(alloc));
        SEL init = sel_registerName("initWithStyle:");
        if ([obj respondsToSelector:init]) effect = ((id(*)(id,SEL,NSInteger))objc_msgSend)(obj,init,0);
    }
    SEL setInteractive = sel_registerName("setInteractive:");
    if (effect && [effect respondsToSelector:setInteractive]) ((void(*)(id,SEL,BOOL))objc_msgSend)(effect,setInteractive,interactive);
    return effect;
}

static void ClearSurface(UIView *v) {
    if(!v)return;
    if(v.opaque)v.opaque=NO;
    if(v.backgroundColor&&![v.backgroundColor isEqual:UIColor.clearColor])v.backgroundColor=UIColor.clearColor;
    if(v.layer.backgroundColor)v.layer.backgroundColor=nil;
}

static UIVisualEffectView *GlassForHost(UIView *host, BOOL interactive) API_AVAILABLE(ios(26.0)) {
    UIVisualEffectView *ev = objc_getAssociatedObject(host,kYTGlassKey);
    if (!ev) {
        id effect = NewNativeGlass(interactive); if (!effect) return nil;
        ev = [[UIVisualEffectView alloc] initWithEffect:effect];
        ev.userInteractionEnabled = NO; ev.clipsToBounds = YES;
        ev.layer.cornerCurve = kCACornerCurveContinuous;
        [host insertSubview:ev atIndex:0];
        objc_setAssociatedObject(host,kYTGlassKey,ev,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return ev;
}

static BOOL IsProtectedContent(UIView *v) {
    if ([v isKindOfClass:UILabel.class] || [v isKindOfClass:UIImageView.class] || [v isKindOfClass:UIControl.class] || [v isKindOfClass:UIVisualEffectView.class]) return YES;
    NSString *n = NSStringFromClass(v.class);
    return [n containsString:@"Badge"] || [n containsString:@"Count"] || [n containsString:@"Indicator"] || [n containsString:@"Avatar"];
}

static void ClearStructuralBackdrops(UIView *root, NSInteger depth) {
    if (depth < 0) return;
    for (UIView *s in root.subviews) {
        if (s == objc_getAssociatedObject(root,kYTGlassKey) || IsProtectedContent(s)) continue;
        ClearSurface(s);
        ClearStructuralBackdrops(s,depth-1);
    }
}

static void ClearShortAncestors(UIView *host, CGFloat maxHeight) {
    UIView *p = host.superview;
    for (int i=0; i<4 && p; i++,p=p.superview) {
        if (p.bounds.size.width + 2 < host.bounds.size.width) break;
        ClearSurface(p);
        if (p.bounds.size.height > maxHeight) break;
    }
}

static void ClearBottomBarHierarchy(UIView *host) {
    UIView *pathChild=host, *p=host.superview;
    for(int level=0; p && level<7 && ![p isKindOfClass:UIWindow.class]; level++,pathChild=p,p=p.superview) {
        ClearSurface(p);if(p.clipsToBounds)p.clipsToBounds=NO;
        CGRect hostRect=[host convertRect:host.bounds toView:p];
        for(UIView *s in p.subviews) {
            if(s==pathChild || [s isKindOfClass:UICollectionView.class] || [s isKindOfClass:UIScrollView.class]) continue;
            CGRect overlap=CGRectIntersection(hostRect,s.frame);
            NSString *n=NSStringFromClass(s.class);
            if(!CGRectIsNull(overlap) && !CGRectIsEmpty(overlap) && (s.bounds.size.height<=180.0 || [n containsString:@"Background"] || [n containsString:@"Backdrop"])) ClearSurface(s);
        }
    }
}

static void CollectLargeScrollViews(UIView *v, UIWindow *w, NSMutableArray<UIScrollView*> *out) {
    if([v isKindOfClass:UIScrollView.class]) {
        CGRect r=[v convertRect:v.bounds toView:w];
        if(r.size.height>350.0 && r.size.width>w.bounds.size.width*.80) [out addObject:(UIScrollView*)v];
    }
    for(UIView *s in v.subviews) CollectLargeScrollViews(s,w,out);
}

static UIScrollView *MainFeedNearHost(UIView *host, BOOL below) {
    UIWindow *w=host.window; if(!w)return nil;
    NSMutableArray *a=[NSMutableArray array]; CollectLargeScrollViews(w,w,a);
    CGRect hr=[host convertRect:host.bounds toView:w]; UIScrollView *best=nil; CGFloat score=CGFLOAT_MAX;
    for(UIScrollView *s in a) {
        if([host isDescendantOfView:s] || [s isDescendantOfView:host])continue;
        CGRect r=[s convertRect:s.bounds toView:w];
        CGFloat gap=below ? fabs(CGRectGetMinY(r)-CGRectGetMaxY(hr)) : fabs(CGRectGetMaxY(r)-CGRectGetMinY(hr));
        if(gap<160.0 && gap<score){score=gap;best=s;}
    }
    return best;
}

static void ExtendFeedBehindBottomBar(UIView *host) {
    UIWindow *w=host.window; UIScrollView *feed=MainFeedNearHost(host,NO); if(!w||!feed)return;
    CGRect r=[feed convertRect:feed.bounds toView:w]; CGFloat target=CGRectGetMaxY(w.bounds);
    CGFloat delta=target-CGRectGetMaxY(r); if(delta<=1.0)return;
    CGRect f=feed.frame; f.size.height+=delta; feed.frame=f;
    UIEdgeInsets in=feed.contentInset; in.bottom=MAX(in.bottom,host.bounds.size.height+8.0); feed.contentInset=in;
    UIEdgeInsets si=feed.scrollIndicatorInsets; si.bottom=MAX(si.bottom,host.bounds.size.height+8.0); feed.scrollIndicatorInsets=si;
}

static void ExtendFeedBehindChipBar(UIView *host) {
    UIWindow *w=host.window; UIScrollView *feed=MainFeedNearHost(host,YES); if(!w||!feed)return;
    CGRect rr=[feed convertRect:feed.bounds toView:w];
    CGFloat target=MAX(0.0,w.safeAreaInsets.top-8.0);
    CGFloat delta=CGRectGetMinY(rr)-target; if(delta<=1.0||delta>360.0)return;
    for(UIView *p=feed; p && ![p isKindOfClass:UIWindow.class]; p=p.superview){ p.clipsToBounds=NO; ClearSurface(p); }
    CGRect f=feed.frame; f.origin.y-=delta; f.size.height+=delta; feed.frame=f;
    feed.backgroundColor=UIColor.clearColor; feed.opaque=NO;
}

static void UpdateSampledBackdrop(UIView *host, BOOL sampleAbove) { (void)host; (void)sampleAbove; }

static void FindMainCollections(UIView *v,UIView *app,UIView *pivot,NSMutableArray<UIScrollView*> *out) {
    NSString *n=NSStringFromClass(v.class);
    if([v isKindOfClass:UIScrollView.class] && [n isEqualToString:@"YTAsyncCollectionView"]) {
        CGRect r=[v convertRect:v.bounds toView:app];
        if(r.size.width>app.bounds.size.width*.9 && r.size.height>500.0 && CGRectGetMinY(r)<20.0 && CGRectGetMaxY(r)<=CGRectGetMinY(pivot.frame)+2.0) [out addObject:(UIScrollView*)v];
    }
    for(UIView *s in v.subviews) FindMainCollections(s,app,pivot,out);
}

static void ExtendRealFeedUnderPivot(UIView *pivot) {
    UIView *app=pivot.superview;if(![NSStringFromClass(app.class)isEqualToString:@"YTAppView"])return;
    YTGWeakBox*box=objc_getAssociatedObject(pivot,kYTFeedKey);UIScrollView*best=box.value;
    if(!best||!best.window){
        NSMutableArray*feeds=[NSMutableArray array];
        for(UIView*s in app.subviews)if(s!=pivot)FindMainCollections(s,app,pivot,feeds);
        CGFloat bestGap=CGFLOAT_MAX;best=nil;
        for(UIScrollView*f in feeds){CGRect r=[f convertRect:f.bounds toView:app];CGFloat gap=fabs(CGRectGetMaxY(r)-CGRectGetMinY(pivot.frame));if(gap<bestGap){bestGap=gap;best=f;}}
        if(!best||bestGap>4.0)return;
        if(!box){box=[YTGWeakBox new];objc_setAssociatedObject(pivot,kYTFeedKey,box,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}box.value=best;
    }
    UIView*node=best;
    while(node&&node!=app){
        UIView*superview=node.superview;if(!superview)break;
        CGPoint bottom=[app convertPoint:CGPointMake(0,CGRectGetMaxY(app.bounds)) toView:superview];
        CGRect f=node.frame;CGFloat newHeight=bottom.y-CGRectGetMinY(f);
        if(newHeight>f.size.height+.5){f.size.height=newHeight;node.frame=f;}
        if(node.clipsToBounds)node.clipsToBounds=NO;node=superview;
    }
    UIEdgeInsets in=best.contentInset;CGFloat bottom=MAX(in.bottom,pivot.bounds.size.height);if(fabs(in.bottom-bottom)>.5){in.bottom=bottom;best.contentInset=in;}
    UIEdgeInsets si=best.scrollIndicatorInsets;bottom=MAX(si.bottom,pivot.bounds.size.height);if(fabs(si.bottom-bottom)>.5){si.bottom=bottom;best.scrollIndicatorInsets=si;}
}

static BOOL ContainsPivotItem(UIView *v) {
    if([NSStringFromClass(v.class) isEqualToString:@"YTPivotBarItemView"])return YES;
    for(UIView *s in v.subviews)if(ContainsPivotItem(s))return YES;
    return NO;
}

static void CenterPivotContent(UIView *host) { (void)host; }

static BOOL IsInsidePivotBar(UIView *v) {
    for(UIView *p=v.superview;p;p=p.superview)if([NSStringFromClass(p.class)isEqualToString:@"YTPivotBarView"])return YES;
    return NO;
}

static CGRect gPivotGlassFrame = {{0,0},{0,0}};

static void StylePivotItem(UIView *item) {
    if(!IsInsidePivotBar(item))return;
    UIView *pivot=item.superview;
    while(pivot && ![NSStringFromClass(pivot.class)isEqualToString:@"YTPivotBarView"])pivot=pivot.superview;
    if(!pivot||CGRectIsEmpty(gPivotGlassFrame))return;
    item.transform=CGAffineTransformIdentity;
    CGFloat target=CGRectGetMidY(gPivotGlassFrame);
    for(UIView *s in item.subviews) {
        NSString *n=NSStringFromClass(s.class);
        BOOL visibleContent=[n isEqualToString:@"YTQTMButton"]||[n containsString:@"AccessibilityControl"]||[n containsString:@"IndicatorView"]||[n isEqualToString:@"YTTransferButton"];
        if(!visibleContent)continue;
        CGPoint c=[s.superview convertPoint:s.center toView:pivot];
        CGFloat baseY=c.y-s.transform.ty;
        CGFloat visualCorrection=[n containsString:@"IndicatorView"]?0.0:3.0;
        CGFloat delta=target-baseY+visualCorrection;
        s.transform=CGAffineTransformMakeTranslation(0,MAX(0.0,MIN(40.0,delta)));
    }
}

static UIButton *ButtonInPivotItem(UIView *item) {
    for(UIView *s in item.subviews)if([NSStringFromClass(s.class)isEqualToString:@"YTQTMButton"]&&s.bounds.size.width>20)return (UIButton*)s;
    return nil;
}

static void CollectPivotItems(UIView *v,NSMutableArray<UIView*> *out) {
    if([NSStringFromClass(v.class)isEqualToString:@"YTPivotBarItemView"]){
        CGRect r=v.frame; UIButton*b=ButtonInPivotItem(v);
        if(!v.hidden&&r.size.width>20&&r.size.height>=0&&b&&!b.hidden)[out addObject:v];
        return;
    }
    if([v isKindOfClass:UITabBar.class])return;
    for(UIView *s in v.subviews)CollectPivotItems(s,out);
}

static NSString*PivotSignature(NSArray<UIView*>*items){
    NSMutableString*s=[NSMutableString stringWithFormat:@"%lu|",(unsigned long)items.count];
    for(UIView*v in items){UIButton*b=ButtonInPivotItem(v);[s appendFormat:@"%@:%p|",b.currentTitle?:b.titleLabel.text?:@"",b.imageView.image];}
    return s;
}

static UIViewController *OwningViewController(UIView *v) {
    for(UIResponder *r=v;r;r=r.nextResponder)if([r isKindOfClass:UIViewController.class])return (UIViewController*)r;
    return nil;
}

static void SetPersistentSystemTabBarHidden(BOOL hidden,BOOL animated){
    UIView*pivot=gYTPivot;UITabBarController*controller=objc_getAssociatedObject(pivot,kYTNativeControllerKey);UIView*wrapper=gYTWrapper;if(!controller||!wrapper)return;BOOL changed=gYTSystemTabHidden!=hidden;gYTSystemTabHidden=hidden;
    SEL setHidden=sel_registerName("setTabBarHidden:animated:");if(changed&&[controller respondsToSelector:setHidden])((void(*)(id,SEL,BOOL,BOOL))objc_msgSend)(controller,setHidden,hidden,animated);else if(changed)controller.tabBar.hidden=hidden;
    UIView*app=pivot.superview;if(wrapper.superview==app){if(gYTWatchBranch&&gYTWatchBranch.superview==app)[app insertSubview:wrapper belowSubview:gYTWatchBranch];else if(hidden)[app sendSubviewToBack:wrapper];else if(gYTWatchControllerCount==0)[app bringSubviewToFront:wrapper];}
    wrapper.hidden=NO;wrapper.alpha=gYTOverlayReady?1.0:.01;wrapper.userInteractionEnabled=gYTOverlayReady&&!hidden;
}

static UIView*WatchBranchForController(id controller){
    UIView*app=gYTPivot.superview,*v=[controller view];if(!app||!v)return nil;while(v.superview&&v.superview!=app)v=v.superview;return v.superview==app?v:nil;
}

static void SendNoArgIfSupported(id target,const char*name){if(!target)return;SEL s=sel_registerName(name);if([target respondsToSelector:s])((void(*)(id,SEL))objc_msgSend)(target,s);}

static void StopPlaybackAfterWatchExit(id watchController){
    SendNoArgIfSupported(watchController,"pausePlayback");SendNoArgIfSupported(watchController,"internalPause");
    for(NSString*k in @[@"playbackController",@"playerController",@"player"]){@try{id obj=[watchController valueForKey:k];NSString*n=NSStringFromClass([obj class]);if([n containsString:@"Player"]||[n containsString:@"Playback"]){SendNoArgIfSupported(obj,"pausePlayback");SendNoArgIfSupported(obj,"pause");SendNoArgIfSupported(obj,"internalPause");}}@catch(__unused id e){}}
    for(UIResponder*r=gYTPivot;r;r=r.nextResponder){SendNoArgIfSupported(r,"pausePlayback");SendNoArgIfSupported(r,"pauseMiniplayer");SendNoArgIfSupported(r,"dismissWatchMiniBarView");}
}

static void WatchWillAppear(id self,SEL cmd,BOOL animated){
    if(![objc_getAssociatedObject(self,kYTWatchActiveKey)boolValue]){objc_setAssociatedObject(self,kYTWatchActiveKey,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);gYTWatchControllerCount++;}
    if(gYTWatchWillAppearIMP)((void(*)(id,SEL,BOOL))gYTWatchWillAppearIMP)(self,cmd,animated);gYTWatchBranch=WatchBranchForController(self);SetPersistentSystemTabBarHidden(YES,animated);
}

static void WatchWillDisappear(id self,SEL cmd,BOOL animated){
    if(gYTWatchWillDisappearIMP)((void(*)(id,SEL,BOOL))gYTWatchWillDisappearIMP)(self,cmd,animated);gYTWatchBranch=WatchBranchForController(self);PreparePortalForCurrentFeed();SetPersistentSystemTabBarHidden(NO,animated);
    id coordinator=[self transitionCoordinator];SEL animate=sel_registerName("animateAlongsideTransition:completion:");if([coordinator respondsToSelector:animate])((BOOL(*)(id,SEL,id,id))objc_msgSend)(coordinator,animate,nil,^(id context){SEL cancelled=sel_registerName("isCancelled");BOOL isCancelled=[context respondsToSelector:cancelled]&&((BOOL(*)(id,SEL))objc_msgSend)(context,cancelled);if(isCancelled)SetPersistentSystemTabBarHidden(YES,NO);else StopPlaybackAfterWatchExit(self);});
}

static void WatchDidDisappear(id self,SEL cmd,BOOL animated){
    if(gYTWatchDidDisappearIMP)((void(*)(id,SEL,BOOL))gYTWatchDidDisappearIMP)(self,cmd,animated);BOOL wasActive=[objc_getAssociatedObject(self,kYTWatchActiveKey)boolValue];if(!wasActive)return;
    StopPlaybackAfterWatchExit(self);objc_setAssociatedObject(self,kYTWatchActiveKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);gYTWatchControllerCount=MAX(0,gYTWatchControllerCount-1);gYTWatchBranch=nil;SetPersistentSystemTabBarHidden(NO,NO);
}

static void InstallWatchControllerHooks(void){
    Class cls=objc_getClass("YTWatchViewController");if(!cls)return;
    Method a=class_getInstanceMethod(cls,@selector(viewWillAppear:));if(a){gYTWatchWillAppearIMP=method_getImplementation(a);if(!class_addMethod(cls,@selector(viewWillAppear:),(IMP)WatchWillAppear,method_getTypeEncoding(a)))method_setImplementation(class_getInstanceMethod(cls,@selector(viewWillAppear:)),(IMP)WatchWillAppear);}
    Method b=class_getInstanceMethod(cls,@selector(viewWillDisappear:));if(b){gYTWatchWillDisappearIMP=method_getImplementation(b);if(!class_addMethod(cls,@selector(viewWillDisappear:),(IMP)WatchWillDisappear,method_getTypeEncoding(b)))method_setImplementation(class_getInstanceMethod(cls,@selector(viewWillDisappear:)),(IMP)WatchWillDisappear);}
    Method d=class_getInstanceMethod(cls,@selector(viewDidDisappear:));if(d){gYTWatchDidDisappearIMP=method_getImplementation(d);if(!class_addMethod(cls,@selector(viewDidDisappear:),(IMP)WatchDidDisappear,method_getTypeEncoding(d)))method_setImplementation(class_getInstanceMethod(cls,@selector(viewDidDisappear:)),(IMP)WatchDidDisappear);}
}

static UIView *EnsurePortal(UIViewController*vc,UIView*source){
    if(!source)return nil;UIView*portal=objc_getAssociatedObject(vc,kYTPortalKey);Class c=NSClassFromString(@"_UIPortalView");if(!c)return nil;
    if(!portal){
        SEL init=sel_registerName("initWithSourceView:");id obj=((id(*)(id,SEL))objc_msgSend)(c,@selector(alloc));portal=[obj respondsToSelector:init]?((id(*)(id,SEL,id))objc_msgSend)(obj,init,source):[[c alloc]initWithFrame:vc.view.bounds];
        portal.userInteractionEnabled=NO;portal.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;[vc.view insertSubview:portal atIndex:0];objc_setAssociatedObject(vc,kYTPortalKey,portal,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        for(NSString*k in @[@"setAllowsBackdropGroups:",@"setMatchesPosition:",@"setMatchesTransform:"]){SEL s=sel_registerName(k.UTF8String);if([portal respondsToSelector:s])((void(*)(id,SEL,BOOL))objc_msgSend)(portal,s,YES);}
        SEL alpha=sel_registerName("setMatchesAlpha:");if([portal respondsToSelector:alpha])((void(*)(id,SEL,BOOL))objc_msgSend)(portal,alpha,NO);
        SEL hit=sel_registerName("setAllowsHitTesting:");if([portal respondsToSelector:hit])((void(*)(id,SEL,BOOL))objc_msgSend)(portal,hit,NO);SEL hide=sel_registerName("setHidesSourceView:");if([portal respondsToSelector:hide])((void(*)(id,SEL,BOOL))objc_msgSend)(portal,hide,NO);
    }
    YTGWeakBox*box=objc_getAssociatedObject(vc,kYTPortalSourceKey);UIView*old=box.value;
    if(source!=old){SEL setSource=sel_registerName("setSourceView:");if([portal respondsToSelector:setSource]){[CATransaction begin];[CATransaction setDisableActions:YES];((void(*)(id,SEL,id))objc_msgSend)(portal,setSource,source);[CATransaction commit];}if(!box){box=[YTGWeakBox new];objc_setAssociatedObject(vc,kYTPortalSourceKey,box,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}box.value=source;}
    if(!CGRectEqualToRect(portal.frame,vc.view.bounds))portal.frame=vc.view.bounds;
    return portal;
}

static BOOL ContainsFeedCollection(UIView*v,UIView*app){
    if([NSStringFromClass(v.class)isEqualToString:@"YTAsyncCollectionView"]){CGRect r=[v convertRect:v.bounds toView:app];if(r.size.width>app.bounds.size.width*.82&&r.size.height>app.bounds.size.height*.35)return YES;}
    for(UIView*s in v.subviews)if(ContainsFeedCollection(s,app))return YES;return NO;
}

static UIView*CurrentFeedPortalSource(UIView*app,UIView*pivot,UIView*wrapper){
    for(UIView*s in app.subviews.reverseObjectEnumerator){if(s==pivot||s==wrapper||s==gYTWatchBranch)continue;NSString*n=NSStringFromClass(s.class);if([n isEqualToString:@"UILayoutContainerView"]&&ContainsFeedCollection(s,app))return s;}
    return nil;
}

static BOOL PreparePortalForCurrentFeed(void){
    UIView*pivot=gYTPivot,*app=pivot.superview,*wrapper=gYTWrapper;if(!pivot||!app||!wrapper)return NO;UITabBarController*controller=objc_getAssociatedObject(pivot,kYTNativeControllerKey);UIView*source=CurrentFeedPortalSource(app,pivot,wrapper);return source&&EnsurePortal(controller,source)!=nil;
}

static void ClearControllerLayers(UIView *v,UITabBar *bar){
    if(v==bar||[NSStringFromClass(v.class)containsString:@"Portal"])return;
    ClearSurface(v);
    for(UIView*s in v.subviews)ClearControllerLayers(s,bar);
}

static void InstallNativeTabBar(UIView *pivot) {
    NSMutableArray<UIView*>*pivotItems=[NSMutableArray array];CollectPivotItems(pivot,pivotItems);
    [pivotItems sortUsingComparator:^NSComparisonResult(UIView*a,UIView*b){CGRect ar=[a convertRect:a.bounds toView:pivot],br=[b convertRect:b.bounds toView:pivot];return CGRectGetMinX(ar)<CGRectGetMinX(br)?NSOrderedAscending:NSOrderedDescending;}];
    if(pivotItems.count<2)return;
    UITabBarController*controller=objc_getAssociatedObject(pivot,kYTNativeControllerKey);YTGNativeTabDelegate*delegate=objc_getAssociatedObject(pivot,kYTNativeDelegateKey);BOOL created=controller==nil;
    if(created){
        controller=[UITabBarController new];delegate=[YTGNativeTabDelegate new];delegate.pivot=pivot;controller.delegate=delegate;
        UIView*app=pivot.superview;UIViewController*owner=OwningViewController(app);if(owner)[owner addChildViewController:controller];
        YTGPassThroughView*w=[[YTGPassThroughView alloc]initWithFrame:app.bounds];w.backgroundColor=UIColor.clearColor;w.opaque=NO;w.alpha=.01;w.userInteractionEnabled=NO;w.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;gYTOverlayReady=NO;
        controller.view.frame=w.bounds;controller.view.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;[w addSubview:controller.view];[app addSubview:w];if(owner)[controller didMoveToParentViewController:owner];
        UITabBar*bar=controller.tabBar;w.tabBar=bar;objc_setAssociatedObject(pivot,kYTNativeWrapperKey,w,OBJC_ASSOCIATION_RETAIN_NONATOMIC);objc_setAssociatedObject(pivot,kYTNativeControllerKey,controller,OBJC_ASSOCIATION_RETAIN_NONATOMIC);objc_setAssociatedObject(pivot,kYTNativeTabKey,bar,OBJC_ASSOCIATION_ASSIGN);objc_setAssociatedObject(pivot,kYTNativeDelegateKey,delegate,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    NSString*sig=PivotSignature(pivotItems);NSString*oldSig=objc_getAssociatedObject(pivot,kYTItemSignatureKey);BOOL rebuild=created||controller.viewControllers.count!=pivotItems.count||![sig isEqualToString:oldSig];NSInteger selected=NSNotFound;
    for(NSUInteger i=0;i<pivotItems.count;i++){UIView*original=pivotItems[i];SEL selectedSEL=sel_registerName("selected");if([original respondsToSelector:selectedSEL]&&((BOOL(*)(id,SEL))objc_msgSend)(original,selectedSEL))selected=i;}
    if(rebuild){
        NSMutableArray*controllers=[NSMutableArray arrayWithCapacity:pivotItems.count];
        for(NSUInteger i=0;i<pivotItems.count;i++){UIView*original=pivotItems[i];UIButton*b=ButtonInPivotItem(original);UIImage*image=b.imageView.image;NSString*title=b.currentTitle?:b.titleLabel.text?:@"";BOOL avatar=[title isEqualToString:@"我"]||[title localizedCaseInsensitiveContainsString:@"you"];UIImageRenderingMode mode=avatar?UIImageRenderingModeAlwaysOriginal:UIImageRenderingModeAlwaysTemplate;UIViewController*vc=[UIViewController new];UIImage*rendered=[image imageWithRenderingMode:mode];vc.view.backgroundColor=UIColor.clearColor;vc.view.opaque=NO;vc.tabBarItem=[[UITabBarItem alloc]initWithTitle:title image:rendered tag:(NSInteger)i];vc.tabBarItem.selectedImage=rendered;[controllers addObject:vc];}
        delegate.syncing=YES;controller.viewControllers=controllers;delegate.syncing=NO;objc_setAssociatedObject(pivot,kYTItemSignatureKey,sig,OBJC_ASSOCIATION_COPY_NONATOMIC);
    }
    delegate.pivotItems=pivotItems;if(selected!=NSNotFound&&controller.selectedIndex!=selected){delegate.syncing=YES;controller.selectedIndex=selected;delegate.syncing=NO;}
    UIView*app=pivot.superview;YTGPassThroughView*w=objc_getAssociatedObject(pivot,kYTNativeWrapperKey);gYTPivot=pivot;gYTWrapper=w;if(w.superview!=app)return;if(!CGRectEqualToRect(w.frame,app.bounds))w.frame=app.bounds;
    if(gYTWatchBranch&&gYTWatchBranch.superview==app)[app insertSubview:w belowSubview:gYTWatchBranch];else if(gYTSystemTabHidden)[app sendSubviewToBack:w];else[app bringSubviewToFront:w];w.hidden=NO;
    if(!CGRectEqualToRect(controller.view.frame,w.bounds))controller.view.frame=w.bounds;UITabBar*bar=controller.tabBar;w.tabBar=bar;
    if(created||rebuild){ClearControllerLayers(controller.view,bar);[controller.view setNeedsLayout];[controller.view layoutIfNeeded];}
    BOOL portalReady=gYTOverlayReady||(gYTWatchControllerCount==0&&PreparePortalForCurrentFeed());if(portalReady&&!gYTOverlayReady){[controller.view setNeedsLayout];[controller.view layoutIfNeeded];[CATransaction flush];[CATransaction begin];[CATransaction setDisableActions:YES];gYTOverlayReady=YES;for(UIView*original in pivotItems){original.alpha=.01;original.userInteractionEnabled=NO;}w.alpha=1.0;w.userInteractionEnabled=!gYTSystemTabHidden;[CATransaction commit];[CATransaction flush];}else if(gYTOverlayReady){for(UIView*original in pivotItems){original.alpha=.01;original.userInteractionEnabled=NO;}w.alpha=1.0;w.userInteractionEnabled=!gYTSystemTabHidden;}else{for(UIView*original in pivotItems){original.alpha=1.0;original.userInteractionEnabled=YES;}w.alpha=.01;w.userInteractionEnabled=NO;}
    SetPersistentSystemTabBarHidden(gYTWatchControllerCount>0,NO);
}

static void StylePivot(UIView *host) API_AVAILABLE(ios(26.0)) {
    ExtendRealFeedUnderPivot(host);ClearSurface(host);ClearShortAncestors(host,260.0);
    if(![objc_getAssociatedObject(host,kYTConfiguredKey)boolValue]){ClearBottomBarHierarchy(host);objc_setAssociatedObject(host,kYTConfiguredKey,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
    UIView*oldGlass=objc_getAssociatedObject(host,kYTGlassKey);if(oldGlass){[oldGlass removeFromSuperview];objc_setAssociatedObject(host,kYTGlassKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
    if(host.clipsToBounds)host.clipsToBounds=NO;InstallNativeTabBar(host);
}

static void TintGlass(UIVisualEffectView *ev, BOOL selected) { (void)ev; (void)selected; }

static void StyleChip(UIView *host) API_AVAILABLE(ios(26.0)) {
    if (host.bounds.size.width<28 || host.bounds.size.width>260 || host.bounds.size.height<24 || host.bounds.size.height>64) return;
    ClearSurface(host); ClearStructuralBackdrops(host,2);
    UIVisualEffectView *ev = GlassForHost(host,YES); if (!ev) return;
    ev.alpha=1.0;
    ev.frame=host.bounds; ev.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    ev.layer.cornerRadius=MIN(host.bounds.size.height/2.0,16.0);
    TintGlass(ev,[host isKindOfClass:UIControl.class] ? ((UIControl*)host).selected : NO);
    [host sendSubviewToBack:ev];
}

static void StyleChipBar(UIView *host) API_AVAILABLE(ios(26.0)) {
    ClearSurface(host); ClearShortAncestors(host,240.0);
    UpdateSampledBackdrop(host,NO);
    for (UIView *p=host.superview; p && ![p isKindOfClass:UIWindow.class]; p=p.superview) {
        if(p.bounds.size.height>260.0) break;
        ClearSurface(p);
    }
    for (UIView *s in host.subviews) {
        ClearSurface(s);
        if([s isKindOfClass:UICollectionView.class]) {
            UICollectionView *cv=(UICollectionView*)s; cv.backgroundView=nil; cv.backgroundColor=UIColor.clearColor; cv.opaque=NO;
        }
    }
}

static void ClearSubheaderTree(UIView *v) {
    if([v isKindOfClass:UILabel.class]||[v isKindOfClass:UIImageView.class]||[v isKindOfClass:UIVisualEffectView.class])return;
    NSString *n=NSStringFromClass(v.class);
    BOOL chip=[n containsString:@"ChipView"]||[n containsString:@"ChipCell"];
    if(!chip)ClearSurface(v); v.opaque=NO;
    if([v isKindOfClass:UICollectionViewCell.class])ClearSurface(((UICollectionViewCell*)v).contentView);
    for(UIView *s in v.subviews)ClearSubheaderTree(s);
}

static BOOL IsSubheaderCollection(UIView *v) {
    if(v.bounds.size.height>70.0)return NO;
    for(UIView *p=v.superview;p;p=p.superview){
        NSString *n=NSStringFromClass(p.class);
        if([n isEqualToString:@"YTSubheaderContainerView"])return YES;
        if(p.bounds.size.height>180.0)return NO;
    }
    return NO;
}

static void StyleAsyncCollection(UIView *v) {
    if(!IsSubheaderCollection(v))return;
    UICollectionView *cv=(UICollectionView*)v; cv.backgroundView=nil; cv.backgroundColor=UIColor.clearColor; cv.opaque=NO;
    for(UIView *s in cv.subviews)ClearSubheaderTree(s);
}

static void StyleSubheader(UIView *host) {
    ClearSurface(host); host.opaque=NO;
    for(UIView *s in host.subviews) {
        ClearSurface(s); s.opaque=NO;
        if([s isKindOfClass:UICollectionView.class]) {
            UICollectionView *cv=(UICollectionView*)s; cv.backgroundView=nil; cv.backgroundColor=UIColor.clearColor; cv.opaque=NO;
        }
    }
    UIView *p=host.superview;
    if(p && p.bounds.size.height<=160.0){ClearSurface(p);p.opaque=NO;}
}

static void GlassHeaderControls(UIView *root) API_AVAILABLE(ios(26.0)) {
    for (UIView *s in root.subviews) {
        if ([s isKindOfClass:UIControl.class] && s.bounds.size.width>=28 && s.bounds.size.width<=64 && s.bounds.size.height>=28 && s.bounds.size.height<=64) {
            ClearSurface(s); UIVisualEffectView *ev=GlassForHost(s,YES);
            if (ev) { ev.frame=s.bounds; ev.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight; ev.layer.cornerRadius=MIN(s.bounds.size.width,s.bounds.size.height)/2.0; [s sendSubviewToBack:ev]; }
        } else if (![s isKindOfClass:UILabel.class] && ![s isKindOfClass:UIImageView.class]) GlassHeaderControls(s);
    }
}

static void StyleHeader(UIView *host) API_AVAILABLE(ios(26.0)) {
    ClearSurface(host);
    @try { id shadow=[host valueForKey:@"shadowView"]; if ([shadow isKindOfClass:UIView.class]) ((UIView*)shadow).hidden=YES; } @catch (__unused id e) {}
    UIView *right=nil;
    @try { id v=[host valueForKey:@"rightButtonBar"]; if ([v isKindOfClass:UIView.class]) right=v; } @catch (__unused id e) {}
    if (right && right.bounds.size.width>=60 && right.bounds.size.height>=28) {
        ClearSurface(right); ClearStructuralBackdrops(right,1);
        UIVisualEffectView *ev=GlassForHost(right,YES);
        if(ev){ ev.frame=CGRectInset(right.bounds,-2.0,-2.0); ev.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight; ev.layer.cornerRadius=(right.bounds.size.height+4.0)/2.0; ev.layer.masksToBounds=YES; ev.layer.borderWidth=.5; ev.layer.borderColor=[UIColor colorWithWhite:1 alpha:.16].CGColor; [right sendSubviewToBack:ev]; }
    } else GlassHeaderControls(host);
}

static YTGHook *HookForObject(id obj) {
    for (int i=0;i<gHookCount;i++) if ([obj isKindOfClass:gHooks[i].cls]) return &gHooks[i];
    return NULL;
}

static void ApplyKind(UIView *v,YTGKind kind) {
    if (@available(iOS 26.0,*)) {
        switch(kind) { case YTGKindPivot: StylePivot(v); break; case YTGKindPivotItem: StylePivotItem(v); break; case YTGKindChip: StyleChip(v); break; case YTGKindChipBar: StyleChipBar(v); break; case YTGKindHeader: StyleHeader(v); break; case YTGKindSubheader: StyleSubheader(v); break; case YTGKindAsyncCollection: StyleAsyncCollection(v); break; }
    }
}

static void HookedLayout(UIView *self,SEL cmd) {
    YTGHook *h=HookForObject(self); if (h && h->original) ((void(*)(id,SEL))h->original)(self,cmd);
    if (h) ApplyKind(self,h->kind);
}

static void InstallHook(const char *name,YTGKind kind) {
    Class cls=objc_getClass(name); if(!cls || gHookCount>=12) return;
    unsigned count=0; Method *list=class_copyMethodList(cls,&count); Method own=NULL;
    for(unsigned i=0;i<count;i++) if(method_getName(list[i])==@selector(layoutSubviews)){own=list[i];break;}
    free(list); if(!own)return;
    gHooks[gHookCount++] = (YTGHook){cls,method_getImplementation(own),kind};
    method_setImplementation(own,(IMP)HookedLayout);
}

static void Scan(UIView *v) {
    YTGHook *h=HookForObject(v); if(h)ApplyKind(v,h->kind);
    for(UIView *s in v.subviews)Scan(s);
}
static void ScanWindows(void) {
    for(UIScene *scene in UIApplication.sharedApplication.connectedScenes) if([scene isKindOfClass:UIWindowScene.class]) for(UIWindow *w in ((UIWindowScene*)scene).windows)Scan(w);
}

__attribute__((constructor)) static void StartYouTubeGlassV3(void) {
    dispatch_async(dispatch_get_main_queue(),^{
        InstallWatchControllerHooks();
        InstallHook("YTPivotBarView",YTGKindPivot);
        InstallHook("YTChipCloudChipView",YTGKindChip);
        InstallHook("YTChipCloudChipCell",YTGKindChip);
        InstallHook("YTGhostChipCell",YTGKindChip);
        InstallHook("YTFilterChipBarView",YTGKindChipBar);
        InstallHook("YTHeaderView",YTGKindHeader);
        InstallHook("YTSubheaderContainerView",YTGKindSubheader);
        [[NSNotificationCenter defaultCenter]addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification*n){ScanWindows();SetPersistentSystemTabBarHidden(gYTWatchControllerCount>0,NO);}];
        for(NSNumber*d in @[@0.15,@0.5,@1.0,@2.0,@4.0])dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(d.doubleValue*NSEC_PER_SEC)),dispatch_get_main_queue(),^{ScanWindows();});
    });
}

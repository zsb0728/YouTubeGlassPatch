#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

static const void *kYTGlassKey = &kYTGlassKey;
typedef NS_ENUM(NSInteger, YTGKind) { YTGKindPivot, YTGKindChip, YTGKindChipBar, YTGKindHeader };
typedef struct { Class cls; IMP original; YTGKind kind; } YTGHook;
static YTGHook gHooks[12]; static int gHookCount = 0;

static id NewNativeGlass(BOOL interactive) API_AVAILABLE(ios(26.0)) {
    Class cls = NSClassFromString(@"UIGlassEffect"); if (!cls) return nil;
    id effect = nil; SEL factory = sel_registerName("effectWithStyle:");
    if ([cls respondsToSelector:factory]) effect = ((id(*)(id,SEL,NSInteger))objc_msgSend)(cls,factory,1);
    if (!effect) {
        id obj = ((id(*)(id,SEL))objc_msgSend)(cls,@selector(alloc));
        SEL init = sel_registerName("initWithStyle:");
        if ([obj respondsToSelector:init]) effect = ((id(*)(id,SEL,NSInteger))objc_msgSend)(obj,init,1);
    }
    SEL setInteractive = sel_registerName("setInteractive:");
    if (effect && [effect respondsToSelector:setInteractive]) ((void(*)(id,SEL,BOOL))objc_msgSend)(effect,setInteractive,interactive);
    return effect;
}

static void ClearSurface(UIView *v) {
    if (!v) return; v.opaque = NO; v.backgroundColor = UIColor.clearColor; v.layer.backgroundColor = nil;
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
        ClearSurface(p); p.clipsToBounds=NO;
        CGRect hostRect=[host convertRect:host.bounds toView:p];
        for(UIView *s in p.subviews) {
            if(s==pathChild || [s isKindOfClass:UICollectionView.class] || [s isKindOfClass:UIScrollView.class]) continue;
            CGRect overlap=CGRectIntersection(hostRect,s.frame);
            NSString *n=NSStringFromClass(s.class);
            if(!CGRectIsNull(overlap) && !CGRectIsEmpty(overlap) && (s.bounds.size.height<=180.0 || [n containsString:@"Background"] || [n containsString:@"Backdrop"])) ClearSurface(s);
        }
    }
}

static void StylePivot(UIView *host) API_AVAILABLE(ios(26.0)) {
    ClearSurface(host); ClearStructuralBackdrops(host,5); ClearShortAncestors(host,220.0); ClearBottomBarHierarchy(host);
    UIVisualEffectView *ev = GlassForHost(host,YES); if (!ev) return;
    CGFloat safe = host.safeAreaInsets.bottom;
    if (safe < 1.0 && host.window) safe = host.window.safeAreaInsets.bottom;
    CGFloat buttonZone = MAX(52.0,host.bounds.size.height-safe);
    CGFloat h = MIN(72.0,MAX(64.0,buttonZone+10.0));
    CGFloat inset = 8.0, y = -8.0;
    ev.frame = CGRectMake(inset,y,MAX(0.0,host.bounds.size.width-inset*2),h);
    ev.layer.cornerRadius = h/2.0; ev.layer.masksToBounds=YES;
    ev.layer.borderWidth=0.75; ev.layer.borderColor=[UIColor colorWithWhite:1 alpha:0.20].CGColor;
    host.clipsToBounds = NO; [host sendSubviewToBack:ev];
}

static void TintGlass(UIVisualEffectView *ev, BOOL selected) API_AVAILABLE(ios(26.0)) {
    id effect = ev.effect; SEL setTint = sel_registerName("setTintColor:");
    if ([effect respondsToSelector:setTint]) {
        UIColor *c = selected ? [UIColor colorWithWhite:1 alpha:0.20] : [UIColor colorWithWhite:1 alpha:0.04];
        ((void(*)(id,SEL,id))objc_msgSend)(effect,setTint,c);
    }
}

static void StyleChip(UIView *host) API_AVAILABLE(ios(26.0)) {
    if (host.bounds.size.width<28 || host.bounds.size.width>260 || host.bounds.size.height<24 || host.bounds.size.height>64) return;
    ClearSurface(host); ClearStructuralBackdrops(host,2);
    UIVisualEffectView *ev = GlassForHost(host,YES); if (!ev) return;
    ev.frame=host.bounds; ev.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    ev.layer.cornerRadius=MIN(host.bounds.size.height/2.0,16.0);
    TintGlass(ev,[host isKindOfClass:UIControl.class] ? ((UIControl*)host).selected : NO);
    [host sendSubviewToBack:ev];
}

static void StyleChipBar(UIView *host) API_AVAILABLE(ios(26.0)) {
    ClearSurface(host); ClearShortAncestors(host,240.0);
    for(UIView *p=host.superview; p && ![p isKindOfClass:UIWindow.class]; p=p.superview) {
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
        switch(kind) { case YTGKindPivot: StylePivot(v); break; case YTGKindChip: StyleChip(v); break; case YTGKindChipBar: StyleChipBar(v); break; case YTGKindHeader: StyleHeader(v); break; }
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
        InstallHook("YTPivotBarView",YTGKindPivot);
        InstallHook("YTChipCloudChipView",YTGKindChip);
        InstallHook("YTChipCloudChipCell",YTGKindChip);
        InstallHook("YTGhostChipCell",YTGKindChip);
        InstallHook("YTFilterChipBarView",YTGKindChipBar);
        InstallHook("YTHeaderView",YTGKindHeader);
        [[NSNotificationCenter defaultCenter]addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification*n){ScanWindows();}];
        for(int i=1;i<=24;i++)dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(i*.25*NSEC_PER_SEC)),dispatch_get_main_queue(),^{ScanWindows();});
    });
}

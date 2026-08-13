#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

static const void *kGlassKey = &kGlassKey;
static IMP gLayoutIMP;

static BOOL ReturnYES(id self, SEL _cmd) { return YES; }
static BOOL ReturnNO(id self, SEL _cmd) { return NO; }

static BOOL IsBoolGetter(Method m) {
    if (!m || method_getNumberOfArguments(m) != 2) return NO;
    char *t = method_copyReturnType(m);
    BOOL ok = t && (t[0] == 'B' || t[0] == 'c' || t[0] == 'C');
    if (t) free(t);
    return ok;
}

static BOOL DesiredFlag(const char *name, BOOL *value) {
    static const char *yesNames[] = {
        "isFrostedPivotBarPermitted",
        "isLiquidGlassAvailable",
        "computeIsLiquidGlassAvailable",
        "useLiquidGlassStyling",
        "mainAppCoreClientEnableModernIaFrostedBottomBar",
        "mainAppCoreClientEnableModernIaFrostedBottomBarStartupScheduler",
        "mainAppCoreClientEnableModernIaFrostedPivotBar",
        "mainAppCoreClientEnableModernIaFrostedPivotBarClipped",
        "mainAppCoreClientEnableModernIaFrostedPivotBarInvalidateOnMarginChange",
        "mainAppCoreClientEnableModernIaFrostedPivotBarUpdatedBackdrop",
        "mainAppCoreClientEnableModernIaFrostedTopBar",
        "mainAppCoreClientIosEnableModernIaFrostedBottomBarFixForSearch",
        "mainAppCoreClientIos27EnableLiquidGlass"
    };
    if (!strcmp(name, "optOutOfFrostedPivotBar")) { *value = NO; return YES; }
    for (NSUInteger i = 0; i < sizeof(yesNames)/sizeof(yesNames[0]); i++)
        if (!strcmp(name, yesNames[i])) { *value = YES; return YES; }
    return NO;
}

static void HookDeclaredFlags(Class cls) {
    unsigned count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    for (unsigned i = 0; i < count; i++) {
        Method m = methods[i]; BOOL value = NO;
        if (DesiredFlag(sel_getName(method_getName(m)), &value) && IsBoolGetter(m))
            method_setImplementation(m, value ? (IMP)ReturnYES : (IMP)ReturnNO);
    }
    free(methods);
}

static void ForceOfficialGlassFlags(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        int count = objc_getClassList(NULL, 0);
        if (count <= 0) return;
        Class *classes = (__unsafe_unretained Class *)calloc((size_t)count, sizeof(Class));
        count = objc_getClassList(classes, count);
        for (int i = 0; i < count; i++) {
            HookDeclaredFlags(classes[i]);
            HookDeclaredFlags(object_getClass(classes[i]));
        }
        free(classes);
    });
}

static id NewGlass(BOOL interactive) {
    Class cls = NSClassFromString(@"UIGlassEffect");
    if (!cls) return nil;
    id effect = nil;
    SEL factory = sel_registerName("effectWithStyle:");
    if ([cls respondsToSelector:factory])
        effect = ((id(*)(id,SEL,NSInteger))objc_msgSend)(cls, factory, 0);
    if (!effect) {
        id obj = ((id(*)(id,SEL))objc_msgSend)(cls, @selector(alloc));
        SEL init = sel_registerName("initWithStyle:");
        if ([obj respondsToSelector:init])
            effect = ((id(*)(id,SEL,NSInteger))objc_msgSend)(obj, init, 0);
    }
    SEL setInteractive = sel_registerName("setInteractive:");
    if (effect && [effect respondsToSelector:setInteractive])
        ((void(*)(id,SEL,BOOL))objc_msgSend)(effect, setInteractive, interactive);
    return effect;
}

static void ClearSurface(UIView *v) {
    v.opaque = NO;
    v.backgroundColor = UIColor.clearColor;
    v.layer.backgroundColor = nil;
}

static UIVisualEffectView *EnsureGlass(UIView *host, BOOL interactive) {
    UIVisualEffectView *ev = objc_getAssociatedObject(host, kGlassKey);
    id effect = NewGlass(interactive);
    if (!effect) return nil;
    if (!ev) {
        ev = [[UIVisualEffectView alloc] initWithEffect:effect];
        ev.userInteractionEnabled = NO;
        ev.clipsToBounds = YES;
        [host insertSubview:ev atIndex:0];
        objc_setAssociatedObject(host, kGlassKey, ev, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else {
        ev.effect = effect;
    }
    ev.layer.cornerCurve = kCACornerCurveContinuous;
    return ev;
}

static BOOL IsPivot(NSString *n) {
    return [n isEqualToString:@"YTPivotBarView"] ||
           [n isEqualToString:@"YTPivotBarViewControllerView"] ||
           [n containsString:@"ModernIaPivotBar"];
}

static BOOL IsChip(UIView *v, NSString *n) {
    if (v.bounds.size.width < 28 || v.bounds.size.width > 240 ||
        v.bounds.size.height < 24 || v.bounds.size.height > 64) return NO;
    return [n isEqualToString:@"YTChipCloudChipCell"] ||
           [n isEqualToString:@"YTGhostChipCell"] ||
           [n containsString:@"FilterChipCell"] ||
           [n containsString:@"ChipCellView"];
}

static void ApplyGlass(UIView *host) {
    if (@available(iOS 26.0, *)) {
        NSString *name = NSStringFromClass(host.class);
        if (IsPivot(name)) {
            ClearSurface(host);
            UIVisualEffectView *ev = EnsureGlass(host, YES);
            if (!ev) return;
            CGFloat safe = host.safeAreaInsets.bottom;
            CGFloat h = MAX(52.0, host.bounds.size.height - safe - 4.0);
            h = MIN(h, host.bounds.size.height - 2.0);
            ev.frame = CGRectMake(8.0, 2.0, MAX(0, host.bounds.size.width - 16.0), MAX(0, h));
            ev.layer.cornerRadius = h / 2.0;
            host.clipsToBounds = NO;
        } else if (IsChip(host, name)) {
            ClearSurface(host);
            for (UIView *s in host.subviews) {
                if ([NSStringFromClass(s.class) isEqualToString:@"UIView"]) ClearSurface(s);
            }
            UIVisualEffectView *ev = EnsureGlass(host, YES);
            if (!ev) return;
            ev.frame = host.bounds;
            ev.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            ev.layer.cornerRadius = MIN(host.bounds.size.height / 2.0, 14.0);
        }
    }
}

static void GlassLayout(UIView *self, SEL cmd) {
    ((void(*)(id,SEL))gLayoutIMP)(self, cmd);
    ApplyGlass(self);
}

static void Scan(UIView *v) {
    ApplyGlass(v);
    for (UIView *s in v.subviews) Scan(s);
}

static void ScanWindows(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes)
        if ([scene isKindOfClass:UIWindowScene.class])
            for (UIWindow *w in ((UIWindowScene *)scene).windows) Scan(w);
}

__attribute__((constructor)) static void YouTubeGlassStart(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        ForceOfficialGlassFlags();
        Method m = class_getInstanceMethod(UIView.class, @selector(layoutSubviews));
        gLayoutIMP = method_getImplementation(m);
        method_setImplementation(m, (IMP)GlassLayout);
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *n) {
            ForceOfficialGlassFlags(); ScanWindows();
        }];
        for (int i = 1; i <= 24; i++)
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(i * 0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ ForceOfficialGlassFlags(); ScanWindows(); });
    });
}

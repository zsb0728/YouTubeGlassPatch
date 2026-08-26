#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

// 原地启用 YouTube 21.33.6 自带的 iOS 26 Frosted Pivot Bar；若宿主官方路径未产出，
// 仅在原 YTPivotBarView 内放 UIGlassEffect 兜底。不替换底栏、不覆盖窗口、不修改播放器/Feed。
static const void *kYTGBackgroundKey=&kYTGBackgroundKey;
static const void *kYTGSelectionKey=&kYTGSelectionKey;
static IMP gOriginalLayout;
static BOOL gInstalled;

static BOOL YTGYes(id self,SEL cmd){return YES;}
static BOOL YTGNo(id self,SEL cmd){return NO;}

static BOOL YTGIsBoolGetter(Method m){
    if(!m||method_getNumberOfArguments(m)!=2)return NO;
    char *t=method_copyReturnType(m);BOOL ok=t&&(t[0]=='B'||t[0]=='c'||t[0]=='C');if(t)free(t);return ok;
}

static BOOL YTGDesiredFlag(const char *name,BOOL *value){
    static const char *yes[]={
        "isFrostedPivotBarPermitted","isLiquidGlassAvailable","computeIsLiquidGlassAvailable",
        "useLiquidGlassStyling","mainAppCoreClientEnableModernIaFrostedBottomBar",
        "mainAppCoreClientEnableModernIaFrostedBottomBarStartupScheduler",
        "mainAppCoreClientEnableModernIaFrostedPivotBar",
        "mainAppCoreClientEnableModernIaFrostedPivotBarClipped",
        "mainAppCoreClientEnableModernIaFrostedPivotBarInvalidateOnMarginChange",
        "mainAppCoreClientEnableModernIaFrostedPivotBarUpdatedBackdrop",
        "mainAppCoreClientIosEnableModernIaFrostedBottomBarFixForSearch",
        "mainAppCoreClientScheduleModernIaFrostedPivotBarInitializationAfterStartup"
    };
    if(!strcmp(name,"optOutOfFrostedPivotBar")){*value=NO;return YES;}
    for(NSUInteger i=0;i<sizeof(yes)/sizeof(yes[0]);i++)if(!strcmp(name,yes[i])){*value=YES;return YES;}
    return NO;
}

static void YTGHookFlagsOnClass(Class cls){
    unsigned count=0;Method *list=class_copyMethodList(cls,&count);
    for(unsigned i=0;i<count;i++){BOOL value=NO;Method m=list[i];if(YTGDesiredFlag(sel_getName(method_getName(m)),&value)&&YTGIsBoolGetter(m))method_setImplementation(m,value?(IMP)YTGYes:(IMP)YTGNo);}
    free(list);
}

static void YTGEnableOfficialFlags(void){
    int count=objc_getClassList(NULL,0);if(count<=0)return;
    Class *classes=(__unsafe_unretained Class*)calloc((size_t)count,sizeof(Class));count=objc_getClassList(classes,count);
    for(int i=0;i<count;i++){YTGHookFlagsOnClass(classes[i]);YTGHookFlagsOnClass(object_getClass(classes[i]));}
    free(classes);
}

static void YTGClearSurface(UIView *v){if(!v)return;v.opaque=NO;v.backgroundColor=UIColor.clearColor;v.layer.backgroundColor=nil;}

static BOOL YTGIsPivotItem(UIView *v){return [NSStringFromClass(v.class)isEqualToString:@"YTPivotBarItemView"];}

static void YTGCollectItems(UIView *v,NSMutableArray<UIView*> *out){
    for(UIView *s in v.subviews){if(YTGIsPivotItem(s)){if(!s.hidden&&s.alpha>.01&&s.bounds.size.width>20)[out addObject:s];}else if(![s isKindOfClass:UIVisualEffectView.class])YTGCollectItems(s,out);}
}

static BOOL YTGSelected(UIView *item){SEL sel=sel_registerName("selected");return [item respondsToSelector:sel]&&((BOOL(*)(id,SEL))objc_msgSend)(item,sel);}

static void YTGClearInternalBackdrops(UIView *root,UIView *background,UIView *selection,NSInteger depth){
    if(depth<0)return;
    for(UIView *s in root.subviews){
        if(s==background||s==selection||YTGIsPivotItem(s)||[s isKindOfClass:UIControl.class]||[s isKindOfClass:UILabel.class]||[s isKindOfClass:UIImageView.class])continue;
        NSString *name=NSStringFromClass(s.class);if([name containsString:@"Badge"]||[name containsString:@"Avatar"]||[name containsString:@"Indicator"])continue;
        YTGClearSurface(s);YTGClearInternalBackdrops(s,background,selection,depth-1);
    }
}

static void YTGSuppressFullWidthGlass(UIView *root,UIView *background,UIView *selection,UIView *host){
    for(UIView *s in root.subviews){
        if(s==background||s==selection)continue;
        if([s isKindOfClass:UIVisualEffectView.class]){
            UIVisualEffectView *effectView=(UIVisualEffectView*)s;
            CGRect r=[s convertRect:s.bounds toView:host];
            BOOL fullWidth=r.size.width>host.bounds.size.width*.78&&r.size.height>28&&r.size.height<180;
            if(fullWidth&&[effectView.effect isKindOfClass:UIGlassEffect.class]){
                // YouTube 的实验开关会生成全宽玻璃底板；保留其 overlay 布局，只关掉底板视觉。
                effectView.effect=nil;effectView.hidden=YES;effectView.userInteractionEnabled=NO;
            }
        }
        if(!YTGIsPivotItem(s))YTGSuppressFullWidthGlass(s,background,selection,host);
    }
}

static UIVisualEffectView *YTGGlassView(BOOL interactive) API_AVAILABLE(ios(26.0)){
    UIGlassEffect *effect=[UIGlassEffect effectWithStyle:UIGlassEffectStyleRegular];effect.interactive=interactive;
    UIVisualEffectView *view=[[UIVisualEffectView alloc]initWithEffect:effect];view.userInteractionEnabled=NO;view.opaque=NO;view.backgroundColor=UIColor.clearColor;view.clipsToBounds=YES;view.layer.cornerCurve=kCACornerCurveContinuous;return view;
}

static void YTGRemoveFallback(UIView *host){
    UIVisualEffectView *a=objc_getAssociatedObject(host,kYTGBackgroundKey),*b=objc_getAssociatedObject(host,kYTGSelectionKey);
    [a removeFromSuperview];[b removeFromSuperview];objc_setAssociatedObject(host,kYTGBackgroundKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);objc_setAssociatedObject(host,kYTGSelectionKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void YTGStylePivot(UIView *host) API_AVAILABLE(ios(26.0)){
    if(!host.window||host.bounds.size.width<100||host.bounds.size.height<30)return;
    UIVisualEffectView *background=objc_getAssociatedObject(host,kYTGBackgroundKey),*selection=objc_getAssociatedObject(host,kYTGSelectionKey);
    // 保留 YouTube 官方 overlay/Feed 布局，但屏蔽其全宽毛玻璃底板，改由下面的悬浮胶囊呈现。
    YTGSuppressFullWidthGlass(host,background,selection,host);

    NSMutableArray<UIView*> *items=[NSMutableArray array];YTGCollectItems(host,items);if(items.count<2)return;
    [items sortUsingComparator:^NSComparisonResult(UIView*a,UIView*b){CGRect ar=[a convertRect:a.bounds toView:host],br=[b convertRect:b.bounds toView:host];return CGRectGetMinX(ar)<CGRectGetMinX(br)?NSOrderedAscending:NSOrderedDescending;}];
    if(!background){background=YTGGlassView(NO);selection=YTGGlassView(YES);[host insertSubview:background atIndex:0];[host insertSubview:selection aboveSubview:background];objc_setAssociatedObject(host,kYTGBackgroundKey,background,OBJC_ASSOCIATION_RETAIN_NONATOMIC);objc_setAssociatedObject(host,kYTGSelectionKey,selection,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}

    // 只清理原底栏内部的旧背景；不碰 superview、Feed、scroll view、窗口和播放器。
    YTGClearSurface(host);YTGClearInternalBackdrops(host,background,selection,3);host.clipsToBounds=NO;
    CGFloat safe=host.safeAreaInsets.bottom;if(safe<1&&host.window)safe=host.window.safeAreaInsets.bottom;
    CGFloat h=MIN(58.0,MAX(48.0,host.bounds.size.height-safe-6.0));
    CGFloat side=16.0;
    CGRect capsule=CGRectMake(side,MAX(2.0,(host.bounds.size.height-safe-h)/2.0),MAX(0.0,host.bounds.size.width-side*2.0),h);
    background.frame=capsule;background.layer.cornerRadius=h/2.0;

    UIView *selected=items.firstObject;for(UIView *item in items)if(YTGSelected(item)){selected=item;break;}
    CGRect itemRect=[selected convertRect:selected.bounds toView:host];CGFloat lensH=MAX(36.0,h-6.0);
    CGFloat lensX=MAX(CGRectGetMinX(capsule)+3.0,CGRectGetMinX(itemRect)+4.0);CGFloat lensMax=MIN(CGRectGetMaxX(capsule)-3.0,CGRectGetMaxX(itemRect)-4.0);
    CGRect lens=CGRectMake(lensX,CGRectGetMidY(capsule)-lensH/2.0,MAX(28.0,lensMax-lensX),lensH);
    selection.frame=lens;selection.layer.cornerRadius=lensH/2.0;selection.hidden=NO;
    [host sendSubviewToBack:background];[host insertSubview:selection aboveSubview:background];
}

static void YTGLayout(UIView *self,SEL cmd){if(gOriginalLayout)((void(*)(id,SEL))gOriginalLayout)(self,cmd);if(@available(iOS 26.0,*))YTGStylePivot(self);}

static void YTGInstall(void){
    if(gInstalled)return;Class cls=objc_getClass("YTPivotBarView");Method m=cls?class_getInstanceMethod(cls,@selector(layoutSubviews)):NULL;if(!m)return;
    gInstalled=YES;gOriginalLayout=method_getImplementation(m);const char *types=method_getTypeEncoding(m);
    if(!class_addMethod(cls,@selector(layoutSubviews),(IMP)YTGLayout,types))method_setImplementation(class_getInstanceMethod(cls,@selector(layoutSubviews)),(IMP)YTGLayout);
}

__attribute__((constructor)) static void YTGStart(void){
    YTGEnableOfficialFlags();
    dispatch_async(dispatch_get_main_queue(),^{
        YTGInstall();
        [[NSNotificationCenter defaultCenter]addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification*n){YTGEnableOfficialFlags();YTGInstall();}];
        for(NSNumber *d in @[@0.05,@0.2,@0.5,@1.0,@2.0])dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(d.doubleValue*NSEC_PER_SEC)),dispatch_get_main_queue(),^{YTGEnableOfficialFlags();YTGInstall();});
    });
}

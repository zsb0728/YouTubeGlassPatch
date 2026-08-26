#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>

// YouTube 21.33.6 — native sibling glass architecture.
// Verified baseline: YTAsyncCollectionView already reaches screen bottom; YTPivotBarView is the white cover.
// Put official UIGlassEffect in YTAppView between Feed and the original pivot, so it samples real content.
// Never enable YouTube Frosted experiments; never replace buttons/controllers or touch player/scroll views.
static const void *kYTGBaseKey=&kYTGBaseKey,*kYTGLensKey=&kYTGLensKey;
static IMP gPivotLayoutIMP,gItemSelectedIMP;static BOOL gPivotHooked,gItemHooked;

static BOOL YTGIsItem(UIView*v){return[NSStringFromClass(v.class)isEqualToString:@"YTPivotBarItemView"];}
static void YTGCollectItems(UIView*v,NSMutableArray*out){for(UIView*s in v.subviews){if(YTGIsItem(s)){if(!s.hidden&&s.alpha>.01&&s.bounds.size.width>20)[out addObject:s];}else YTGCollectItems(s,out);}}
static BOOL YTGSelected(UIView*v){SEL s=sel_registerName("selected");return[v respondsToSelector:s]&&((BOOL(*)(id,SEL))objc_msgSend)(v,s);}
static void YTGClear(UIView*v){if(!v)return;v.opaque=NO;v.backgroundColor=UIColor.clearColor;v.layer.backgroundColor=nil;}

static UIVisualEffectView*YTGMakeGlass(BOOL interactive) API_AVAILABLE(ios(26.0)){
    UIGlassEffect*effect=[UIGlassEffect effectWithStyle:UIGlassEffectStyleClear];
    effect.interactive=interactive;
    UIVisualEffectView*v=[[UIVisualEffectView alloc]initWithEffect:effect];
    v.userInteractionEnabled=NO;v.opaque=NO;v.backgroundColor=UIColor.clearColor;v.layer.backgroundColor=nil;
    v.cornerConfiguration=[UICornerConfiguration capsuleConfiguration];
    return v;
}

static UIView*YTGItemContainer(UIView*host,NSArray*items){
    UIView*c=items.count?((UIView*)items.firstObject).superview:nil;
    return c&&c.superview==host?c:nil;
}

static void YTGRestoreOriginal(UIView*host){
    UIVisualEffectView*base=objc_getAssociatedObject(host,kYTGBaseKey),*lens=objc_getAssociatedObject(host,kYTGLensKey);
    base.hidden=YES;lens.hidden=YES;
}

static void YTGStyle(UIView*host) API_AVAILABLE(ios(26.0)){
    UIView*app=host.superview;
    if(!host.window||![NSStringFromClass(app.class)isEqualToString:@"YTAppView"]||host.bounds.size.width<300||host.bounds.size.height<60){YTGRestoreOriginal(host);return;}

    NSMutableArray*items=[NSMutableArray array];YTGCollectItems(host,items);
    if(items.count<2||items.count>7){YTGRestoreOriginal(host);return;}
    [items sortUsingComparator:^NSComparisonResult(UIView*a,UIView*b){CGRect x=[a convertRect:a.bounds toView:host],y=[b convertRect:b.bounds toView:host];return CGRectGetMinX(x)<CGRectGetMinX(y)?NSOrderedAscending:NSOrderedDescending;}];
    UIView*container=YTGItemContainer(host,items);if(!container){YTGRestoreOriginal(host);return;}

    UIVisualEffectView*base=objc_getAssociatedObject(host,kYTGBaseKey),*lens=objc_getAssociatedObject(host,kYTGLensKey);
    if(!base){
        base=YTGMakeGlass(NO);lens=YTGMakeGlass(YES);
        objc_setAssociatedObject(host,kYTGBaseKey,base,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(host,kYTGLensKey,lens,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if(base.superview!=app)[app insertSubview:base belowSubview:host];
    if(lens.superview!=app)[app insertSubview:lens aboveSubview:base];
    [app insertSubview:base belowSubview:host];[app insertSubview:lens belowSubview:host];

    // Only the verified white surfaces inside the original pivot. Buttons and interaction stay untouched.
    YTGClear(host);YTGClear(container);host.clipsToBounds=NO;
    for(UIView*s in host.subviews)if(s!=container&&s.bounds.size.height<=2.0)YTGClear(s);

    CGFloat side=22.0,height=62.0;
    CGRect capsuleInHost=CGRectMake(side,0.0,host.bounds.size.width-side*2.0,height);
    CGRect capsule=[host convertRect:capsuleInHost toView:app];
    base.frame=capsule;base.hidden=NO;YTGClear(base);

    UIView*selected=items.firstObject;for(UIView*i in items)if(YTGSelected(i)){selected=i;break;}
    CGRect item=[selected convertRect:selected.bounds toView:host];CGFloat lensHeight=56.0;
    CGFloat x=MAX(CGRectGetMinX(capsuleInHost)+3.0,CGRectGetMinX(item)+5.0);
    CGFloat maxX=MIN(CGRectGetMaxX(capsuleInHost)-3.0,CGRectGetMaxX(item)-5.0);
    CGRect lensHost=CGRectMake(x,3.0,MAX(30.0,maxX-x),lensHeight);
    lens.frame=[host convertRect:lensHost toView:app];lens.hidden=NO;YTGClear(lens);
    base.userInteractionEnabled=NO;lens.userInteractionEnabled=NO;
}

static void YTGPivotLayout(UIView*self,SEL cmd){
    if(gPivotLayoutIMP)((void(*)(id,SEL))gPivotLayoutIMP)(self,cmd);
    if(@available(iOS 26.0,*))YTGStyle(self);
}
static UIView*YTGPivotForItem(UIView*v){for(UIView*p=v.superview;p;p=p.superview)if([NSStringFromClass(p.class)isEqualToString:@"YTPivotBarView"])return p;return nil;}
static void YTGItemSelected(id self,SEL cmd,BOOL selected){
    if(gItemSelectedIMP)((void(*)(id,SEL,BOOL))gItemSelectedIMP)(self,cmd,selected);
    UIView*p=YTGPivotForItem(self);if(p)dispatch_async(dispatch_get_main_queue(),^{[p setNeedsLayout];});
}

static void YTGInstall(void){
    Class pivot=objc_getClass("YTPivotBarView");Method pm=pivot?class_getInstanceMethod(pivot,@selector(layoutSubviews)):NULL;
    if(pm&&!gPivotHooked){gPivotHooked=YES;gPivotLayoutIMP=method_getImplementation(pm);const char*t=method_getTypeEncoding(pm);if(!class_addMethod(pivot,@selector(layoutSubviews),(IMP)YTGPivotLayout,t))method_setImplementation(class_getInstanceMethod(pivot,@selector(layoutSubviews)),(IMP)YTGPivotLayout);}
    Class item=objc_getClass("YTPivotBarItemView");SEL ss=sel_registerName("setSelected:");Method sm=item?class_getInstanceMethod(item,ss):NULL;
    if(sm&&!gItemHooked){gItemHooked=YES;gItemSelectedIMP=method_getImplementation(sm);const char*t=method_getTypeEncoding(sm);if(!class_addMethod(item,ss,(IMP)YTGItemSelected,t))method_setImplementation(class_getInstanceMethod(item,ss),(IMP)YTGItemSelected);}
}

__attribute__((constructor))static void YTGStart(void){
    // Targeted hook installation only: no objc_getClassList, no window scans, no timers, no diagnostics.
    YTGInstall();dispatch_async(dispatch_get_main_queue(),^{YTGInstall();});
}

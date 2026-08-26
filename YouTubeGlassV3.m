#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

// YouTube 原生底栏液态玻璃：不替换 YTPivotBarView，不创建控制器/Portal，
// 只把 iOS 26 官方 UIGlassEffect 放到原按钮下面。
static const void *kYTGBackgroundKey=&kYTGBackgroundKey;
static const void *kYTGSelectionKey=&kYTGSelectionKey;
static IMP gOriginalLayout;
static BOOL gInstalled;

static void YTGClearSurface(UIView *v){
    if(!v)return;
    v.opaque=NO;
    v.backgroundColor=UIColor.clearColor;
    v.layer.backgroundColor=nil;
}

static void YTGCollectItems(UIView *v,NSMutableArray<UIView*> *out){
    for(UIView *s in v.subviews){
        if([NSStringFromClass(s.class)isEqualToString:@"YTPivotBarItemView"]){
            if(!s.hidden&&s.alpha>.01&&s.bounds.size.width>20)[out addObject:s];
        }else if(![s isKindOfClass:UIVisualEffectView.class])YTGCollectItems(s,out);
    }
}

static BOOL YTGSelected(UIView *item){
    SEL sel=sel_registerName("selected");
    return [item respondsToSelector:sel]&&((BOOL(*)(id,SEL))objc_msgSend)(item,sel);
}

static UIVisualEffectView *YTGGlassView(BOOL interactive) API_AVAILABLE(ios(26.0)){
    UIGlassEffect *effect=[UIGlassEffect effectWithStyle:UIGlassEffectStyleRegular];
    effect.interactive=interactive;
    UIVisualEffectView *view=[[UIVisualEffectView alloc]initWithEffect:effect];
    view.userInteractionEnabled=NO;
    view.opaque=NO;
    view.backgroundColor=UIColor.clearColor;
    view.clipsToBounds=YES;
    return view;
}

static void YTGStylePivot(UIView *host) API_AVAILABLE(ios(26.0)){
    if(!host.window||host.bounds.size.width<100||host.bounds.size.height<30)return;

    NSMutableArray<UIView*> *items=[NSMutableArray array];
    YTGCollectItems(host,items);
    if(items.count<2)return;
    [items sortUsingComparator:^NSComparisonResult(UIView*a,UIView*b){
        CGRect ar=[a convertRect:a.bounds toView:host],br=[b convertRect:b.bounds toView:host];
        return CGRectGetMinX(ar)<CGRectGetMinX(br)?NSOrderedAscending:NSOrderedDescending;
    }];

    UIVisualEffectView *background=objc_getAssociatedObject(host,kYTGBackgroundKey);
    UIVisualEffectView *selection=objc_getAssociatedObject(host,kYTGSelectionKey);
    if(!background){
        background=YTGGlassView(NO);
        selection=YTGGlassView(YES);
        background.alpha=0; selection.alpha=0;
        [host insertSubview:background atIndex:0];
        [host insertSubview:selection aboveSubview:background];
        objc_setAssociatedObject(host,kYTGBackgroundKey,background,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(host,kYTGSelectionKey,selection,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    // 只清 host 自身旧底色；绝不递归清祖先、Feed 或播放器。
    YTGClearSurface(host);

    CGFloat side=12.0,top=4.0,bottom=MAX(4.0,host.safeAreaInsets.bottom+2.0);
    CGRect capsule=UIEdgeInsetsInsetRect(host.bounds,UIEdgeInsetsMake(top,side,bottom,side));
    if(capsule.size.height<40){capsule=CGRectInset(host.bounds,side,2);}
    background.frame=capsule;
    background.layer.cornerRadius=capsule.size.height/2.0;

    UIView *selected=nil;
    for(UIView *item in items)if(YTGSelected(item)){selected=item;break;}
    if(!selected)selected=items.firstObject;
    CGRect itemRect=[selected convertRect:selected.bounds toView:host];
    CGFloat insetY=MAX(2.0,(itemRect.size.height-capsule.size.height)/2.0+2.0);
    CGRect lens=CGRectInset(itemRect,4.0,insetY);
    lens=CGRectIntersection(lens,capsule);
    if(!CGRectIsNull(lens)&&lens.size.width>20&&lens.size.height>20){
        selection.hidden=NO;
        selection.frame=lens;
        selection.layer.cornerRadius=lens.size.height/2.0;
    }else selection.hidden=YES;

    // 玻璃永远在原按钮下面，原按钮及其手势、角标、头像完全不动。
    [host sendSubviewToBack:background];
    [host insertSubview:selection aboveSubview:background];
    [UIView performWithoutAnimation:^{background.alpha=1;selection.alpha=1;}];
}

static void YTGLayout(UIView *self,SEL cmd){
    if(gOriginalLayout)((void(*)(id,SEL))gOriginalLayout)(self,cmd);
    if(@available(iOS 26.0,*))YTGStylePivot(self);
}

static void YTGInstall(void){
    if(gInstalled)return;
    Class cls=objc_getClass("YTPivotBarView");
    Method m=class_getInstanceMethod(cls,@selector(layoutSubviews));
    if(!cls||!m)return;
    gInstalled=YES;
    gOriginalLayout=method_getImplementation(m);
    const char *types=method_getTypeEncoding(m);
    if(!class_addMethod(cls,@selector(layoutSubviews),(IMP)YTGLayout,types))
        method_setImplementation(class_getInstanceMethod(cls,@selector(layoutSubviews)),(IMP)YTGLayout);
}

__attribute__((constructor)) static void YTGStart(void){
    dispatch_async(dispatch_get_main_queue(),^{YTGInstall();});
}

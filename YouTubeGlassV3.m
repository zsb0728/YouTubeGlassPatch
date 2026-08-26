#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

// Stable in-place architecture for YouTube 21.33.6.
// Preserve original pivot/buttons/gestures. Add official Clear Glass behind its button container.
static const void *kBase=&kBase,*kLens=&kLens;
static IMP gLayoutIMP,gSelectedIMP;static BOOL gLayoutHooked,gSelectedHooked;

static BOOL IsItem(UIView*v){return[NSStringFromClass(v.class)isEqualToString:@"YTPivotBarItemView"];}
static void Collect(UIView*v,NSMutableArray*out){for(UIView*s in v.subviews){if(IsItem(s)){if(!s.hidden&&s.alpha>.01&&s.bounds.size.width>20)[out addObject:s];}else if(s!=objc_getAssociatedObject(v,kBase)&&s!=objc_getAssociatedObject(v,kLens))Collect(s,out);}}
static BOOL Selected(UIView*v){SEL s=sel_registerName("selected");return[v respondsToSelector:s]&&((BOOL(*)(id,SEL))objc_msgSend)(v,s);}
static void Clear(UIView*v){if(!v)return;v.opaque=NO;v.backgroundColor=UIColor.clearColor;v.layer.backgroundColor=nil;}
static UIVisualEffectView*Glass(BOOL interactive) API_AVAILABLE(ios(26.0)){UIGlassEffect*e=[UIGlassEffect effectWithStyle:UIGlassEffectStyleClear];e.interactive=interactive;UIVisualEffectView*v=[[UIVisualEffectView alloc]initWithEffect:e];v.userInteractionEnabled=NO;v.opaque=NO;v.backgroundColor=UIColor.clearColor;v.layer.backgroundColor=nil;v.cornerConfiguration=[UICornerConfiguration capsuleConfiguration];return v;}

static void Style(UIView*host) API_AVAILABLE(ios(26.0)){
 if(!host.window||host.bounds.size.width<300||host.bounds.size.height<60)return;
 NSMutableArray*items=[NSMutableArray array];Collect(host,items);if(items.count<2||items.count>7)return;
 [items sortUsingComparator:^NSComparisonResult(UIView*a,UIView*b){CGRect x=[a convertRect:a.bounds toView:host],y=[b convertRect:b.bounds toView:host];return CGRectGetMinX(x)<CGRectGetMinX(y)?NSOrderedAscending:NSOrderedDescending;}];
 UIView*container=((UIView*)items.firstObject).superview;if(!container||container.superview!=host)return;
 UIVisualEffectView*base=objc_getAssociatedObject(host,kBase),*lens=objc_getAssociatedObject(host,kLens);
 if(!base){base=Glass(NO);lens=Glass(YES);[host insertSubview:base atIndex:0];[host insertSubview:lens aboveSubview:base];objc_setAssociatedObject(host,kBase,base,OBJC_ASSOCIATION_RETAIN_NONATOMIC);objc_setAssociatedObject(host,kLens,lens,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
 Clear(host);Clear(container);for(UIView*s in host.subviews)if(s!=base&&s!=lens&&s!=container&&s.bounds.size.height<=2)Clear(s);host.clipsToBounds=NO;
 CGRect capsule=CGRectMake(22,0,host.bounds.size.width-44,62);base.frame=capsule;base.hidden=NO;Clear(base);
 UIView*selected=items.firstObject;for(UIView*i in items)if(Selected(i)){selected=i;break;}CGRect ir=[selected convertRect:selected.bounds toView:host];CGFloat x=MAX(25,CGRectGetMinX(ir)+5),mx=MIN(host.bounds.size.width-25,CGRectGetMaxX(ir)-5);lens.frame=CGRectMake(x,3,MAX(30,mx-x),56);lens.hidden=NO;Clear(lens);
 [host insertSubview:base belowSubview:container];[host insertSubview:lens belowSubview:container];base.userInteractionEnabled=NO;lens.userInteractionEnabled=NO;
}
static void HookLayout(UIView*self,SEL cmd){if(gLayoutIMP)((void(*)(id,SEL))gLayoutIMP)(self,cmd);if(@available(iOS 26.0,*))Style(self);}
static UIView*PivotFor(UIView*v){for(UIView*p=v.superview;p;p=p.superview)if([NSStringFromClass(p.class)isEqualToString:@"YTPivotBarView"])return p;return nil;}
static void HookSelected(id self,SEL cmd,BOOL value){if(gSelectedIMP)((void(*)(id,SEL,BOOL))gSelectedIMP)(self,cmd,value);UIView*p=PivotFor(self);if(p)dispatch_async(dispatch_get_main_queue(),^{[p setNeedsLayout];});}
static void Install(void){
 Class p=objc_getClass("YTPivotBarView");Method lm=p?class_getInstanceMethod(p,@selector(layoutSubviews)):NULL;if(lm&&!gLayoutHooked){gLayoutIMP=method_getImplementation(lm);method_setImplementation(lm,(IMP)HookLayout);gLayoutHooked=YES;}
 Class i=objc_getClass("YTPivotBarItemView");SEL ss=sel_registerName("setSelected:");Method sm=i?class_getInstanceMethod(i,ss):NULL;if(sm&&!gSelectedHooked){gSelectedIMP=method_getImplementation(sm);method_setImplementation(sm,(IMP)HookSelected);gSelectedHooked=YES;}
}
__attribute__((constructor))static void Start(void){dispatch_async(dispatch_get_main_queue(),^{Install();for(NSNumber*d in @[@0.05,@0.2,@0.5,@1.0,@2.0,@4.0])dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(d.doubleValue*NSEC_PER_SEC)),dispatch_get_main_queue(),^{Install();});});}

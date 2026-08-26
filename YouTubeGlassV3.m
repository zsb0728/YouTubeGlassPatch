#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>

// Instance-owned native glass for YouTube 21.33.6.
// Adopt the actual YTPivotBarView instance under YTAppView, avoiding fragile class-wide swizzles.
static const void *kBase=&kBase,*kLens=&kLens,*kAdopted=&kAdopted;
static Class gPivotRuntimeSubclass;

static BOOL IsNamed(id obj,NSString*n){return obj&&[NSStringFromClass(object_getClass(obj))isEqualToString:n];}
static BOOL IsPivotItem(UIView*v){Class c=object_getClass(v);while(c){if([NSStringFromClass(c)isEqualToString:@"YTPivotBarItemView"])return YES;c=class_getSuperclass(c);}return NO;}
static void CollectItems(UIView*v,NSMutableArray*out){for(UIView*s in v.subviews){if(IsPivotItem(s)){if(!s.hidden&&s.alpha>.01&&s.bounds.size.width>20)[out addObject:s];}else CollectItems(s,out);}}
static BOOL ItemSelected(UIView*v){SEL s=sel_registerName("selected");return[v respondsToSelector:s]&&((BOOL(*)(id,SEL))objc_msgSend)(v,s);}
static void ClearSurface(UIView*v){if(!v)return;v.opaque=NO;v.backgroundColor=UIColor.clearColor;v.layer.backgroundColor=nil;}
static UIVisualEffectView*MakeGlass(BOOL interactive) API_AVAILABLE(ios(26.0)){UIGlassEffect*e=[UIGlassEffect effectWithStyle:UIGlassEffectStyleClear];e.interactive=interactive;UIVisualEffectView*v=[[UIVisualEffectView alloc]initWithEffect:e];v.userInteractionEnabled=NO;v.opaque=NO;v.backgroundColor=UIColor.clearColor;v.layer.backgroundColor=nil;v.cornerConfiguration=[UICornerConfiguration capsuleConfiguration];return v;}

static void ApplyGlass(UIView*host) API_AVAILABLE(ios(26.0)){
 UIView*app=host.superview;if(!app||![NSStringFromClass(object_getClass(app))isEqualToString:@"YTAppView"]||!host.window)return;
 NSMutableArray*items=[NSMutableArray array];CollectItems(host,items);if(items.count<2||items.count>7)return;
 [items sortUsingComparator:^NSComparisonResult(UIView*a,UIView*b){CGRect x=[a convertRect:a.bounds toView:host],y=[b convertRect:b.bounds toView:host];return CGRectGetMinX(x)<CGRectGetMinX(y)?NSOrderedAscending:NSOrderedDescending;}];
 UIView*buttonContainer=((UIView*)items.firstObject).superview;if(!buttonContainer||buttonContainer.superview!=host)return;
 UIVisualEffectView*base=objc_getAssociatedObject(host,kBase),*lens=objc_getAssociatedObject(host,kLens);
 if(!base){base=MakeGlass(NO);lens=MakeGlass(YES);objc_setAssociatedObject(host,kBase,base,OBJC_ASSOCIATION_RETAIN_NONATOMIC);objc_setAssociatedObject(host,kLens,lens,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
 if(base.superview!=app)[app insertSubview:base belowSubview:host];if(lens.superview!=app)[app insertSubview:lens belowSubview:host];
 [app insertSubview:base belowSubview:host];[app insertSubview:lens belowSubview:host];
 ClearSurface(host);ClearSurface(buttonContainer);for(UIView*s in host.subviews)if(s!=buttonContainer&&s.bounds.size.height<=2)ClearSurface(s);host.clipsToBounds=NO;
 CGRect local=CGRectMake(22,0,host.bounds.size.width-44,62);base.frame=[host convertRect:local toView:app];base.hidden=NO;ClearSurface(base);
 UIView*selected=items.firstObject;for(UIView*i in items)if(ItemSelected(i)){selected=i;break;}CGRect ir=[selected convertRect:selected.bounds toView:host];CGFloat x=MAX(25,CGRectGetMinX(ir)+5),mx=MIN(host.bounds.size.width-25,CGRectGetMaxX(ir)-5);CGRect lr=CGRectMake(x,3,MAX(30,mx-x),56);lens.frame=[host convertRect:lr toView:app];lens.hidden=NO;ClearSurface(lens);base.userInteractionEnabled=NO;lens.userInteractionEnabled=NO;
}

static void RuntimePivotLayout(UIView*self,SEL cmd){struct objc_super sup={self,class_getSuperclass(object_getClass(self))};((void(*)(struct objc_super*,SEL))objc_msgSendSuper)(&sup,cmd);if(@available(iOS 26.0,*))ApplyGlass(self);}
static Class ReportOriginalClass(id self,SEL cmd){return class_getSuperclass(object_getClass(self));}
static Class PivotSubclassFor(Class original){
 if(gPivotRuntimeSubclass)return gPivotRuntimeSubclass;
 const char*name="YTG_RuntimePivotBarView";Class existing=objc_getClass(name);if(existing){gPivotRuntimeSubclass=existing;return existing;}
 Class sub=objc_allocateClassPair(original,name,0);if(!sub)return Nil;
 Method lm=class_getInstanceMethod(original,@selector(layoutSubviews));class_addMethod(sub,@selector(layoutSubviews),(IMP)RuntimePivotLayout,method_getTypeEncoding(lm));class_addMethod(sub,@selector(class),(IMP)ReportOriginalClass,"#@:");objc_registerClassPair(sub);gPivotRuntimeSubclass=sub;return sub;
}
static BOOL AdoptPivot(UIView*pivot){if(objc_getAssociatedObject(pivot,kAdopted))return YES;Class original=object_getClass(pivot);Class sub=PivotSubclassFor(original);if(!sub)return NO;object_setClass(pivot,sub);objc_setAssociatedObject(pivot,kAdopted,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);[pivot setNeedsLayout];[pivot layoutIfNeeded];return YES;}

static BOOL FindAndAdopt(void){
 for(UIScene*scene in UIApplication.sharedApplication.connectedScenes)if([scene isKindOfClass:UIWindowScene.class])for(UIWindow*w in ((UIWindowScene*)scene).windows){
  NSMutableArray*stack=[NSMutableArray arrayWithObject:w];while(stack.count){UIView*v=stack.lastObject;[stack removeLastObject];if([NSStringFromClass(object_getClass(v))isEqualToString:@"YTAppView"]){for(UIView*s in v.subviews)if([NSStringFromClass(object_getClass(s))isEqualToString:@"YTPivotBarView"]||[s isKindOfClass:gPivotRuntimeSubclass])return AdoptPivot(s);return NO;}[stack addObjectsFromArray:v.subviews];}
 }
 return NO;
}
static void ScheduleAdoption(void){for(NSNumber*d in @[@0.0,@0.05,@0.15,@0.35,@0.75,@1.5,@3.0,@5.0])dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(d.doubleValue*NSEC_PER_SEC)),dispatch_get_main_queue(),^{FindAndAdopt();});}
__attribute__((constructor))static void StartGlass(void){dispatch_async(dispatch_get_main_queue(),^{ScheduleAdoption();[[NSNotificationCenter defaultCenter]addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification*n){ScheduleAdoption();}];});}

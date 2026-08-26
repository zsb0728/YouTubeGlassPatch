#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

// 仅开启 YouTube 自带 Frosted/Liquid Glass 开关；不创建、隐藏、移动或改色任何视图。
static BOOL YTGYes(id self,SEL cmd){return YES;} static BOOL YTGNo(id self,SEL cmd){return NO;}
static BOOL YTGIsBool(Method m){if(!m||method_getNumberOfArguments(m)!=2)return NO;char*t=method_copyReturnType(m);BOOL ok=t&&(t[0]=='B'||t[0]=='c'||t[0]=='C');if(t)free(t);return ok;}
static BOOL YTGFlag(const char*n,BOOL*v){static const char*yes[]={"isFrostedPivotBarPermitted","isLiquidGlassAvailable","computeIsLiquidGlassAvailable","useLiquidGlassStyling","mainAppCoreClientEnableModernIaFrostedBottomBar","mainAppCoreClientEnableModernIaFrostedBottomBarStartupScheduler","mainAppCoreClientEnableModernIaFrostedPivotBar","mainAppCoreClientEnableModernIaFrostedPivotBarClipped","mainAppCoreClientEnableModernIaFrostedPivotBarInvalidateOnMarginChange","mainAppCoreClientEnableModernIaFrostedPivotBarUpdatedBackdrop","mainAppCoreClientIosEnableModernIaFrostedBottomBarFixForSearch","mainAppCoreClientScheduleModernIaFrostedPivotBarInitializationAfterStartup"};if(!strcmp(n,"optOutOfFrostedPivotBar")){*v=NO;return YES;}for(NSUInteger i=0;i<sizeof(yes)/sizeof(yes[0]);i++)if(!strcmp(n,yes[i])){*v=YES;return YES;}return NO;}
static void YTGHook(Class c){unsigned n=0;Method*l=class_copyMethodList(c,&n);for(unsigned i=0;i<n;i++){BOOL v=NO;if(YTGFlag(sel_getName(method_getName(l[i])),&v)&&YTGIsBool(l[i]))method_setImplementation(l[i],v?(IMP)YTGYes:(IMP)YTGNo);}free(l);}
static void YTGEnable(void){int n=objc_getClassList(NULL,0);if(n<=0)return;Class*c=(__unsafe_unretained Class*)calloc(n,sizeof(Class));n=objc_getClassList(c,n);for(int i=0;i<n;i++){YTGHook(c[i]);YTGHook(object_getClass(c[i]));}free(c);}
__attribute__((constructor(101))) static void YTGOfficialFlagsStart(void){YTGEnable();dispatch_async(dispatch_get_main_queue(),^{for(NSNumber*d in @[@0.05,@0.2,@0.5,@1.0,@2.0])dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(d.doubleValue*NSEC_PER_SEC)),dispatch_get_main_queue(),^{YTGEnable();});});}

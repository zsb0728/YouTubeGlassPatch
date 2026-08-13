#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static NSString *lastSignature;
static NSInteger dumpIndex=0;

static NSString *ColorText(UIColor *c){
    if(!c)return @"nil"; CGFloat r=0,g=0,b=0,a=0;
    if([c getRed:&r green:&g blue:&b alpha:&a])return [NSString stringWithFormat:@"rgba(%.2f,%.2f,%.2f,%.2f)",r,g,b,a];
    CGFloat w=0;if([c getWhite:&w alpha:&a])return [NSString stringWithFormat:@"white(%.2f,%.2f)",w,a];
    return c.description;
}

static BOOL Interesting(UIView *v,UIWindow *w){
    CGRect r=[v convertRect:v.bounds toView:w]; CGFloat H=w.bounds.size.height;
    NSString *n=NSStringFromClass(v.class);
    return CGRectGetMinY(r)<360 || CGRectGetMaxY(r)>H-360 ||
      [n containsString:@"Pivot"]||[n containsString:@"Chip"]||[n containsString:@"Header"]||
      [n containsString:@"Bottom"]||[n containsString:@"TabBar"]||[n containsString:@"Mini"];
}

static void Walk(UIView *v,UIWindow *w,NSInteger depth,NSMutableString *out){
    if(Interesting(v,w)){
        CGRect r=[v convertRect:v.bounds toView:w];
        [out appendFormat:@"%*s%@ ptr=%p local=%@ win=%@ alpha=%.2f hidden=%d opaque=%d clips=%d bg=%@ sub=%lu super=%@\n",(int)MIN(depth,20)*2,"",NSStringFromClass(v.class),v,NSStringFromCGRect(v.frame),NSStringFromCGRect(r),v.alpha,v.hidden,v.opaque,v.clipsToBounds,ColorText(v.backgroundColor),(unsigned long)v.subviews.count,NSStringFromClass(v.superview.class)];
    }
    for(UIView *s in v.subviews)Walk(s,w,depth+1,out);
}

static void DumpHierarchy(void){
    NSMutableString *body=[NSMutableString string];
    [body appendFormat:@"time=%@ appState=%ld screens=%lu\n",NSDate.date,(long)UIApplication.sharedApplication.applicationState,(unsigned long)UIApplication.sharedApplication.connectedScenes.count];
    for(UIScene *scene in UIApplication.sharedApplication.connectedScenes)if([scene isKindOfClass:UIWindowScene.class]){
        [body appendFormat:@"SCENE %@ activation=%ld\n",scene.session.persistentIdentifier,(long)scene.activationState];
        for(UIWindow *w in ((UIWindowScene*)scene).windows){[body appendFormat:@"WINDOW level=%.1f key=%d frame=%@ root=%@\n",w.windowLevel,w.keyWindow,NSStringFromCGRect(w.frame),NSStringFromClass(w.rootViewController.class)];Walk(w,w,0,body);}
    }
    NSString *sig=[NSString stringWithFormat:@"%lu",(unsigned long)body.hash];
    if([sig isEqualToString:lastSignature])return; lastSignature=sig; dumpIndex++;
    NSArray *dirs=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES);if(!dirs.count)return;
    NSString *path=[dirs[0] stringByAppendingPathComponent:@"YouTubeGlass-Hierarchy.txt"];
    NSString *block=[NSString stringWithFormat:@"\n\n========== DUMP %ld ==========\n%@",(long)dumpIndex,body];
    if(![[NSFileManager defaultManager]fileExistsAtPath:path])[block writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    else {NSFileHandle *h=[NSFileHandle fileHandleForWritingAtPath:path];[h seekToEndOfFile];[h writeData:[block dataUsingEncoding:NSUTF8StringEncoding]];[h closeFile];}
}

__attribute__((constructor)) static void StartDiagnostic(void){
 dispatch_async(dispatch_get_main_queue(),^{
   for(int i=1;i<=180;i++)dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(i*2*NSEC_PER_SEC)),dispatch_get_main_queue(),^{DumpHierarchy();});
   [[NSNotificationCenter defaultCenter]addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification*n){dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{DumpHierarchy();});}];
 });
}

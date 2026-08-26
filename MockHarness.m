#import <UIKit/UIKit.h>

@interface YTAppView:UIView @end
@implementation YTAppView @end
@interface YTPivotBarItemView:UIView @property(nonatomic,getter=isSelected)BOOL selected;@end
@implementation YTPivotBarItemView @end
@interface YTPivotBarView:UIView @property(nonatomic,strong)UIView*itemContainer;@end
@implementation YTPivotBarView
-(void)layoutSubviews{[super layoutSubviews];self.itemContainer.frame=CGRectMake(0,1,self.bounds.size.width,81);}
@end

@interface MockFeed:UIView @end
@implementation MockFeed
-(void)drawRect:(CGRect)r{CGContextRef c=UIGraphicsGetCurrentContext();NSArray*colors=@[(__bridge id)[UIColor colorWithRed:.08 green:.55 blue:.92 alpha:1].CGColor,(__bridge id)[UIColor colorWithRed:.95 green:.18 blue:.36 alpha:1].CGColor,(__bridge id)[UIColor colorWithRed:.2 green:.8 blue:.45 alpha:1].CGColor];CGGradientRef g=CGGradientCreateWithColors(NULL,(__bridge CFArrayRef)colors,NULL);CGContextDrawLinearGradient(c,g,CGPointZero,CGPointMake(r.size.width,r.size.height),0);CGGradientRelease(g);}
@end

@interface AppDelegate:UIResponder<UIApplicationDelegate>@property UIWindow*window;@end
@implementation AppDelegate
-(BOOL)application:(UIApplication*)app didFinishLaunchingWithOptions:(NSDictionary*)opts{
 self.window=[[UIWindow alloc]initWithFrame:UIScreen.mainScreen.bounds];UIViewController*vc=[UIViewController new];YTAppView*root=[[YTAppView alloc]initWithFrame:self.window.bounds];vc.view=root;
 MockFeed*feed=[[MockFeed alloc]initWithFrame:root.bounds];feed.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;[root addSubview:feed];
 for(int i=0;i<4;i++){UIView*card=[[UIView alloc]initWithFrame:CGRectMake(20,100+i*190,root.bounds.size.width-40,160)];card.backgroundColor=[UIColor colorWithWhite:1 alpha:.18];card.layer.cornerRadius=24;[root addSubview:card];}
 YTPivotBarView*p=[[YTPivotBarView alloc]initWithFrame:CGRectMake(0,root.bounds.size.height-82,root.bounds.size.width,82)];p.backgroundColor=UIColor.whiteColor;p.opaque=YES;p.clipsToBounds=YES;
 UIView*container=[[UIView alloc]initWithFrame:CGRectMake(0,1,p.bounds.size.width,81)];container.backgroundColor=UIColor.whiteColor;p.itemContainer=container;[p addSubview:container];
 NSArray*titles=@[@"首页",@"订阅",@"历史",@"我"];for(int i=0;i<4;i++){CGFloat w=p.bounds.size.width/4;YTPivotBarItemView*item=[[YTPivotBarItemView alloc]initWithFrame:CGRectMake(i*w,0,w,47)];item.selected=i==0;UILabel*l=[[UILabel alloc]initWithFrame:item.bounds];l.text=titles[i];l.textAlignment=NSTextAlignmentCenter;l.font=[UIFont boldSystemFontOfSize:15];[item addSubview:l];[container addSubview:item];}
 [root addSubview:p];self.window.rootViewController=vc;[self.window makeKeyAndVisible];
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{[self verify:p root:root phase:@"initial"];CGFloat y=p.frame.origin.y;p.frame=CGRectMake(0,root.bounds.size.height,p.bounds.size.width,82);[p setNeedsLayout];[p layoutIfNeeded];[self verify:p root:root phase:@"offscreen"];p.frame=CGRectMake(0,y,p.bounds.size.width,82);[p setNeedsLayout];[p layoutIfNeeded];[self verify:p root:root phase:@"returned"];});return YES;
}
-(void)verify:(YTPivotBarView*)p root:(YTAppView*)root phase:(NSString*)phase API_AVAILABLE(ios(26.0)){
 NSMutableArray*glass=[NSMutableArray array];for(UIView*v in root.subviews)if([v isKindOfClass:UIVisualEffectView.class]&&[((UIVisualEffectView*)v).effect isKindOfClass:UIGlassEffect.class])[glass addObject:v];
 BOOL ok=glass.count==2&&p.backgroundColor==UIColor.clearColor;for(UIVisualEffectView*v in glass)ok=ok&&!v.userInteractionEnabled&&v.superview==root;
 if([phase isEqual:@"initial"]||[phase isEqual:@"returned"]){UIVisualEffectView*b=glass.count?glass[0]:nil;ok=ok&&fabs(b.frame.size.height-62)<.5&&fabs(b.frame.origin.x-22)<.5&&fabs(b.frame.origin.y-p.frame.origin.y)<.5;}
 NSDictionary*d=@{@"phase":phase,@"pass":@(ok),@"glassCount":@(glass.count),@"pivot":NSStringFromCGRect(p.frame),@"glass0":glass.count?NSStringFromCGRect(((UIView*)glass[0]).frame):@"none"};
 NSLog(@"YTG_MOCK_%@",d);NSString*dir=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;NSString*path=[dir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.json",phase]];[[NSJSONSerialization dataWithJSONObject:d options:0 error:nil]writeToFile:path atomically:YES];if(!ok)abort();
}
@end
int main(int argc,char**argv){@autoreleasepool{return UIApplicationMain(argc,argv,nil,NSStringFromClass(AppDelegate.class));}}

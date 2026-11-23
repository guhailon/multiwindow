#import "MWFloatGrabber.h"
#import "MWPassthroughWindow.h"
#import "MWSceneHelper.h"
#import "MWBackgrounderManager.h"
#import "MWHeaders.h"

#define MW_GRABBER_LOG(fmt, ...) NSLog(@"[MWGrabber] " fmt, ##__VA_ARGS__)

extern void mw_createWindowForApp(NSString *bundleID, NSString *sceneID);
extern void mw_goHome(void);

// 开关 plist（与巨魔分屏 App 设置联动）
#define MW_FLOAT_PREFS @"/var/mobile/Library/Preferences/com.ycwl.mwfloat.plist"
#define MW_FLOAT_KEY   @"MWFloatModeEnabled"
#define MW_FLOAT_NOTIFY CFSTR("com.ycwl.mwfloat.changed")

@implementation MWFloatGrabber {
    UIPanGestureRecognizer *_pan;
    BOOL _dragging;
}

+ (instancetype)sharedGrabber {
    static MWFloatGrabber *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] initWithFrame:CGRectZero];
    });
    return instance;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:CGRectMake(0, 0, 56, 56)];
    if (self) {
        self.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.55];
        self.layer.cornerRadius = 28;
        self.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.5].CGColor;
        self.layer.borderWidth = 1.0;
        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOpacity = 0.3;
        self.layer.shadowRadius = 4;
        self.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleLeftMargin;

        // 内部图标：圆角小窗 + 对角线，暗示"拖成小窗"
        UIImageView *icon = [[UIImageView alloc] initWithFrame:CGRectMake(15, 15, 26, 26)];
        icon.image = [self grabberIcon];
        icon.contentMode = UIViewContentModeScaleAspectFit;
        icon.tag = 999;
        [self addSubview:icon];

        _pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        [self addGestureRecognizer:_pan];
    }
    return self;
}

- (UIImage *)grabberIcon {
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(26, 26)];
    return [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        CGContextRef c = ctx.CGContext;
        [[UIColor whiteColor] setStroke];
        CGContextSetLineWidth(c, 2.0);
        // 大窗框
        UIBezierPath *outer = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(2, 2, 16, 16) cornerRadius:3];
        [outer stroke];
        // 小窗框（右下）
        UIBezierPath *inner = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(11, 11, 13, 13) cornerRadius:2];
        [[UIColor colorWithRed:0.3 green:0.6 blue:1.0 alpha:1.0] setFill];
        [[UIColor whiteColor] setStroke];
        [inner fill];
        [inner stroke];
    }];
}

- (void)attachToWindow:(UIWindow *)window {
    if (!window) return;
    // 右下角，避开 Home Indicator；iPhone X+ 底部安全区约 34pt
    CGFloat w = window.bounds.size.width;
    CGFloat h = window.bounds.size.height;
    self.frame = CGRectMake(w - 68, h - 130, 56, 56);
    [window addSubview:self];
    [self setEnabled:[self readEnabled]];

    // 监听开关变化（Darwin 通知，跨进程与 App 设置联动）
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                    (__bridge const void *)(self),
                                    mwFloatPrefsChanged,
                                    MW_FLOAT_NOTIFY,
                                    NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
}

static void mwFloatPrefsChanged(CFNotificationCenterRef center, void *observer,
                                CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        MWFloatGrabber *g = [MWFloatGrabber sharedGrabber];
        [g setEnabled:[g readEnabled]];
        MW_GRABBER_LOG(@"开关变化，当前=%d", [g readEnabled]);
    });
}

- (BOOL)readEnabled {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:MW_FLOAT_PREFS];
    if (!prefs || ![prefs objectForKey:MW_FLOAT_KEY]) return YES; // 默认开启
    return [[prefs objectForKey:MW_FLOAT_KEY] boolValue];
}

- (void)setEnabled:(BOOL)enabled {
    self.hidden = !enabled;
    self.userInteractionEnabled = enabled;
}

#pragma mark - 拖动手势

// 获取当前前台 App（SpringBoard 进程内）
- (SBApplication *)frontmostApplication {
    @try {
        SpringBoard *sb = (SpringBoard *)[UIApplication sharedApplication];
        SBApplication *app = nil;
        if ([sb respondsToSelector:@selector(_accessibilityFrontMostApplication)]) {
            app = [sb performSelector:@selector(_accessibilityFrontMostApplication)];
        }
        if (!app) {
            Class sbws = NSClassFromString(@"SBWorkspace");
            id ws = [sbws performSelector:@selector(sharedInstance)];
            for (NSString *sel in @[@"_currentApplication", @"currentApplication", @"frontmostApplication"]) {
                if ([ws respondsToSelector:NSSelectorFromString(sel)]) {
                    app = [ws performSelector:NSSelectorFromString(sel)];
                    if (app) break;
                }
            }
        }
        if (!app) {
            Class sac = NSClassFromString(@"SBApplicationController");
            id ctrl = [sac performSelector:@selector(sharedInstance)];
            if ([ctrl respondsToSelector:@selector(currentApplication)])
                app = [ctrl performSelector:@selector(currentApplication)];
        }
        return app;
    } @catch (NSException *e) {
        MW_GRABBER_LOG(@"frontmost exception: %@", e);
        return nil;
    }
}

- (void)handlePan:(UIPanGestureRecognizer *)gesture {
    if (![self readEnabled]) return;

    CGPoint translation = [gesture translationInView:self.superview];
    CGPoint velocity = [gesture velocityInView:self.superview];

    if (gesture.state == UIGestureRecognizerStateBegan) {
        _dragging = YES;
        MW_GRABBER_LOG(@"拖动开始");
    } else if (gesture.state == UIGestureRecognizerStateChanged) {
        // 手柄跟随手指移动（限制在屏幕内）
        CGPoint center = self.center;
        center.x += translation.x;
        center.y += translation.y;
        CGRect sb = self.superview.bounds;
        center.x = MAX(28, MIN(sb.size.width - 28, center.x));
        center.y = MAX(28, MIN(sb.size.height - 28, center.y));
        self.center = center;
        [gesture setTranslation:CGPointZero inView:self.superview];
    } else if (gesture.state == UIGestureRecognizerStateEnded ||
               gesture.state == UIGestureRecognizerStateCancelled) {
        _dragging = NO;
        // 判定：向左上拖动超过阈值，或速度快 → 触发窗口化
        BOOL shouldTrigger = (translation.x < -40 || translation.y < -40 ||
                              velocity.x < -500 || velocity.y < -500);
        MW_GRABBER_LOG(@"拖动结束 translation=(%.0f,%.0f) velocity=(%.0f,%.0f) trigger=%d",
                       translation.x, translation.y, velocity.x, velocity.y, shouldTrigger);

        // 手柄复位到右下角
        CGRect sb = self.superview.bounds;
        [UIView animateWithDuration:0.25 animations:^{
            self.frame = CGRectMake(sb.size.width - 68, sb.size.height - 130, 56, 56);
        }];

        if (shouldTrigger) {
            [self tryWindowizeFrontmostApp];
        }
    }
}

- (void)tryWindowizeFrontmostApp {
    SBApplication *app = [self frontmostApplication];
    NSString *bundleID = nil;
    if (app && [app respondsToSelector:@selector(bundleIdentifier)])
        bundleID = [app bundleIdentifier];
    if (!bundleID || [bundleID isEqualToString:@"com.apple.springboard"]) {
        MW_GRABBER_LOG(@"没有可窗口化的前台 App（bid=%@）", bundleID);
        return;
    }

    MW_GRABBER_LOG(@"窗口化前台 App: %@", bundleID);
    // 已经在悬浮窗里的不重复创建
    if ([MWPassthroughWindow isWindowed:bundleID]) {
        MW_GRABBER_LOG(@"%@ 已窗口化，跳过", bundleID);
        return;
    }

    NSString *sceneID = nil;
    FBScene *scene = [MWSceneHelper getFBScene:bundleID];
    if (scene && [scene respondsToSelector:@selector(identifier)])
        sceneID = [scene identifier];

    // 先完成窗口化（拖拉动作），返回桌面由窗口化完成后立即触发
    // 这样 App 画面先被包进悬浮窗，再回桌面，悬浮窗直接呈现在桌面上
    MW_GRABBER_LOG(@"拖拉完成，开始窗口化（稍后返回桌面）");
    mw_createWindowForApp(bundleID, sceneID);
}

@end

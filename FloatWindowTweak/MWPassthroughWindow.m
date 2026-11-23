#import "MWPassthroughWindow.h"
#import "MWWindowView.h"
#import <objc/message.h>

static MWPassthroughWindow *_sharedInstance = nil;
static NSMutableArray *_windowedIDs = nil;
static MWPassthroughWindow *_keyboardWindow = nil;

// 精确定位 SpringBoard 主显示 scene —— 关键！
// 注入 SpringBoard 后进程内有 SystemAperture/keyboard/外置显示等多个 scene，
// connectedScenes 第一个往往不是主屏 scene，导致 window 被 compositor 降到 App 之下。
static UIWindowScene *SBFMainScene(void) {
    UIApplication *app = [UIApplication sharedApplication];
    SEL sel = NSSelectorFromString(@"_mainDisplayWindowScene");
    if ([app respondsToSelector:sel]) {
        id s = ((id (*)(id, SEL))objc_msgSend)(app, sel);
        if ([s isKindOfClass:[UIWindowScene class]]) return (UIWindowScene *)s;
    }
    UIWindowScene *sbClassScene = nil, *fallback = nil;
    for (UIScene *c in app.connectedScenes) {
        if (![c isKindOfClass:[UIWindowScene class]]) continue;
        UIWindowScene *ws = (UIWindowScene *)c;
        NSString *sid = @"";
        NSString *role = @"";
        if (ws.session) {
            sid = ws.session.persistentIdentifier ?: @"";
            role = ws.session.role ?: @"";
        }
        NSString *cls = NSStringFromClass([ws class]);
        if ([sid rangeOfString:@"SystemAperture"].location != NSNotFound ||
            [sid rangeOfString:@"keyboard"].location != NSNotFound ||
            [role rangeOfString:@"SystemAperture"].location != NSNotFound ||
            [role rangeOfString:@"Keyboard"].location != NSNotFound) continue;
        if ([sid isEqualToString:@"com.apple.springboard"]) return ws;
        if (!sbClassScene && [cls isEqualToString:@"SBWindowScene"]) sbClassScene = ws;
        if (!fallback && ws.activationState == UISceneActivationStateForegroundActive) fallback = ws;
    }
    return sbClassScene ?: fallback;
}

@implementation MWPassthroughView

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *view = [super hitTest:point withEvent:event];
    return (view == self) ? nil : view;
}

@end

@implementation MWPassthroughWindow

+ (void)initialize {
    if (self == [MWPassthroughWindow class]) {
        _windowedIDs = [NSMutableArray array];
    }
}

+ (instancetype)sharedInstance {
    return _sharedInstance;
}

+ (void)setSharedInstance:(MWPassthroughWindow *)instance {
    _sharedInstance = instance;
}

+ (MWPassthroughWindow *)keyboardWindow {
    return _keyboardWindow;
}

+ (void)setKeyboardWindow:(MWPassthroughWindow *)window {
    _keyboardWindow = window;
}

- (instancetype)init {
    UIWindowScene *scene = SBFMainScene();

    if (scene) {
        self = [super initWithWindowScene:scene];
    } else {
        self = [super initWithFrame:[UIScreen mainScreen].bounds];
    }

    if (self) {
        if ([UIDevice currentDevice].userInterfaceIdiom != UIUserInterfaceIdiomPad) {
            [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
            [[NSNotificationCenter defaultCenter] addObserver:self
                                                     selector:@selector(deviceOrientationDidChange:)
                                                         name:UIDeviceOrientationDidChangeNotification
                                                       object:nil];
        }
    }
    return self;
}

- (instancetype)initWithNoRotation {
    UIWindowScene *scene = nil;
    for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
        if ([s isKindOfClass:[UIWindowScene class]]) {
            scene = (UIWindowScene *)s;
            break;
        }
    }

    if (scene) {
        self = [super initWithWindowScene:scene];
    } else {
        self = [super initWithFrame:[UIScreen mainScreen].bounds];
    }

    if (self) {
        if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
            UIInterfaceOrientation orientation = UIInterfaceOrientationPortrait;
            if (@available(iOS 13.0, *)) {
                UIWindowScene *ws = self.windowScene;
                if (ws) orientation = ws.interfaceOrientation;
            }

            CGFloat angle = 0;
            switch (orientation) {
                case UIInterfaceOrientationPortrait: angle = 0; break;
                case UIInterfaceOrientationLandscapeRight: angle = 270 * M_PI / 180.0; break;
                case UIInterfaceOrientationLandscapeLeft: angle = 90 * M_PI / 180.0; break;
                default: break;
            }
            self.transform = CGAffineTransformMakeRotation(angle);
            self.frame = [UIScreen mainScreen].bounds;
        }
    }
    return self;
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *view = [super hitTest:point withEvent:event];
    return (view == self) ? nil : view;
}

- (void)deviceOrientationDidChange:(NSNotification *)notification {
    UIDevice *device = notification.object;
    UIDeviceOrientation orientation = device.orientation;

    CGFloat angle = 0;
    switch (orientation) {
        case UIDeviceOrientationPortrait: angle = 0; break;
        case UIDeviceOrientationLandscapeRight: angle = 90 * M_PI / 180.0; break;
        case UIDeviceOrientationLandscapeLeft: angle = 270 * M_PI / 180.0; break;
        default: return;
    }

    [UIView animateWithDuration:0.3 delay:0 options:0 animations:^{
        self.transform = CGAffineTransformMakeRotation(angle);
        self.frame = [UIScreen mainScreen].bounds;
    } completion:nil];
}

// 运行时重绑到 SpringBoard 主 scene（scene 在 didFinishLaunching 时可能尚未就绪）
- (BOOL)ensureBoundToMainScene {
    UIWindowScene *mainScene = SBFMainScene();
    if (!mainScene) return NO;
    if (self.windowScene == mainScene) return NO;
    self.windowScene = mainScene;
    CGRect bounds = mainScene.coordinateSpace.bounds;
    if (!CGRectIsEmpty(bounds)) self.frame = bounds;
    return YES;
}

+ (BOOL)isWindowed:(NSString *)bundleID {
    if (!bundleID) return NO;
    for (NSString *wid in _windowedIDs) {
        if ([wid isEqualToString:bundleID]) return YES;
    }
    return NO;
}

+ (void)addWindowedId:(NSString *)bundleID {
    if (bundleID && ![_windowedIDs containsObject:bundleID])
        [_windowedIDs addObject:bundleID];
}

+ (void)removeWindowedId:(NSString *)bundleID {
    if (bundleID)
        [_windowedIDs removeObject:bundleID];
}

+ (void)notifyUpdateLayers {
    MWPassthroughWindow *window = [self sharedInstance];
    if (!window) return;

    UIView *rootView = window;
    if (window.rootViewController) {
        rootView = window.rootViewController.view ?: window;
    }

    for (UIView *subview in rootView.subviews) {
        if ([subview isKindOfClass:[MWWindowView class]]) {
            [(MWWindowView *)subview updateLayers];
        }
    }
}

@end

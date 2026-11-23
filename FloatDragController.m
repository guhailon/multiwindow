#import "FloatDragController.h"
#import <objc/runtime.h>

@interface FloatDragController ()
@property(nonatomic, strong) UIWindow *handleWindow;
@property(nonatomic, weak) UIView *targetView;
@property(nonatomic, strong) UIView *handleView;
@end

@implementation FloatDragController

+ (instancetype)shared {
    static FloatDragController *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[FloatDragController alloc] init];
    });
    return instance;
}

// 找到主界面的 windowScene（keyWindow 所在 scene），手柄窗口必须与它关联，
// 否则 iOS 13+ 下 window 不参与触摸分发，手势收不到。
- (UIWindowScene *)mainScene {
    UIWindowScene *scene = UIApplication.sharedApplication.keyWindow.windowScene;
    if (scene) return scene;
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if ([s isKindOfClass:UIWindowScene.class]) {
            return (UIWindowScene *)s;
        }
    }
    return nil;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        CGFloat side = 64;
        UIView *handle = [[UIView alloc] initWithFrame:CGRectMake(0, 0, side, side)];
        handle.backgroundColor = [[UIColor systemBlueColor] colorWithAlphaComponent:0.5];
        handle.layer.cornerRadius = 12;
        handle.layer.masksToBounds = YES;
        handle.layer.borderWidth = 2;
        handle.layer.borderColor = [UIColor whiteColor].CGColor;

        CAShapeLayer *tri = [CAShapeLayer layer];
        UIBezierPath *path = [UIBezierPath bezierPath];
        [path moveToPoint:CGPointMake(side, side * 0.3)];
        [path addLineToPoint:CGPointMake(side, side)];
        [path addLineToPoint:CGPointMake(side * 0.3, side)];
        [path closePath];
        tri.path = path.CGPath;
        tri.fillColor = [UIColor whiteColor].CGColor;
        [handle.layer addSublayer:tri];

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        [handle addGestureRecognizer:pan];
        self.handleView = handle;
        NSLog(@"[MW-Float] handleView created, pan attached");
    }
    return self;
}

// 确保手柄窗口已创建并与主 scene 关联（延迟到 attach 时，scene 此时一定就绪）。
- (void)ensureWindow {
    if (self.handleWindow) return;
    UIWindowScene *scene = [self mainScene];
    UIWindow *w;
    if (scene) {
        w = [[UIWindow alloc] initWithWindowScene:scene];
        NSLog(@"[MW-Float] handleWindow created with scene: %@", scene);
    } else {
        w = [[UIWindow alloc] initWithFrame:CGRectZero];
        NSLog(@"[MW-Float] WARNING: no scene, handleWindow created with frame only");
    }
    // 确定性的高层级：远高于系统 alert(2000)，保证盖在 hosted app window 之上。
    w.windowLevel = UIWindowLevelAlert + 5000;
    w.backgroundColor = [UIColor clearColor];
    w.hidden = YES;
    w.userInteractionEnabled = YES;
    [w addSubview:self.handleView];
    self.handleWindow = w;
}

- (void)attachToView:(UIView *)target {
    [self ensureWindow];
    self.targetView = target;
    self.handleWindow.hidden = NO;
    [self syncFrame];
    NSLog(@"[MW-Float] attach target=%@ frame=%@", target, NSStringFromCGRect(target.frame));
}

- (void)detachFromView:(UIView *)target {
    if (self.targetView == target) {
        self.targetView = nil;
        self.handleWindow.hidden = YES;
        NSLog(@"[MW-Float] detach");
    }
}

// 手柄窗口只占目标窗口右下角，跟随目标 frame（屏幕坐标）。
- (void)syncFrame {
    UIView *target = self.targetView;
    if (!target || target.hidden || !target.superview) {
        self.handleWindow.hidden = YES;
        return;
    }
    // 把 target 在父视图中的 frame 转成屏幕坐标
    CGRect rectInWindow = [target.superview convertRect:target.frame toView:nil];
    CGFloat side = 64;
    CGFloat hx = CGRectGetMaxX(rectInWindow) - side + 6;
    CGFloat hy = CGRectGetMaxY(rectInWindow) - side + 6;
    CGRect screen = UIScreen.mainScreen.bounds;
    hx = MIN(MAX(hx, 0), screen.size.width - side);
    hy = MIN(MAX(hy, 0), screen.size.height - side);
    self.handleWindow.frame = CGRectMake(hx, hy, side, side);
    self.handleWindow.hidden = NO;
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    UIView *target = self.targetView;
    if (!target) return;

    CGPoint delta = [pan translationInView:self.handleWindow];
    [pan setTranslation:CGPointZero inView:self.handleWindow];

    CGRect f = target.frame;
    CGFloat minSize = 140;
    CGRect screen = UIScreen.mainScreen.bounds;
    CGFloat maxW = screen.size.width - f.origin.x;
    CGFloat maxH = screen.size.height - f.origin.y;
    f.size.width = MIN(maxW, MAX(minSize, f.size.width + delta.x));
    f.size.height = MIN(maxH, MAX(minSize, f.size.height + delta.y));
    target.frame = f;

    [self syncFrame];
    NSLog(@"[MW-Float] pan delta=%@ newFrame=%@", NSStringFromCGPoint(delta), NSStringFromCGRect(f));

    if ([target isKindOfClass:NSClassFromString(@"DecoratedAppSceneView")]) {
        [target performSelector:@selector(refreshHostedSceneAfterResize)];
    }
}

@end

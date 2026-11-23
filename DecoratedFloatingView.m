#import "DecoratedFloatingView.h"
#import "ResizeHandleView.h"

@implementation DecoratedFloatingView

- (instancetype)initWithFrame:(CGRect)frame {
    // Navigation bar. Shift it visually below the status bar via transform
    // ONLY — never change its frame or contentView geometry, because the
    // hosted app scene is sized from those bounds and any change blanks it.
    UINavigationBar *navigationBar = [[UINavigationBar alloc] initWithFrame:CGRectMake(0, 0, frame.size.width, 44)];
    navigationBar.transform = CGAffineTransformMakeTranslation(0, 44);
    navigationBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    UINavigationItem *navigationItem = [[UINavigationItem alloc] initWithTitle:@"Unnamed window"];
    navigationBar.items = @[navigationItem];
    return [self initWithFrame:frame navigationBar:navigationBar];
}

- (instancetype)initWithFrame:(CGRect)frame navigationBar:(UINavigationBar *)navigationBar {
    self = [super initWithFrame:frame];
    self.backgroundColor = UIColor.systemBackgroundColor;
    self.layer.cornerRadius = 10;
    self.layer.masksToBounds = YES;

    self.navigationBar = navigationBar;
    self.navigationItem = navigationBar.items.firstObject;
    if (!self.navigationBar.superview) {
        [self addSubview:self.navigationBar];
    }
    
    CGFloat navBarHeight = self.navigationBar.frame.size.height;
    CGRect contentFrame = CGRectMake(0, navBarHeight, self.frame.size.width, self.frame.size.height - navBarHeight);

    UIView *contentView = [[UIView alloc] initWithFrame:contentFrame];
    contentView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    contentView.layer.anchorPoint = CGPointMake(0, 0);
    contentView.layer.position = CGPointMake(0, self.navigationBar.frame.size.height);
    self.contentView = contentView;
    [self addSubview:contentView];

    UIPanGestureRecognizer *moveGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(moveWindow:)];
    moveGesture.minimumNumberOfTouches = 1;
    moveGesture.maximumNumberOfTouches = 1;
    [self.navigationBar addGestureRecognizer:moveGesture];

    // Resize handle (idea stolen from Notes debugging window)
    UIPanGestureRecognizer *resizeGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(resizeWindow:)];
    resizeGesture.minimumNumberOfTouches = 1;
    resizeGesture.maximumNumberOfTouches = 1;
    // Bigger hit target (72pt) so the bottom-right resize corner is easy to grab.
    self.resizeHandle = [[ResizeHandleView alloc] initWithFrame:CGRectMake(self.frame.size.width - 72, self.frame.size.height - 72, 72, 72)];
    [self.resizeHandle addGestureRecognizer:resizeGesture];
    [self addSubview:self.resizeHandle];

    // hosted app 的 presentationView 会铺满 contentView，可能吞掉右下角的触摸。
    // 把导航条和缩放手柄提到最前（只改层级，绝不改 contentView 的几何/尺寸）。
    [self bringSubviewToFront:self.navigationBar];
    [self bringSubviewToFront:self.resizeHandle];

    self.layer.borderWidth = 1.0;
    self.layer.borderColor = UIColor.secondarySystemBackgroundColor.CGColor;
    
    return self;
}

- (void)moveWindow:(UIPanGestureRecognizer*)sender {
    CGPoint point = [sender translationInView:self];
    [sender setTranslation:CGPointZero inView:self];

    self.center = CGPointMake(self.center.x + point.x, self.center.y + point.y);
}

- (void)resizeWindow:(UIPanGestureRecognizer*)sender {
    CGPoint point = [sender translationInView:self];
    [sender setTranslation:CGPointZero inView:self];

    CGRect frame = self.frame;
    frame.size.width = MAX(50, frame.size.width + point.x);
    frame.size.height = MAX(50, frame.size.height + point.y);
    self.frame = frame;
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesBegan:touches withEvent:event];
    // FIXME: how to bring view to front when touching the passthrough view?
    [self.superview bringSubviewToFront:self];
}

// hosted app 画面可能覆盖整个内容区并吞掉右下角触摸。
// 触点落在缩放手柄范围内时直接返回手柄，保证右下角拖动缩放必定触发。
// 注意：只做触摸分发，绝不修改 contentView 的 frame/bounds（改了会黑屏）。
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (!self.resizeHandle.hidden && self.resizeHandle.userInteractionEnabled) {
        if (CGRectContainsPoint(self.resizeHandle.frame, point)) {
            return self.resizeHandle;
        }
    }
    return hit;
}

@end

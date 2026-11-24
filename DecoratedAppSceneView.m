#import "DecoratedAppSceneView.h"
#import "AppSceneViewController.h"
#import "UIKitPrivate+MultitaskSupport.h"
#import "PiPManager.h"
#import "MWLog.h"
#import <objc/runtime.h>

@interface RBSTarget : NSObject
@end
@implementation RBSTarget(hook)
+ (instancetype)hook_targetWithPid:(pid_t)pid environmentIdentifier:(NSString *)environmentIdentifier {
    if([environmentIdentifier containsString:@"LiveProcess"]) {
        environmentIdentifier = [NSString stringWithFormat:@"LiveProcess:%d", pid];
    }
    return [self hook_targetWithPid:pid environmentIdentifier:environmentIdentifier];
}
@end

void swizzleClass(Class class, SEL originalAction, SEL swizzledAction) {
    method_exchangeImplementations(class_getClassMethod(class, originalAction), class_getClassMethod(class, swizzledAction));
}

static int hook_return_2(void) {
    return 2;
}
__attribute__((constructor))
void UIKitFixesInit(void) {
    // Fix _UIPrototypingMenuSlider not continually updating its value on iOS 17+
    Class _UIFluidSliderInteraction = objc_getClass("_UIFluidSliderInteraction");
    if(_UIFluidSliderInteraction) {
        method_setImplementation(class_getInstanceMethod(_UIFluidSliderInteraction, @selector(_state)), (IMP)hook_return_2);
    }
    // TODO: Fix keyboard focus
    swizzleClass(RBSTarget.class, @selector(targetWithPid:environmentIdentifier:), @selector(hook_targetWithPid:environmentIdentifier:));
}

@interface DecoratedAppSceneView()
@property(nonatomic) AppSceneViewController* appSceneView;
@property(nonatomic) NSString *sceneID;
@property(nonatomic) NSString* windowName;
@property(nonatomic) int pid;
@property(nonatomic) CGFloat scaleRatio;
// FIX (1.0.1): content size the scene was created/synced at. The window
// animates open from the tapped cell frame, so contentView.bounds is
// transient at scene-creation time; these pin the intended size and track
// the last size pushed to the scene.
@property(nonatomic) CGRect intendedContentFrame;
@property(nonatomic) CGSize lastSyncedContentSize;

@end

@implementation DecoratedAppSceneView
- (instancetype)initWithApp:(LSApplicationProxy *)app windowName:(NSString*)windowName {
    self = [super initWithFrame:UIScreen.mainScreen.bounds];
    self.scaleRatio = 1.0;
    // FIX (1.0.1): capture the intended content size NOW, while the window
    // is still at its full-screen frame. didSelectRow shrinks this window to
    // the tapped cell frame and animates it back over 0.4s, so
    // contentView.bounds at launch-completion time is cell-sized or
    // mid-animation — the scene used to be created at that wrong size and
    // never re-synced, which is why Settings rendered as a clipped strip
    // and QQ as a blank window.
    self.intendedContentFrame = CGRectMake(0, 0, self.contentView.bounds.size.width, self.contentView.bounds.size.height);
    self.lastSyncedContentSize = self.intendedContentFrame.size;
    // LOG (1.0.2): what size did we capture at init, before didSelectRow
    // shrinks this window to the tapped cell frame?
    MWLog(@"DASV", @"init %@ self=%@ content=%@ intended=%@", windowName, NSStringFromCGRect(self.frame), NSStringFromCGRect(self.contentView.bounds), NSStringFromCGRect(self.intendedContentFrame));
    NSArray *menuItems = @[
        [UIAction actionWithTitle:@"复制进程号" image:[UIImage systemImageNamed:@"doc.on.doc"] identifier:nil handler:^(UIAction * _Nonnull action) {
            UIPasteboard.generalPasteboard.string = @(self.pid).stringValue;
        }],
        [UIAction actionWithTitle:@"开启悬浮窗" image:[UIImage systemImageNamed:@"pip.enter"] identifier:nil handler:^(UIAction * _Nonnull action) {
            if ([PiPManager.shared isPiPWithView:self.appSceneView.view]) {
                [PiPManager.shared stopPiP];
            } else {
                [PiPManager.shared startPiPWithView:self.appSceneView.view contentView:self.contentView];
            }
        }],
        [UICustomViewMenuElement elementWithViewProvider:^UIView *(UICustomViewMenuElement *element) {
            return [self scaleSliderViewWithTitle:@"缩放" min:0.5 max:2.0 value:self.scaleRatio stepInterval:0.01];
        }]
    ];
    
    if(@available(iOS 16.0, *)) {
        __weak typeof(self) weakSelf = self;
        [self.navigationItem setTitleMenuProvider:^UIMenu *(NSArray<UIMenuElement *> *suggestedActions){
            NSString *pidText = [NSString stringWithFormat:@"进程号: %d", self.pid];
            return [UIMenu menuWithTitle:pidText children:menuItems];
        }];
    }
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose target:self action:@selector(closeWindow)];
    self.windowName = windowName;
    self.navigationItem.title = windowName;
    
    NSString *bundleID = app.bundleIdentifier;
    //self.transitionContext = [UIApplicationSceneTransitionContext new];
    RBSProcessIdentity* identity = [RBSProcessIdentity identityForEmbeddedApplicationIdentifier:bundleID];
    RBSProcessPredicate* predicate = [RBSProcessPredicate predicateMatchingIdentity:identity];
    FBProcessManager *manager = FBProcessManager.sharedInstance;
    FBApplicationProcessLaunchTransaction *transaction = [[FBApplicationProcessLaunchTransaction alloc] initWithProcessIdentity:identity executionContextProvider:^id(void){
        FBMutableProcessExecutionContext *context = [FBMutableProcessExecutionContext new];
        context.identity = identity;
        context.environment = @{}; // environment variables
        //context.waitForDebugger = NO;
        //context.disableASLR = NO;
        context.launchIntent = 4;
        //context.watchdogProvider = SBSceneWatchdogProvider
        return [manager launchProcessWithContext:context];
    }];
    
    [transaction setCompletionBlock:^{
        // LOG (1.0.2): what is the window/content size NOW (after the 0.4s
        // open animation may have shrunk it), and what frame goes into the
        // scene creation? Compare with the init line above.
        MWLog(@"DASV", @"launchDone %@ self.frame=%@ content.bounds=%@ intended=%@", windowName, NSStringFromCGRect(self.frame), NSStringFromCGRect(self.contentView.bounds), NSStringFromCGRect(self.intendedContentFrame));
        // FIX (1.0.1): create the scene at the intended final content size,
        // not the transient contentView.bounds (see initWithApp above).
        AppSceneViewController* appSceneView = [[AppSceneViewController alloc] initWithApp:app frame:self.intendedContentFrame delegate:self];
        appSceneView.view.layer.anchorPoint = CGPointMake(0, 0);
        appSceneView.view.layer.position = CGPointMake(0, 0);
        self.appSceneView = appSceneView;
        self.pid = appSceneView.pid;
        [self.contentView insertSubview:appSceneView.view atIndex:0];
        MWLog(@"DASV", @"presented %@ pid=%d view.frame=%@ content.bounds=%@", windowName, self.pid, NSStringFromCGRect(appSceneView.view.frame), NSStringFromCGRect(self.contentView.bounds));
        if(@available(iOS 16.0, *)) {} else {
            [self iOS15SetupTitleMenu:menuItems];
        }
        // Do NOT auto-promote to PiP here. Moving appSceneView.view into the
        // system PiP container empties the split-view window (white screen),
        // and suspending the host freezes all touch handling. Keep the app
        // view inside contentView so the split window stays interactive.
        // Users can still enter PiP manually from the title menu.
    }];
    [transaction begin];

    return self;
}

// FIX (1.0.1): the scene frame must always equal the floating window's
// content size. The open animation, drags and resizes all change
// contentView.bounds, but nothing re-synced the scene after creation.
// Re-sync whenever the content size actually changes (guarded so animation
// frames don't spam scene updates; resizeWindowWithFrame already debounces
// the settings push by 0.05s).
- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize size = self.contentView.bounds.size;
    if (fabs(size.width - self.lastSyncedContentSize.width) > 0.5 ||
        fabs(size.height - self.lastSyncedContentSize.height) > 0.5) {
        // LOG (1.0.2): did the re-sync fire at all, and from what size to what?
        MWLog(@"DASV", @"layoutSync size=%@ last=%@ scale=%.2f", NSStringFromCGSize(size), NSStringFromCGSize(self.lastSyncedContentSize), self.scaleRatio);
        self.lastSyncedContentSize = size;
        [self.appSceneView resizeWindowWithFrame:CGRectMake(0, 0, size.width / self.scaleRatio, size.height / self.scaleRatio)];
    }
}

// Called by FloatDragController after a drag-resize. It used to call this
// selector, which did not exist, so drag-resizes never updated the scene.
- (void)refreshHostedSceneAfterResize {
    CGSize size = self.contentView.bounds.size;
    MWLog(@"DASV", @"refreshAfterResize content=%@ scale=%.2f", NSStringFromCGRect(self.contentView.bounds), self.scaleRatio);
    self.lastSyncedContentSize = size;
    [self.appSceneView resizeWindowWithFrame:CGRectMake(0, 0, size.width / self.scaleRatio, size.height / self.scaleRatio)];
}

- (void)iOS15SetupTitleMenu:(NSArray<UIMenuElement *> *)menuItems {
    // https://github.com/LiveContainer/LiveContainer/commit/6ad506b7aef92d639178f17d88bbd0b77cfe2c69#diff-e3748f6b0b007ce504c448dfa3e22869c3a360a455672fc310083bc6a1e361a3
    UIImageSymbolConfiguration* sc1 = [UIImageSymbolConfiguration configurationWithPaletteColors:@[UIColor.secondaryLabelColor,UIColor.secondarySystemFillColor]];
    
    UIImageSymbolConfiguration* sc2 = [UIImageSymbolConfiguration configurationWithScale:UIImageSymbolScaleMedium];
    UIImageSymbolConfiguration* sc = [sc1 configurationByApplyingConfiguration:sc2];
    UIImage* dropDownImage = [UIImage systemImageNamed:@"chevron.down.circle.fill" withConfiguration:sc];
    
    UIButtonConfiguration* bc = [UIButtonConfiguration plainButtonConfiguration];
    bc.imagePadding = 4;
    bc.imagePlacement = NSDirectionalRectEdgeTrailing;
    bc.titleTextAttributesTransformer = ^(NSDictionary<NSAttributedStringKey, id> *incoming) {
        NSMutableDictionary<NSAttributedStringKey, id> *outgoing = [incoming mutableCopy];
        outgoing[NSFontAttributeName] = self.navigationBar._defaultTitleFont;
        return outgoing;
    };
    UIButton *titleView = [UIButton buttonWithConfiguration:bc primaryAction:nil];
    
    [titleView setTitleColor:UIColor.labelColor forState:UIControlStateNormal];
    [titleView setTitleColor:UIColor.secondaryLabelColor forState:UIControlStateHighlighted];
    //[UIFont boldSystemFontOfSize:_doneButton.titleLabel.font.pointSize]];
    titleView.showsMenuAsPrimaryAction = YES;
    [titleView setTitle:self.windowName forState:UIControlStateNormal];
    [titleView setImage:dropDownImage forState:UIControlStateNormal];
    
    NSString *pidText = [NSString stringWithFormat:@"进程号: %d", self.pid];
    titleView.menu = [UIMenu menuWithTitle:pidText children:menuItems];
    
    self.navigationBar.overrideUserInterfaceStyle = UIUserInterfaceStyleUnspecified;
    [self.navigationBar.standardAppearance configureWithTransparentBackground];
    self.navigationBar.standardAppearance.backgroundColor = [UIColor.secondarySystemBackgroundColor colorWithAlphaComponent:0.7];
    self.navigationItem.titleView = titleView;
}

// Stolen from UIKitester
- (UIView *)scaleSliderViewWithTitle:(NSString *)title min:(CGFloat)minValue max:(CGFloat)maxValue value:(CGFloat)initialValue stepInterval:(CGFloat)step {
    UIView *containerView = [[UIView alloc] init];
    containerView.translatesAutoresizingMaskIntoConstraints = NO;
    containerView.exclusiveTouch = YES;
    
    UIStackView *stackView = [[UIStackView alloc] init];
    stackView.axis = UILayoutConstraintAxisVertical;
    stackView.spacing = 0.0;
    stackView.translatesAutoresizingMaskIntoConstraints = NO;
    [containerView addSubview:stackView];
    
    [NSLayoutConstraint activateConstraints:@[
        [stackView.topAnchor constraintEqualToAnchor:containerView.topAnchor constant:10.0],
        [stackView.bottomAnchor constraintEqualToAnchor:containerView.bottomAnchor constant:-8.0],
        [stackView.leadingAnchor constraintEqualToAnchor:containerView.leadingAnchor constant:16.0],
        [stackView.trailingAnchor constraintEqualToAnchor:containerView.trailingAnchor constant:-16.0]
    ]];
    
    UILabel *label = [[UILabel alloc] init];
    label.text = title;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.font = [UIFont boldSystemFontOfSize:12.0];
    [stackView addArrangedSubview:label];
    
    _UIPrototypingMenuSlider *slider = [[_UIPrototypingMenuSlider alloc] init];
    slider.minimumValue = minValue;
    slider.maximumValue = maxValue;
    slider.value = initialValue;
    slider.stepSize = step;
    
    NSLayoutConstraint *sliderHeight = [slider.heightAnchor constraintEqualToConstant:40.0];
    sliderHeight.active = YES;
    
    [stackView addArrangedSubview:slider];
    
    [slider addTarget:self action:@selector(scaleSliderChanged:) forControlEvents:UIControlEventValueChanged];
    
    return containerView;
}

- (void)scaleSliderChanged:(_UIPrototypingMenuSlider *)slider {
    self.scaleRatio = slider.value;
    CGSize size = self.contentView.bounds.size;
    self.contentView.layer.sublayerTransform = CATransform3DMakeScale(_scaleRatio, _scaleRatio, 1.0);
    [self.appSceneView resizeWindowWithFrame:CGRectMake(0, 0, size.width / _scaleRatio, size.height / _scaleRatio)];
}

- (void)closeWindow {
    [self.appSceneView closeWindow];
}

- (void)resizeWindow:(UIPanGestureRecognizer*)sender {
    [super resizeWindow:sender];
    CGSize size = self.contentView.bounds.size;
    if (sender.state == UIGestureRecognizerStateEnded || sender.state == UIGestureRecognizerStateCancelled) {
        MWLog(@"DASV", @"resizeWindow end content=%@ scale=%.2f", NSStringFromCGRect(self.contentView.bounds), self.scaleRatio);
    }
    [self.appSceneView resizeWindowWithFrame:CGRectMake(0, 0, size.width / _scaleRatio, size.height / _scaleRatio)];

    // 拖动缩放不再自动进入画中画/回桌面：搬走 appSceneView.view 会让分屏
    // 窗口失去宿主而白屏，suspend 又会冻结场景渲染。保持 view 在 contentView
    // 内，分屏窗口稳定显示实时内容。手动悬浮窗仍可从标题菜单开启。
}

- (void)appDidExit {
    self.layer.masksToBounds = NO;
    [UIView transitionWithView:self duration:0.4 options:UIViewAnimationOptionTransitionCurlUp animations:^{
        self.hidden = YES;
    } completion:^(BOOL b){
        [self removeFromSuperview];
    }];
}
@end

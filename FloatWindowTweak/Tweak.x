#import "MWHeaders.h"
#import "MWWindowView.h"
#import "MWPassthroughWindow.h"
#import "MWSceneHelper.h"
#import "MWBackgrounderManager.h"
#import "MWThemeManager.h"
#import "MWFloatGrabber.h"

#define SCALE_MODE_PLIST @"/var/mobile/Library/Preferences/com.ycwl.mwfloat.scalemode.plist"
#define MW_LOG(fmt, ...) NSLog(@"[MWFloat] " fmt, ##__VA_ARGS__)

// RBSAssertion 静态持有，防止 ARC 释放导致进程被挂起
static NSMutableDictionary *_activeAssertions = nil;

// 创建 _UISceneLayerHostContainerView（跨 iOS 版本）
static _UISceneLayerHostContainerView *mw_createSceneContainer(FBScene *scene) {
    Class containerClass = NSClassFromString(@"_UISceneLayerHostContainerView");
    if (!containerClass) return nil;
    _UISceneLayerHostContainerView *container = nil;
    if ([containerClass instancesRespondToSelector:@selector(initWithScene:debugDescription:)]) {
        container = [[containerClass alloc] initWithScene:scene debugDescription:@"MWFloat"];
    } else if ([containerClass instancesRespondToSelector:@selector(initWithScene:)]) {
        container = [[containerClass alloc] initWithScene:scene];
    }
    return container;
}

// ============================================================
// 返回主屏幕：iOS 15-17 多级兜底（全部字符串动态调用，无需私有头）
// ============================================================
static id mw_mainScene(void) {
    UIApplication *app = [UIApplication sharedApplication];
    SEL s = NSSelectorFromString(@"_mainDisplayWindowScene");
    if ([app respondsToSelector:s]) {
        id scene = ((id (*)(id, SEL))objc_msgSend)(app, s);
        if (scene) return scene;
    }
    id workspace = [NSClassFromString(@"SBMainWorkspace") sharedInstance];
    SEL s2 = NSSelectorFromString(@"mainWindowScene");
    if (workspace && [workspace respondsToSelector:s2]) {
        id scene = ((id (*)(id, SEL))objc_msgSend)(workspace, s2);
        if (scene) return scene;
    }
    return nil;
}

void mw_goHome(void) {
    id sb = [UIApplication sharedApplication];
    id uc = [NSClassFromString(@"SBUIController") sharedInstance];
    id scene = mw_mainScene();

    // ① iOS 15-17 首选：走真实 Home 键处理链
    SEL sel = NSSelectorFromString(@"handleHomeButtonSinglePressUpForWindowScene:");
    if (uc && [uc respondsToSelector:sel] && scene) {
        ((BOOL (*)(id, SEL, id))objc_msgSend)(uc, sel, scene);
        MW_LOG(@"goHome: handleHomeButtonSinglePressUpForWindowScene:");
        return;
    }
    // ② iOS 13-14 老 selector
    SEL old = NSSelectorFromString(@"handleHomeButtonSinglePressUp");
    if (uc && [uc respondsToSelector:old]) {
        ((BOOL (*)(id, SEL))objc_msgSend)(uc, old);
        MW_LOG(@"goHome: handleHomeButtonSinglePressUp");
        return;
    }
    // ③ iOS 17 simulate 版本（带 completion 参数）
    SEL sim = NSSelectorFromString(@"_simulateHomeButtonPressWithCompletion:");
    if ([sb respondsToSelector:sim]) {
        ((void (*)(id, SEL, id))objc_msgSend)(sb, sim, nil);
        MW_LOG(@"goHome: _simulateHomeButtonPressWithCompletion:");
        return;
    }
    // ④ 直接返回主屏方法
    SEL rth = NSSelectorFromString(@"_returnToHomeScreenWithCompletion:");
    if ([sb respondsToSelector:rth]) {
        ((void (*)(id, SEL, id))objc_msgSend)(sb, rth, nil);
        MW_LOG(@"goHome: _returnToHomeScreenWithCompletion:");
        return;
    }
    SEL rst = NSSelectorFromString(@"_resetToHomeScreen:");
    if ([sb respondsToSelector:rst]) {
        ((void (*)(id, SEL, id))objc_msgSend)(sb, rst, nil);
        MW_LOG(@"goHome: _resetToHomeScreen:");
        return;
    }
    // ⑤ 最后的无参兜底
    SEL sim0 = NSSelectorFromString(@"_simulateHomeButtonPress");
    if ([sb respondsToSelector:sim0]) {
        ((void (*)(id, SEL))objc_msgSend)(sb, sim0);
        MW_LOG(@"goHome: _simulateHomeButtonPress");
    }
}

// ============================================================
// 窗口化核心：把指定 bundleID 的 App scene 包装进悬浮窗
// 暴露为 C 函数供右下角手柄（MWFloatGrabber）调用
// ============================================================
void mw_createWindowForApp(NSString *bundleID, NSString *sceneID) {
    if (!bundleID) return;
    MW_LOG(@"窗口化 %@ (scene: %@)", bundleID, sceneID);

    [[MWBackgrounderManager sharedInstance] setForegroundSceneID:(sceneID ?: bundleID) enabled:YES];
    [[MWBackgrounderManager sharedInstance] setForeground:bundleID enabled:YES];
    [MWSceneHelper wakeUpScene:bundleID];

    MWPassthroughWindow *hostWindow = [MWPassthroughWindow sharedInstance];
    if (!hostWindow) {
        MW_LOG(@"错误：宿主窗口不存在，延迟重试");
        // 宿主窗口尚未就绪时延迟重试一次（注入时机晚于 didFinishLaunching 的兜底）
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            MWPassthroughWindow *w = [MWPassthroughWindow sharedInstance];
            if (w) mw_createWindowForApp(bundleID, sceneID);
        });
        return;
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        FBScene *scene = [MWSceneHelper getFBScene:bundleID];
        if (!scene && sceneID) scene = [MWSceneHelper getFBScene:sceneID];
        if (!scene) {
            MW_LOG(@"错误：找不到 %@ 的 FBScene", bundleID);
            return;
        }

        [MWSceneHelper setSceneForeground:scene foreground:YES];

        UIView *contentView = nil;
        _UISceneLayerHostContainerView *container = mw_createSceneContainer(scene);
        if (container) {
            id containerScene = [container scene];
            if (containerScene && [containerScene respondsToSelector:@selector(layerManager)]) {
                id layerManager = [containerScene layerManager];
                NSArray *layers = [layerManager layers];
                if ([layers count] > 0 && [container respondsToSelector:@selector(_createHostViewForLayer:)]) {
                    for (id layer in layers) {
                        UIView *hostView = [container _createHostViewForLayer:layer];
                        if (hostView) {
                            hostView.frame = container.frame;
                            [container addSubview:hostView];
                        }
                    }
                }
            }
            contentView = container;
        }
        if (!contentView) contentView = [MWSceneHelper createLayerHostView:bundleID];
        if (!contentView) {
            MW_LOG(@"错误：无法为 %@ 创建内容视图", bundleID);
            return;
        }

        contentView.frame = [UIScreen mainScreen].bounds;

        MWWindowView *windowView = [[MWWindowView alloc] initWithContentView:contentView
                                                                  identifier:bundleID
                                                                       scene:scene];
        // 标题：右侧悬浮小窗初始位置
        windowView.frame = CGRectMake([UIScreen mainScreen].bounds.size.width - 340, 90, 320, 460);

        Class sbAppCtrl = NSClassFromString(@"SBApplicationController");
        SBApplication *app = [[sbAppCtrl sharedInstance] applicationWithBundleIdentifier:bundleID];
        windowView.titleLabel.text = app.displayName ?: bundleID;

        UIView *targetView = (UIView *)hostWindow;
        if (hostWindow.rootViewController)
            targetView = hostWindow.rootViewController.view ?: (UIView *)hostWindow;
        [targetView addSubview:windowView];
        [MWPassthroughWindow addWindowedId:bundleID];
        [MWSceneHelper startKeepAliveForBundleID:bundleID];

        // 申请 RBSAssertion，防止内核级挂起（保活关键）
        @try {
            SBApplication *theApp = [[NSClassFromString(@"SBApplicationController") sharedInstance]
                                      applicationWithBundleIdentifier:bundleID];
            int pid = 0;
            if ([theApp respondsToSelector:@selector(pid)]) {
                NSInvocation *inv = [NSInvocation invocationWithMethodSignature:
                    [theApp methodSignatureForSelector:@selector(pid)]];
                [inv setSelector:@selector(pid)]; [inv setTarget:theApp]; [inv invoke];
                [inv getReturnValue:&pid];
            }
            if (pid <= 0 && [theApp respondsToSelector:@selector(processState)]) {
                id ps = [theApp processState];
                if (ps && [ps respondsToSelector:@selector(pid)]) {
                    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:
                        [ps methodSignatureForSelector:@selector(pid)]];
                    [inv setSelector:@selector(pid)]; [inv setTarget:ps]; [inv invoke];
                    [inv getReturnValue:&pid];
                }
            }
            if (pid > 0) {
                Class rt = NSClassFromString(@"RBSTarget");
                Class ra = NSClassFromString(@"RBSLegacyAttribute");
                Class rs = NSClassFromString(@"RBSAssertion");
                if (rt && ra && rs) {
                    RBSTarget *target = [rt targetWithPid:pid];
                    NSUInteger flags = BKSProcessAssertionPreventTaskSuspend |
                                       BKSProcessAssertionPreventTaskThrottleDown |
                                       BKSProcessAssertionWantsForegroundResourcePriority |
                                       BKSProcessAssertionPreventThrottleDownUI;
                    RBSLegacyAttribute *attr = [ra attributeWithReason:BKSProcessAssertionReasonBackgroundUI flags:flags];
                    RBSAssertion *assertion = [[rs alloc] initWithExplanation:@"MWFloat keeping app alive"
                                                                       target:target attributes:@[attr]];
                    NSError *error = nil;
                    if ([assertion acquireWithError:&error]) {
                        windowView.processAssertion = assertion;
                        if (!_activeAssertions) _activeAssertions = [NSMutableDictionary new];
                        _activeAssertions[bundleID] = assertion;
                        MW_LOG(@"RBSAssertion 已获取并保留 PID %d", pid);
                        mach_port_t task = MACH_PORT_NULL;
                        if (task_for_pid(mach_task_self(), pid, &task) == KERN_SUCCESS && task != MACH_PORT_NULL) {
                            task_resume(task);
                            mach_port_deallocate(mach_task_self(), task);
                        } else {
                            kill(pid, SIGCONT);
                        }
                    } else {
                        MW_LOG(@"RBSAssertion 失败: %@", error);
                    }
                }
            }
        } @catch (NSException *e) {
            MW_LOG(@"RBSAssertion 异常: %@", e);
        }

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
            [windowView updateLayers];
            [windowView layoutSubviews];
        });
        MW_LOG(@"悬浮窗创建成功: %@", bundleID);

        // 拖拉/窗口化完成后，立即返回桌面，让悬浮窗直接呈现在桌面上
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.25 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            mw_goHome();
            MW_LOG(@"窗口化完成后已返回桌面");
        });
    });
}

// ============================================================
// 默认组：iOS 15-18 确定存在的类，安全 hook
// ============================================================

%hook SpringBoard
- (void)applicationDidFinishLaunching:(id)application {
    %orig;
    MW_LOG(@"SpringBoard 启动，初始化 MWFloat");
    [MWThemeManager sharedInstance];

    MWPassthroughWindow *window = [[MWPassthroughWindow alloc] init];
    window.frame = [UIScreen mainScreen].bounds;
    window.backgroundColor = [UIColor clearColor];
    window.clipsToBounds = YES;

    if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        UIViewController *vc = [[UIViewController alloc] init];
        window.rootViewController = vc;
        MWPassthroughView *ptView = [[MWPassthroughView alloc] init];
        vc.view = ptView;
        vc.view.backgroundColor = [UIColor clearColor];
    }

    window.windowLevel = UIWindowLevelAlert - 1;
    [MWPassthroughWindow setSharedInstance:window];
    window.hidden = NO;

    // 附加右下角拖动手柄
    [[MWFloatGrabber sharedGrabber] attachToWindow:window];
    MW_LOG(@"宿主窗口 + 右下角手柄已就绪");

    // scene 在 didFinishLaunching 阶段可能尚未完全就绪，延迟重绑到 SpringBoard 主 scene
    // 这是"手柄被全屏 App 盖住"的关键修复：必须绑定正确 scene，windowLevel 才生效
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1.0 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if ([window ensureBoundToMainScene]) {
            MW_LOG(@"宿主窗口已重绑到 SpringBoard 主 scene");
        }
        // 手柄位置随正确 scene 的 bounds 重新布局，并确保 window 进入顶层渲染顺序
        [[MWFloatGrabber sharedGrabber] attachToWindow:window];
        [window makeKeyAndVisible];
    });
}
%end

// 保活核心：App scene 更新时强制 foreground=YES
%hook FBScene
- (void)updateSettings:(id)settings withTransitionContext:(id)ctx completion:(id)completion {
    MWBackgrounderManager *mgr = [MWBackgrounderManager sharedInstance];
    if ([mgr shouldKeepForeground:self]) {
        @try {
            id mutableSettings = [settings mutableCopy];
            if (mutableSettings && [mutableSettings respondsToSelector:@selector(setForeground:)]) {
                [mutableSettings setForeground:YES];
                %orig(mutableSettings, ctx, completion);
                return;
            }
        } @catch (NSException *e) {}
    }
    %orig;
}
%end

// 保活：压制 deactivationReasons
%hook UIMutableApplicationSceneSettings
- (void)setDeactivationReasons:(unsigned long long)reasons {
    if (reasons != 0) {
        MWBackgrounderManager *mgr = [MWBackgrounderManager sharedInstance];
        NSString *identifier = nil;
        for (NSString *name in @[@"_identifier", @"_sceneIdentifier", @"_bundleIdentifier"]) {
            identifier = MW_GetIvar(self, [name UTF8String]);
            if (identifier) break;
        }
        if (!identifier && [self respondsToSelector:@selector(identifier)])
            identifier = [(id)self identifier];
        if (identifier) {
            for (NSString *bid in mgr.foregroundBundleIDs) {
                if ([identifier containsString:bid]) { %orig(0); return; }
            }
            for (NSString *sid in mgr.foregroundSceneIDs) {
                if ([sid isEqualToString:identifier]) { %orig(0); return; }
            }
        }
    }
    %orig;
}
%end

// App 退出时清理状态
%hook SBApplication
- (void)_didExitWithContext:(id)ctx {
    MWBackgrounderManager *mgr = [MWBackgrounderManager sharedInstance];
    if ([self respondsToSelector:@selector(bundleIdentifier)]) {
        NSString *bid = [self bundleIdentifier];
        if (bid) {
            [mgr setForeground:bid enabled:NO];
            [MWPassthroughWindow removeWindowedId:bid];
            id assertion = _activeAssertions[bid];
            if (assertion && [assertion respondsToSelector:@selector(invalidate)])
                [assertion invalidate];
            [_activeAssertions removeObjectForKey:bid];
        }
    }
    %orig;
}
%end

// layer 变化时刷新悬浮窗内容
%hook FBSceneLayerManager
- (void)_setLayers:(id)layers {
    %orig;
    [MWPassthroughWindow notifyUpdateLayers];
}
%end

// ============================================================
// 可选组：iOS 26 专属 / 不确定是否存在的类，按需 %init
// 避免 iOS 17 上 hook 不存在的类导致 SpringBoard 崩溃
// ============================================================

%group OptionalHooks

%hook SBApplication
- (BOOL)isMedusaCapable {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:SCALE_MODE_PLIST];
    if (prefs && self.bundleIdentifier) {
        id val = prefs[self.bundleIdentifier];
        if (val) return [val boolValue];
    }
    return %orig;
}
%end

%hook _UISceneHostingActivationStateHostComponent
- (void)setForeground:(BOOL)fg {
    if (!fg) {
        MWBackgrounderManager *mgr = [MWBackgrounderManager sharedInstance];
        if ([mgr.foregroundBundleIDs count] > 0 || [mgr.foregroundSceneIDs count] > 0) {
            @try {
                id hostScene = [self respondsToSelector:@selector(hostScene)] ? [self hostScene] : nil;
                NSString *sceneId = nil;
                if (hostScene && [hostScene respondsToSelector:@selector(persistentIdentifier)])
                    sceneId = [hostScene performSelector:@selector(persistentIdentifier)];
                if (sceneId) {
                    for (NSString *bid in mgr.foregroundBundleIDs) {
                        if ([sceneId containsString:bid]) { %orig(YES); return; }
                    }
                    for (NSString *sid in mgr.foregroundSceneIDs) {
                        if ([sceneId containsString:sid]) { %orig(YES); return; }
                    }
                }
            } @catch (NSException *e) {}
        }
    }
    %orig;
}
%end

%end // OptionalHooks

%ctor {
    @autoreleasepool {
        _activeAssertions = [NSMutableDictionary new];
        [MWBackgrounderManager sharedInstance];
        MW_LOG(@"已加载 (iOS %@)", [[UIDevice currentDevice] systemVersion]);
        %init;
        // 类存在时才初始化可选 hook，保证 iOS 17 安全
        if (NSClassFromString(@"_UISceneHostingActivationStateHostComponent")) {
            %init(OptionalHooks);
        }
    }
}

//
//  AppSceneView.m
//  LiveContainer
//
//  Created by s s on 2025/5/17.
//
#import "AppSceneViewController.h"
#import "PiPManager.h"
#import "MWLog.h"
#import <objc/runtime.h>

// FIX (1.0.4, experiment B): find an app's EXISTING main scene instead of
// creating a fresh one. SeaDragon Split does this from SpringBoard
// (KonbanXV's route: FBSceneManager -> _workspace -> _allScenesByID),
// where the manager IS the system workspace. This app runs in its OWN
// process, so its FBSceneManager only knows its own scenes — the lookup
// will most likely return nil, and the MWLOG lines below prove it either
// way. Every step is nil-guarded and @try-wrapped; failure falls through
// to the old createScene path, never a crash.
static FBScene *MWExistingSceneForBundleID(NSString *bundleID) {
    if (!bundleID) return nil;
    NSString *fixedID = [NSString stringWithFormat:@"sceneID:%@-default", bundleID];
    Class fbSceneClass = NSClassFromString(@"FBScene");
    @try {
        Class managerClass = NSClassFromString(@"FBSceneManager");
        id manager = nil;
        if (managerClass && [managerClass respondsToSelector:@selector(sharedInstance)]) {
            manager = [managerClass sharedInstance];
        }
        if (!manager) {
            MWLog(@"ASVC", @"hostLookup %@ no manager", bundleID);
        } else {
            // S1: _workspace -> _allScenesByID (SpringBoard's layout)
            Ivar wsIvar = class_getInstanceVariable([manager class], "_workspace");
            id workspace = wsIvar ? object_getIvar(manager, wsIvar) : nil;
            if (workspace) {
                Ivar scIvar = class_getInstanceVariable(object_getClass(workspace), "_allScenesByID");
                id dict = scIvar ? object_getIvar(workspace, scIvar) : nil;
                if ([dict isKindOfClass:[NSDictionary class]]) {
                    BOOL matched = NO;
                    for (NSString *key in [(NSDictionary *)dict allKeys]) {
                        if (![key isKindOfClass:[NSString class]]) continue;
                        if ([key isEqualToString:fixedID] || [key rangeOfString:bundleID].location != NSNotFound) {
                            id scene = [(NSDictionary *)dict objectForKey:key];
                            if (scene && fbSceneClass && [scene isKindOfClass:fbSceneClass]) {
                                MWLog(@"ASVC", @"hostLookup %@ FOUND via S1 workspace sid=%@", bundleID, key);
                                return scene;
                            }
                        }
                    }
                    if (!matched) MWLog(@"ASVC", @"hostLookup %@ S1 workspace dict %lu keys, no match", bundleID, (unsigned long)[(NSDictionary *)dict count]);
                } else {
                    MWLog(@"ASVC", @"hostLookup %@ S1 no _allScenesByID dict", bundleID);
                }
            } else {
                MWLog(@"ASVC", @"hostLookup %@ S1 no _workspace", bundleID);
            }
            // S2: manager _scenesByID / _scenes dicts
            for (NSString *ivarName in @[@"_scenesByID", @"_scenes"]) {
                Ivar iv = class_getInstanceVariable([manager class], [ivarName UTF8String]);
                id dict = iv ? object_getIvar(manager, iv) : nil;
                if ([dict isKindOfClass:[NSDictionary class]]) {
                    BOOL matched = NO;
                    for (NSString *key in [(NSDictionary *)dict allKeys]) {
                        if (![key isKindOfClass:[NSString class]]) continue;
                        if ([key isEqualToString:fixedID] || [key rangeOfString:bundleID].location != NSNotFound) {
                            id scene = [(NSDictionary *)dict objectForKey:key];
                            if (scene && fbSceneClass && [scene isKindOfClass:fbSceneClass]) {
                                MWLog(@"ASVC", @"hostLookup %@ FOUND via S2 %@ sid=%@", bundleID, ivarName, key);
                                return scene;
                            }
                        }
                    }
                    if (!matched) MWLog(@"ASVC", @"hostLookup %@ S2 %@ dict %lu keys, no match", bundleID, ivarName, (unsigned long)[(NSDictionary *)dict count]);
                }
            }
            // S3: allScenes (via performSelector — no visible declaration)
            if ([manager respondsToSelector:@selector(allScenes)]) {
                NSUInteger n = 0;
                NSArray *allScenes = [manager performSelector:@selector(allScenes)];
                for (id scene in allScenes) {
                    n++;
                    if ([scene respondsToSelector:@selector(identifier)]) {
                        NSString *sid = [scene identifier];
                        if (sid && ([sid isEqualToString:fixedID] || [sid rangeOfString:bundleID].location != NSNotFound)) {
                            MWLog(@"ASVC", @"hostLookup %@ FOUND via S3 allScenes sid=%@", bundleID, sid);
                            return scene;
                        }
                    }
                }
                MWLog(@"ASVC", @"hostLookup %@ S3 allScenes %lu scenes, no match", bundleID, (unsigned long)n);
            } else {
                MWLog(@"ASVC", @"hostLookup %@ S3 no allScenes", bundleID);
            }
            // S4: SBSceneManager existingSceneHandleForSceneIdentity:
            Class sbMgr = NSClassFromString(@"SBSceneManager");
            if (sbMgr && [sbMgr respondsToSelector:@selector(existingSceneHandleForSceneIdentity:)]) {
                Class idProvider = NSClassFromString(@"SBSceneIdentityProvider");
                if (idProvider && [idProvider respondsToSelector:@selector(identityForIdentifier:)]) {
                    id identity = [idProvider identityForIdentifier:fixedID];
                    if (identity) {
                        // via performSelector — no visible declaration
                        id handle = [sbMgr performSelector:@selector(existingSceneHandleForSceneIdentity:) withObject:identity];
                        if (handle && [handle respondsToSelector:@selector(scene)]) {
                            id scene = [handle scene];
                            if (scene) {
                                MWLog(@"ASVC", @"hostLookup %@ FOUND via S4 existingSceneHandle", bundleID);
                                return scene;
                            }
                        }
                    }
                }
                MWLog(@"ASVC", @"hostLookup %@ S4 handle nil", bundleID);
            } else {
                MWLog(@"ASVC", @"hostLookup %@ S4 no SBSceneManager API", bundleID);
            }
        }
    } @catch (NSException *e) {
        MWLog(@"ASVC", @"hostLookup %@ exception %@ - fallback createScene", bundleID, e.reason);
    }
    MWLog(@"ASVC", @"hostLookup %@ NOT FOUND - fallback createScene", bundleID);
    return nil;
}

@implementation AppSceneViewController {
    int resizeDebounceToken;
    CGRect currentFrame;
    bool isNativeWindow;
    NSUUID* identifier;
    // FIX (1.0.4): YES when self.view is a layer host for the app's EXISTING
    // main scene (no presenter, no created scene — never destroy/kill it,
    // never push a frame to it).
    bool hostedExistingScene;
}

/*
 - (instancetype)initWithBundleID:(LSApplicationProxy *)app{
     self = [super initWithFrame:CGRectMake(0, 100, 400, 400)];

     self.navigationBar.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
     [self.navigationBar.standardAppearance configureWithTransparentBackground];
     self.navigationBar.standardAppearance.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5];
     self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose target:self action:@selector(closeWindow)];

     NSString *bundleID = app.bundleIdentifier;
     self.transitionContext = [UIApplicationSceneTransitionContext new];
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
         // At this point, the process is spawned and we're ready to create a scene to render in our app
         RBSProcessHandle* processHandle = [RBSProcessHandle handleForPredicate:predicate error:nil];
         [manager registerProcessForAuditToken:processHandle.auditToken];
         // NSString *identifier = [NSString stringWithFormat:@"sceneID:%@-%@", bundleID, @"default"];
         self.sceneID = [NSString stringWithFormat:@"sceneID:%@-%@", bundleID, @"default"];

         FBSMutableSceneDefinition *definition = [FBSMutableSceneDefinition definition];
         definition.identity = [FBSSceneIdentity identityForIdentifier:self.sceneID];
         definition.clientIdentity = [FBSSceneClientIdentity identityForProcessIdentity:identity];
         definition.specification = [UIApplicationSceneSpecification specification];
         FBSMutableSceneParameters *parameters = [FBSMutableSceneParameters parametersForSpecification:definition.specification];

         UIMutableApplicationSceneSettings *settings = [UIMutableApplicationSceneSettings new];
         settings.canShowAlerts = YES;
         settings.cornerRadiusConfiguration = [[BSCornerRadiusConfiguration alloc] initWithTopLeft:self.layer.cornerRadius bottomLeft:self.layer.cornerRadius bottomRight:self.layer.cornerRadius topRight:self.layer.cornerRadius];
         settings.displayConfiguration = UIScreen.mainScreen.displayConfiguration;
         settings.foreground = YES;
         settings.frame = self.bounds;
         settings.interfaceOrientation = UIInterfaceOrientationPortrait;
         //settings.interruptionPolicy = 2; // reconnect
         settings.level = 1;
         settings.peripheryInsets = UIEdgeInsetsMake(self.navigationBar.frame.size.height, 0, 0, 0);
         settings.persistenceIdentifier = NSUUID.UUID.UUIDString;
         settings.safeAreaInsetsPortrait = UIEdgeInsetsMake(self.navigationBar.frame.size.height, 0, 0, 0);
         //settings.statusBarDisabled = 1;
         //settings.previewMaximumSize =
         //settings.deviceOrientationEventsEnabled = YES;
         self.settings = settings;
         parameters.settings = settings;

         UIMutableApplicationSceneClientSettings *clientSettings = [UIMutableApplicationSceneClientSettings new];
         clientSettings.interfaceOrientation = UIInterfaceOrientationPortrait;
         clientSettings.statusBarStyle = 0;
         parameters.clientSettings = clientSettings;

         FBScene *scene = [[FBSceneManager sharedInstance] createSceneWithDefinition:definition initialParameters:parameters];

         self.navigationItem.title = app.localizedName;

         self.presenter = [scene.uiPresentationManager createPresenterWithIdentifier:self.sceneID];
         [self.presenter activate];
         [self insertSubview:self.presenter.presentationView atIndex:0];
     }];
     [transaction begin];
     return self;
 }
 */

- (instancetype)initWithApp:(LSApplicationProxy *)app frame:(CGRect)frame delegate:(id<AppSceneViewDelegate>)delegate {
    self = [super initWithNibName:nil bundle:nil];
    currentFrame = frame;
    self.delegate = delegate;
    isNativeWindow = NO;//[[[NSUserDefaults alloc] initWithSuiteName:[LCUtils appGroupID]] integerForKey:@"LCMultitaskMode" ] == 1;
    
    NSString *bundleID = app.bundleIdentifier;
    //self.transitionContext = [UIApplicationSceneTransitionContext new];
    RBSProcessIdentity* identity = [RBSProcessIdentity identityForEmbeddedApplicationIdentifier:bundleID];
    RBSProcessPredicate* predicate = [RBSProcessPredicate predicateMatchingIdentity:identity];
    FBProcessManager *manager = FBProcessManager.sharedInstance;
    
    // At this point, the process is spawned and we're ready to create a scene to render in our app
    RBSProcessHandle* processHandle = [PrivClass(RBSProcessHandle) handleForPredicate:predicate error:nil];
    self.pid = processHandle.pid;
    if(!self.isAppRunning) {
        MWLog(@"ASVC", @"init %@ ABORT pid=%d not running", bundleID, self.pid);
        return self;
    }
    // FIX (1.0.4, experiment B): if the target is already running, try to
    // host its EXISTING main scene (KonbanXV / SeaDragon Split v38 route)
    // instead of creating a fresh scene the client ignores — QQ stays blank
    // even cold-started, because it never attaches a window to a 2nd scene.
    // Most likely the lookup finds nothing from this app's own process
    // (see MWExistingSceneForBundleID); then we fall through to the old
    // createScene path unchanged.
    FBScene *existingScene = MWExistingSceneForBundleID(bundleID);
    if (existingScene) {
        @try {
            // via performSelector — 'identifier' is not on FBScene's visible interface
            self.sceneID = [existingScene respondsToSelector:@selector(identifier)] ? [existingScene performSelector:@selector(identifier)] : [NSString stringWithFormat:@"sceneID:%@-default", bundleID];
            Class layerHostClass = NSClassFromString(@"_UISceneLayerHostContainerView");
            _UISceneLayerHostContainerView *layerHostView = nil;
            if (layerHostClass && [layerHostClass instancesRespondToSelector:@selector(initWithScene:debugDescription:)]) {
                layerHostView = [[layerHostClass alloc] initWithScene:existingScene debugDescription:@"MultiWindow"];
            }
            if (!layerHostView && layerHostClass && [layerHostClass instancesRespondToSelector:@selector(initWithScene:)]) {
                // via performSelector — initWithScene: has no visible declaration
                layerHostView = [[layerHostClass alloc] performSelector:@selector(initWithScene:) withObject:existingScene];
            }
            if (layerHostView) {
                Class contextClass = NSClassFromString(@"UIScenePresentationContext");
                if (contextClass && [contextClass instancesRespondToSelector:@selector(_initWithDefaultValues)]) {
                    id context = [[contextClass alloc] _initWithDefaultValues];
                    if (context) [layerHostView _setPresentationContext:context];
                }
                hostedExistingScene = YES;
                self.view = layerHostView;
                self.view.frame = CGRectMake(0, 0, frame.size.width, frame.size.height);
                self.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
                // Read-only layer census for the log: does this scene have
                // anything to show at all?
                NSUInteger layerCount = 0;
                @try {
                    // via performSelector — neither selector is on FBScene's visible interface
                    id lm = [existingScene respondsToSelector:@selector(layerManager)] ? [existingScene performSelector:@selector(layerManager)] : nil;
                    NSArray *layers = (lm && [lm respondsToSelector:@selector(layers)]) ? [lm performSelector:@selector(layers)] : nil;
                    layerCount = [layers count];
                } @catch (NSException *e2) { (void)e2; }
                // Foreground only — NEVER touch the main scene's frame or
                // insets (it is the app's full-screen main scene).
                @try {
                    [existingScene updateSettingsWithBlock:^(UIMutableApplicationSceneSettings *settings) {
                        settings.foreground = YES;
                        // KVC — 'backgrounded' is not on UIMutableApplicationSceneSettings' visible interface
                        if ([settings respondsToSelector:@selector(setBackgrounded:)]) {
                            [settings setValue:@(NO) forKey:@"backgrounded"];
                        }
                    }];
                } @catch (NSException *e3) { (void)e3; }
                MWLog(@"ASVC", @"hostedExisting %@ sid=%@ layers=%lu view=%@", bundleID, self.sceneID, (unsigned long)layerCount, NSStringFromCGRect(self.view.frame));
                return self;
            }
            MWLog(@"ASVC", @"hostedExisting %@ layer host nil - fallback createScene", bundleID);
        } @catch (NSException *e) {
            MWLog(@"ASVC", @"hostedExisting %@ exception %@ - fallback createScene", bundleID, e.reason);
        }
    }
    [manager registerProcessForAuditToken:processHandle.auditToken];
    // NSString *identifier = [NSString stringWithFormat:@"sceneID:%@-%@", bundleID, @"default"];
    self.sceneID = [NSString stringWithFormat:@"sceneID:%@-%@", bundleID, @"default"];
    
    FBSMutableSceneDefinition *definition = [PrivClass(FBSMutableSceneDefinition) definition];
    definition.identity = [PrivClass(FBSSceneIdentity) identityForIdentifier:self.sceneID];
    definition.clientIdentity = [PrivClass(FBSSceneClientIdentity) identityForProcessIdentity:processHandle.identity];
    definition.specification = [UIApplicationSceneSpecification specification];
    FBSMutableSceneParameters *parameters = [PrivClass(FBSMutableSceneParameters) parametersForSpecification:definition.specification];
    
    UIUserInterfaceStyle hostStyle = UIApplication.sharedApplication.keyWindow.traitCollection.userInterfaceStyle;
    if (hostStyle == UIUserInterfaceStyleUnspecified) hostStyle = UITraitCollection.currentTraitCollection.userInterfaceStyle;

    UIMutableApplicationSceneSettings *settings = [UIMutableApplicationSceneSettings new];
    settings.canShowAlerts = YES;
    settings.userInterfaceStyle = hostStyle;
    settings.cornerRadiusConfiguration = [[PrivClass(BSCornerRadiusConfiguration) alloc] initWithTopLeft:self.view.layer.cornerRadius bottomLeft:self.view.layer.cornerRadius bottomRight:self.view.layer.cornerRadius topRight:self.view.layer.cornerRadius];
    settings.displayConfiguration = UIScreen.mainScreen.displayConfiguration;
    settings.foreground = YES;
    
    settings.deviceOrientation = UIDevice.currentDevice.orientation;
    settings.interfaceOrientation = UIApplication.sharedApplication.statusBarOrientation;
    if(UIInterfaceOrientationIsLandscape(settings.interfaceOrientation)) {
        settings.frame = CGRectMake(0, 0, frame.size.height, frame.size.width);
    } else {
        settings.frame = CGRectMake(0, 0, frame.size.width, frame.size.height);
    }
    //settings.interruptionPolicy = 2; // reconnect
    settings.level = 1;
    settings.persistenceIdentifier = NSUUID.UUID.UUIDString;
    if(isNativeWindow) {
        UIEdgeInsets defaultInsets = UIApplication.sharedApplication.keyWindow.safeAreaInsets;
        settings.peripheryInsets = defaultInsets;
        settings.safeAreaInsetsPortrait = defaultInsets;
    } else {
        // it seems some apps don't honor these settings so we don't cover the top of the app
        settings.peripheryInsets = UIEdgeInsetsMake(0, 0, 0, 0);
        settings.safeAreaInsetsPortrait = UIEdgeInsetsMake(0, 0, 0, 0);
    }
    
    
    settings.statusBarDisabled = !isNativeWindow;
    //settings.previewMaximumSize =
    //settings.deviceOrientationEventsEnabled = YES;
    // LOG (1.0.2): what frame did the scene actually get, and in which orientation?
    MWLog(@"ASVC", @"init %@ inFrame=%@ orient=%ld settings.frame=%@ pid=%d", bundleID, NSStringFromCGRect(frame), (long)settings.interfaceOrientation, NSStringFromCGRect(settings.frame), self.pid);
    self.settings = settings;
    parameters.settings = settings;
    
    UIMutableApplicationSceneClientSettings *clientSettings = [UIMutableApplicationSceneClientSettings new];
    clientSettings.interfaceOrientation = UIApplication.sharedApplication.statusBarOrientation;
    clientSettings.statusBarStyle = 0;
    parameters.clientSettings = clientSettings;
    
    FBScene *scene = [[PrivClass(FBSceneManager) sharedInstance] createSceneWithDefinition:definition initialParameters:parameters];
    
    self.presenter = [scene.uiPresentationManager createPresenterWithIdentifier:self.sceneID];
    [self.presenter modifyPresentationContext:^(UIMutableScenePresentationContext *context) {
        // Restore the adaptive value that was verified to render hosted scenes.
        // Forcing a fixed value here made every hosted app render black.
        context.appearanceStyle = (hostStyle == UIUserInterfaceStyleDark) ? 2 : 1;
    }];
    [self.presenter activate];

    self.view = self.presenter.presentationView;
    // FIX (1.0.1): the presenter view is born at the scene frame and nothing
    // ever resized it afterwards, so while the window animates open / is
    // dragged / is resized the view kept its birth size and the scene showed
    // only as a clipped strip (or nothing) inside the window. Pin it to the
    // intended content frame now and let it track the container.
    self.view.frame = CGRectMake(0, 0, frame.size.width, frame.size.height);
    self.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    // LOG (1.0.2): what frame does the presenter view end up with right after activate?
    MWLog(@"ASVC", @"activated %@ presenterView=%@ view=%@", bundleID, NSStringFromCGRect(self.presenter.presentationView.frame), NSStringFromCGRect(self.view.frame));
    return self;
}

// this method should not be called in native window mode
- (void)resizeWindowWithFrame:(CGRect)frame {
    // FIX (1.0.1): never push a zero/near-zero frame to the scene (it blanks
    // the hosted app), and keep the presenter view in lock-step with the
    // scene size immediately — the settings update below is debounced, but
    // the view was never resized at all, so a shrunk window kept showing a
    // stale-sized scene clipped to a strip.
    if (frame.size.width < 1 || frame.size.height < 1) {
        MWLog(@"ASVC", @"resize SKIP zero frame=%@", NSStringFromCGRect(frame));
        return;
    }
    // LOG (1.0.2): what size came in, and what is the presenter view now?
    MWLog(@"ASVC", @"resize in=%@ viewBefore=%@", NSStringFromCGRect(frame), NSStringFromCGRect(self.view.frame));
    self.view.frame = CGRectMake(0, 0, frame.size.width, frame.size.height);
    __block int currentDebounceToken = self->resizeDebounceToken + 1;
    self->resizeDebounceToken = currentDebounceToken;
    dispatch_time_t delay = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC));
    dispatch_after(delay, dispatch_get_main_queue(), ^{
        if(currentDebounceToken != self->resizeDebounceToken) {
            return;
        }
        self->currentFrame = frame;
        if (self->hostedExistingScene) {
            // FIX (1.0.4): a hosted EXISTING scene is the app's full-screen
            // main scene — never push a frame to it; only the view moves.
            MWLog(@"ASVC", @"resize hostedExisting skip push frame=%@", NSStringFromCGRect(frame));
            return;
        }
        // LOG (1.0.2): which frame is actually pushed to the scene settings?
        MWLog(@"ASVC", @"resize push frame=%@ orient=%ld", NSStringFromCGRect(frame), (long)self.view.window.windowScene.interfaceOrientation);
        [self.presenter.scene updateSettingsWithBlock:^(UIMutableApplicationSceneSettings *settings) {
            settings.deviceOrientation = UIDevice.currentDevice.orientation;
            settings.interfaceOrientation = self.view.window.windowScene.interfaceOrientation;
            if(UIInterfaceOrientationIsLandscape(settings.interfaceOrientation)) {
                CGRect frame2 = CGRectMake(frame.origin.x, frame.origin.y, frame.size.height, frame.size.width);
                settings.frame = frame2;
            } else {
                settings.frame = frame;
            }
        }];
    });
}

- (void)closeWindow {
    __weak typeof(self) weakSelf = self;
    NSString *key = [NSString stringWithFormat:@"AppSceneViewController:%p", self];
    [self.view.window.windowScene _unregisterSettingsDiffActionArrayForKey:key];
    if (hostedExistingScene) {
        // FIX (1.0.4): this is the app's own main scene — NEVER destroyScene,
        // NEVER kill the pid, there is no presenter to deactivate. Just drop
        // our layer host view and let the app keep running.
        (void)weakSelf;
        MWLog(@"ASVC", @"closeWindow hostedExisting %@ - scene left alive", self.sceneID);
        [self.delegate appDidExit];
        self.delegate = nil;
        return;
    }
    [[PrivClass(FBSceneManager) sharedInstance] destroyScene:key withTransitionContext:nil];
    if(self.presenter){
        [self.presenter deactivate];
        [self.presenter invalidate];
        self.presenter = nil;
    }
    if(self.isAppRunning) {
        // FIXME: need to check if there are no other scenes hosted by SpringBoard
        kill(_pid, SIGTERM);
        NSLog(@"sent sigterm");
        if(self.isAppRunning) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                kill(_pid, SIGKILL);
            });
        }
    }
    [self.delegate appDidExit];
    self.delegate = nil;
}

- (void)_performActionsForUIScene:(UIScene *)scene withUpdatedFBSScene:(id)fbsScene settingsDiff:(FBSSceneSettingsDiff *)diff fromSettings:(UIApplicationSceneSettings *)settings transitionContext:(id)context lifecycleActionType:(uint32_t)actionType {
    [self displayAppTerminatedTextIfNeeded];
    // FIX (1.0.4): a hosted EXISTING scene is the app's main scene — there
    // is no presenter.scene to push settings to; nothing to do here.
    if (hostedExistingScene) return;
    if(!diff) return;
    UIMutableApplicationSceneSettings *baseSettings = [diff settingsByApplyingToMutableCopyOfSettings:settings];
    
    UIApplicationSceneTransitionContext *newContext = [context copy];
    newContext.actions = nil;
    if(isNativeWindow) {
        // directly update the settings
        baseSettings.interruptionPolicy = 0;
        baseSettings.safeAreaInsetsPortrait = self.view.window.safeAreaInsets;
        baseSettings.peripheryInsets = self.view.window.safeAreaInsets;
        [self.presenter.scene updateSettings:baseSettings withTransitionContext:newContext completion:nil];
    } else {
        UIMutableApplicationSceneSettings *newSettings = [self.presenter.scene.settings mutableCopy];
        newSettings.userInterfaceStyle = baseSettings.userInterfaceStyle;
        newSettings.interfaceOrientation = baseSettings.interfaceOrientation;
        newSettings.deviceOrientation = baseSettings.deviceOrientation;
        newSettings.foreground = YES;
        if(UIInterfaceOrientationIsLandscape(baseSettings.interfaceOrientation)) {
            newSettings.frame = CGRectMake(0, 0, currentFrame.size.height, currentFrame.size.width);
        } else {
            newSettings.frame = CGRectMake(0, 0, currentFrame.size.width, currentFrame.size.height);
        }
        [self.presenter.scene updateSettings:newSettings withTransitionContext:newContext completion:nil];
    }
}

- (void)displayAppTerminatedTextIfNeeded {
    if(!self.isAppRunning) {
        if(!isNativeWindow) {
            UILabel *label = [[UILabel alloc] initWithFrame:self.view.bounds];
            label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            label.lineBreakMode = NSLineBreakByWordWrapping;
            label.numberOfLines = 0;
            label.text = @"This app has been terminated.";
            label.textAlignment = NSTextAlignmentCenter;
            [self.view.superview addSubview:label];
        }
    }
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    // LOG (1.0.2): what frame does the presenter view REALLY end up with on screen?
    MWLog(@"ASVC", @"didAppear %@ view=%@ superview=%@", self.sceneID, NSStringFromCGRect(self.view.frame), NSStringFromCGRect(self.view.superview.frame));
    // FIX (1.0.4): the scene may have been created at a wrong size and
    // nothing ever re-pushed it (layoutSync never fires — bounds never
    // change after a wrong creation). Push the intended frame again now
    // that the scene is connected and on screen. For a hosted EXISTING
    // scene this only re-sets the view frame (resize skips the push).
    MWLog(@"ASVC", @"repush after appear frame=%@", NSStringFromCGRect(self->currentFrame));
    [self resizeWindowWithFrame:self->currentFrame];
    [self.view.window.windowScene _registerSettingsDiffActionArray:@[self] forKey:[NSString stringWithFormat:@"AppSceneViewController:%p", self]];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self displayAppTerminatedTextIfNeeded];
    [self.view.window.windowScene _registerSettingsDiffActionArray:@[self] forKey:[NSString stringWithFormat:@"AppSceneViewController:%p", self]];
}

- (BOOL)isAppRunning {
    return _pid > 0 && kill(_pid, 0) == 0;
}

@end
 

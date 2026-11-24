//
//  FBSSceneSettings.m
//  
//
//  Created by Duy Tran on 29/6/25.
//

#import "Hooks.h"
#import "UIKitPrivate+MultitaskSupport.h"
#import "MWLog.h"

extern CGFloat UIHUDWindowLevel;

@implementation UIWindow(hook)
- (BOOL)_allowsOcclusionDetectionOverride {
    return NO;
}

- (BOOL)_extendsScreenSceneLifetime {
    return YES;
}

- (BOOL)_touchesInsideShouldHideCalloutBar {
    return NO;
}

- (BOOL)_transformLayerIncludesScreenRotation {
    return YES;
}

- (BOOL)_usesWindowServerHitTesting {
    return YES;
}

- (id)_layerForCoordinateSpaceConversion {
    return self.layer;
}

#if 0
- (UIWindowBindingDescription)hook__bindingDescription {
    UIWindowBindingDescription desc = [self hook__bindingDescription];
    desc.showsOnTop = YES;
    return desc;
}

// Fixup scaling
- (void)_configureRootLayer:(CALayer *)rootLayer sceneTransformLayer:(CALayer *)sceneTransformLayer transformLayer:(CALayer *)transformLayer {
    UIScreen *screen = [self screen];
    if(!screen) {
        screen = self.windowScene.screen; // Fallback to windowScene's screen if available
    }
    CGRect unjailedBounds = [screen _unjailedReferenceBounds]; // Private UIScreen method
    double screenScale = screen.scale;
    double screenRotation = [screen _rotation]; // Private UIScreen method
    
    // Calculate center of bounds
    double centerX = unjailedBounds.origin.x + unjailedBounds.size.width * 0.5;
    double centerY = unjailedBounds.origin.y + unjailedBounds.size.height * 0.5;
    
    CGPoint renderingCenter = [[screen displayConfiguration] renderingCenter];
    
    // Apply rotation and scale to the rootLayer
    CGAffineTransform rotationTransform = CGAffineTransformMakeRotation(-screenRotation);
    CGAffineTransform scaleTransform = CGAffineTransformScale(rotationTransform, screenScale, screenScale);
    CGAffineTransform currentRootLayerTransform = scaleTransform;
    rootLayer.position = renderingCenter;
    rootLayer.affineTransform = currentRootLayerTransform;
    rootLayer.bounds = unjailedBounds;
    
    sceneTransformLayer.affineTransform = CGAffineTransformIdentity;
    sceneTransformLayer.position = CGPointMake(centerX, centerY);
    sceneTransformLayer.bounds = unjailedBounds;
    
    transformLayer.affineTransform = CGAffineTransformIdentity;
    transformLayer.position = CGPointMake(centerX, centerY);
    transformLayer.bounds = unjailedBounds; // Re-set bounds after potential rotation
    transformLayer.masksToBounds = YES;
}
#endif
@end


@interface FBSWorkspaceScenesClient : NSObject
@end
static BOOL shouldAllowNextUpdate = NO;
@implementation FBSWorkspaceScenesClient(hook)
- (void)hook_sceneID:(id)sceneID updateWithSettingsDiff:(id)diff transitionContext:(id)context completion:(id)completion {
    if(!diff) {
        [self hook_sceneID:sceneID updateWithSettingsDiff:diff transitionContext:context completion:completion];
        return;
    }
    // query 6 for foreground state
    BSSettings *changes = [diff valueForKey:@"changes"];
    // query 3 for deactivation reasons
    BSSettings *otherChanges = [diff valueForKeyPath:@"otherSettingsDiff.changes"];
    if([changes boolForSetting:6] || (![changes.allSettings containsIndex:6] && [[otherChanges objectForSetting:3] intValue] == 0)) {
        NSLog(@"Allowing next update for diff %@", diff);
        [self hook_sceneID:sceneID updateWithSettingsDiff:diff transitionContext:context completion:completion];
    } else {
        // LOG (1.0.4): dropped updates used to be silent — log them so the
        // log shows whether a size re-push got swallowed by this gate.
        MWLog(@"HOOK", @"drop sceneID=%@ fg6=%@ deact3=%@", sceneID, [changes objectForSetting:6], [otherChanges objectForSetting:3]);
    }
}
@end

void swizzle(Class class, SEL originalAction, SEL swizzledAction) {
    if (!class) return;
    Method original = class_getInstanceMethod(class, originalAction);
    Method replacement = class_getInstanceMethod(class, swizzledAction);
    if (!original || !replacement) return;
    method_exchangeImplementations(original, replacement);
}

__attribute__((constructor))
static void hook_init() {
    //method_setImplementation(class_getInstanceMethod(NSClassFromString(@"UIKeyboardVisualModeManager"), @selector(windowingModeEnabled)), (IMP)returnTrue);
    //swizzle(UIWindow.class, @selector(_bindingDescription), @selector(hook__bindingDescription));
    // Required for hosted app scenes to receive foreground updates.
    // This is the original, verified-working configuration (kept in the theos
    // snapshot .modified-021652). Without it, hosted apps receive background
    // diffs when the host backgrounds and STOP RENDERING — the split window
    // turns white/blank and appears completely unresponsive.
    swizzle(FBSWorkspaceScenesClient.class, @selector(sceneID:updateWithSettingsDiff:transitionContext:completion:), @selector(hook_sceneID:updateWithSettingsDiff:transitionContext:completion:));
}

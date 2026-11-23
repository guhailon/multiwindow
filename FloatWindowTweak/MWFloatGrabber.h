#import "MWHeaders.h"

// 右下角常驻的悬浮手柄。用户从桌面打开任意 App 后，拖动手柄即可
// 把当前前台 App 变成右侧悬浮小窗（画中画模式）。
@interface MWFloatGrabber : UIView
+ (instancetype)sharedGrabber;
- (void)attachToWindow:(UIWindow *)window;
- (void)setEnabled:(BOOL)enabled;
@end

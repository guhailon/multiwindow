#import <UIKit/UIKit.h>

// 独立的浮窗拖拽控制器。
// hosted app 的 presentationView 由系统 window server 直接分发触摸，会吞掉
// 宿主视图层级里的手势（顶栏与右下手柄都点不动）。因此把手柄放进一个
// 独立的、windowLevel 更高的小窗口，只覆盖右下角一小块区域，触摸必定到达；
// 其余区域不覆盖，正常穿透给宿主界面和 hosted app。
@interface FloatDragController : NSObject
+ (instancetype)shared;
- (void)attachToView:(UIView *)target;
- (void)detachFromView:(UIView *)target;
- (void)syncFrame;
@end

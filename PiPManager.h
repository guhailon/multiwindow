//
//  PiPManager.h
//  LiveContainer
//
//  Created by s s on 2025/6/3.
//
@import Foundation;
@import AVKit;
@import UIKit;
#import "FoundationPrivate.h"

@interface PiPManager : NSObject<AVPictureInPictureControllerDelegate>
@property (class, nonatomic, readonly) PiPManager *shared;
@property (nonatomic, readonly) bool isPiP;
// 拖动缩放结束后自动进入 PiP 时置 YES：PiP 画面确认显示后再 suspend 回桌面
@property (nonatomic) BOOL shouldAutoSuspend;
- (BOOL)isPiPWithView:(UIView*)view;
- (void)stopPiP;
- (void)startPiPWithView:(UIView*)view contentView:(UIView*)contentView;

@end

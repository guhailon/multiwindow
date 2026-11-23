#import "FoundationPrivate.h"
#import "DecoratedFloatingView.h"
#import "AppSceneViewController.h"

@interface DecoratedAppSceneView : DecoratedFloatingView<AppSceneViewDelegate>
- (instancetype)initWithApp:(LSApplicationProxy *)app windowName:(NSString*)windowName;
- (void)refreshHostedSceneAfterResize;
@end

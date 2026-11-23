#import "DecoratedAppSceneView.h"
#import "LauncherViewController.h"
#import "ViewController.h"

@interface ViewController ()
@property(nonatomic) FBApplicationProcessLaunchTransaction *transaction;
@property(nonatomic) UIScenePresentationManager *presentationManager;
@end

@implementation ViewController

- (void)loadView {
    [super loadView];
    self.title = @"巨魔分屏";

    // Custom header, matching the reference: lots of empty space at the top,
    // a huge bold title at the lower-left and a blue circular settings button
    // at the upper-right. The transparent UINavigationBar is only used by
    // DecoratedFloatingView as a layout anchor and drag handle — none of the
    // standard nav-bar UI is visible.
    CGFloat headerHeight = 120;
    UINavigationBar *navigationBar = [[UINavigationBar alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, headerHeight)];
    navigationBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    navigationBar.items = @[[UINavigationItem new]];
    navigationBar.translucent = YES;
    [navigationBar setBackgroundImage:[UIImage new] forBarMetrics:UIBarMetricsDefault];
    navigationBar.shadowImage = [UIImage new];

    // Huge bold title, lower-left.
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, headerHeight - 54, self.view.bounds.size.width - 40, 48)];
    titleLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    titleLabel.text = @"巨魔分屏";
    titleLabel.font = [UIFont boldSystemFontOfSize:34];
    titleLabel.textColor = UIColor.labelColor;
    titleLabel.textAlignment = NSTextAlignmentLeft;
    titleLabel.adjustsFontSizeToFitWidth = YES;
    [navigationBar addSubview:titleLabel];

    // Blue circular settings button, upper-right.
    UIButton *settingsButton = [UIButton buttonWithType:UIButtonTypeSystem];
    settingsButton.frame = CGRectMake(self.view.bounds.size.width - 56, 56, 40, 40);
    settingsButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    UIImage *gear = [UIImage systemImageNamed:@"gearshape.fill"] ?: [UIImage systemImageNamed:@"gear"];
    [settingsButton setImage:gear forState:UIControlStateNormal];
    settingsButton.tintColor = UIColor.systemBlueColor;
    settingsButton.exclusiveTouch = YES;
    [settingsButton addTarget:self action:@selector(openSettingsMenu:) forControlEvents:UIControlEventTouchUpInside];
    [navigationBar addSubview:settingsButton];

    LauncherViewController *launcherVC = [LauncherViewController new];
    launcherVC.modalPresentationStyle = UIModalPresentationCurrentContext;
    [self addChildViewController:launcherVC];

    DecoratedFloatingView *launcherView = [[DecoratedFloatingView alloc] initWithFrame:self.view.bounds navigationBar:navigationBar];
    launcherView.center = self.view.center;
    // Match the title/header area to the list background so there is no white
    // band above the app cards. Only the launcher window is changed; split
    // screen windows keep their own default background.
    launcherView.backgroundColor = UIColor.systemGroupedBackgroundColor;
    launcherView.resizeHandle.hidden = YES; // only split-screen windows get resize controls
    [launcherView.contentView insertSubview:launcherVC.view atIndex:0];
    [self.view addSubview:launcherView];
    // The list lives inside contentView (whose height already excludes the
    // header). Size it to that container, not the whole floating view, or the
    // bottom rows get clipped.
    launcherVC.view.frame = launcherView.contentView.bounds;
    launcherVC.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [launcherVC didMoveToParentViewController:self];
}

#pragma mark - Settings / About

- (void)openSettingsMenu:(id)sender {
    UIAlertController *menu = [UIAlertController alertControllerWithTitle:@"设置"
                                                                 message:nil
                                                          preferredStyle:UIAlertControllerStyleActionSheet];
    UIAlertAction *about = [UIAlertAction actionWithTitle:@"关于"
                                                    style:UIAlertActionStyleDefault
                                                  handler:^(UIAlertAction * _Nonnull action) {
        [self showAbout];
    }];
    UIAlertAction *cancel = [UIAlertAction actionWithTitle:@"取消"
                                                     style:UIAlertActionStyleCancel
                                                   handler:nil];
    [menu addAction:about];
    [menu addAction:cancel];
    if ([sender isKindOfClass:UIBarButtonItem.class]) {
        menu.popoverPresentationController.barButtonItem = sender;
    } else if ([sender isKindOfClass:UIView.class]) {
        menu.popoverPresentationController.sourceView = sender;
        menu.popoverPresentationController.sourceRect = ((UIView *)sender).bounds;
    }
    [self presentViewController:menu animated:YES completion:nil];
}

- (void)showAbout {
    UIAlertController *about = [UIAlertController alertControllerWithTitle:@"关于"
                                                                 message:@"巨魔分屏\n作者: MrDu"
                                                          preferredStyle:UIAlertControllerStyleAlert];

    // Contact entries come from 0.txt. Links are opened on tap and are not
    // shown as plain text in the UI.
    __weak typeof(self) weakSelf = self;
    [about addAction:[UIAlertAction actionWithTitle:@"作者"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
        [weakSelf openLink:@"https://t.me/yicwl"];
    }]];
    [about addAction:[UIAlertAction actionWithTitle:@"作者频道"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
        [weakSelf openLink:@"https://t.me/ycys8"];
    }]];
    [about addAction:[UIAlertAction actionWithTitle:@"艺创科技"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
        [weakSelf openLink:@"http://w.ik6.cc/index2.php"];
    }]];
    [about addAction:[UIAlertAction actionWithTitle:@"QQ交流群"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
        [weakSelf joinQQGroup];
    }]];
    [about addAction:[UIAlertAction actionWithTitle:@"取消"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    [self presentViewController:about animated:YES completion:nil];
}

- (void)openLink:(NSString *)link {
    NSURL *url = [NSURL URLWithString:link];
    if (!url) return;
    if (@available(iOS 10.0, *)) {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    } else {
        [[UIApplication sharedApplication] openURL:url];
    }
}

- (void)joinQQGroup {
    NSString *groupUin = @"166623677";
    NSString *key = @"HBWejac1xZrc6E3gR0DDZ3fz+845tJu/CUw7FdTHqlhLzY8XxCaqBGIek8NLo/Ik";
    NSString *urlStr = [NSString stringWithFormat:@"mqqapi://card/show_pslcard?src_type=internal&version=1&uin=%@&authSig=%@&card_type=group&source=external&jump_from=webapi", groupUin, key];
    [self openLink:urlStr];
}

@end

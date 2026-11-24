// MWLogViewerViewController.m — in-app log viewer (1.0.3).
//
// Shows /var/mobile/Library/Logs/MultiWindow.log in a scrollable text view.
// Buttons: 刷新 (reload file), 分享 (share the log file), 清空 (truncate
// ONLY MultiWindow.log to empty). If the file is missing/empty it shows
// 暂无日志 and tells Lee to open an app once first (opening an app writes
// the log). Presented modally inside a UINavigationController.
#import "MWLogViewerViewController.h"

static NSString *const MWLogViewerLogPath = @"/var/mobile/Library/Logs/MultiWindow.log";
static NSString *const MWLogViewerEmptyText = @"暂无日志\n\n先打开一次「设置」（或任意应用）再回来查看，打开应用时会写日志。";

@interface MWLogViewerViewController ()
@property(nonatomic) UITextView *textView;
@property(nonatomic) UIBarButtonItem *shareItem;
@end

@implementation MWLogViewerViewController

- (void)loadView {
    [super loadView];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.title = @"查看日志";

    UIBarButtonItem *refreshItem = [[UIBarButtonItem alloc] initWithTitle:@"刷新"
                                                                    style:UIBarButtonItemStylePlain
                                                                   target:self
                                                                   action:@selector(refreshTapped:)];
    self.shareItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction
                                                                   target:self
                                                                   action:@selector(shareTapped:)];
    UIBarButtonItem *clearItem = [[UIBarButtonItem alloc] initWithTitle:@"清空"
                                                                  style:UIBarButtonItemStylePlain
                                                                 target:self
                                                                 action:@selector(clearTapped:)];
    self.navigationItem.leftBarButtonItems = @[refreshItem, self.shareItem, clearItem];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"关闭"
                                                                             style:UIBarButtonItemStyleDone
                                                                            target:self
                                                                            action:@selector(closeTapped:)];

    UITextView *textView = [[UITextView alloc] initWithFrame:self.view.bounds];
    textView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    textView.editable = NO;
    textView.selectable = YES;
    textView.alwaysBounceVertical = YES;
    textView.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    textView.textColor = UIColor.labelColor;
    textView.backgroundColor = UIColor.systemBackgroundColor;
    self.textView = textView;
    [self.view addSubview:textView];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self reloadLog];
}

#pragma mark - Log file

- (void)reloadLog {
    NSString *content = [NSString stringWithContentsOfFile:MWLogViewerLogPath
                                                    encoding:NSUTF8StringEncoding
                                                       error:nil];
    if (!content || content.length == 0) {
        self.textView.text = MWLogViewerEmptyText;
        return;
    }
    self.textView.text = content;
    // Show the newest lines at the bottom.
    NSRange bottom = NSMakeRange(content.length, 0);
    [self.textView scrollRangeToVisible:bottom];
}

#pragma mark - Actions

- (void)refreshTapped:(id)sender {
    [self reloadLog];
}

- (void)shareTapped:(id)sender {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *items = nil;
    if ([fm fileExistsAtPath:MWLogViewerLogPath]) {
        items = @[[NSURL fileURLWithPath:MWLogViewerLogPath]];
    } else {
        items = @[self.textView.text ?: @""];
    }
    UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:items
                                                                             applicationActivities:nil];
    if ([sender isKindOfClass:UIBarButtonItem.class]) {
        activity.popoverPresentationController.barButtonItem = sender;
    } else {
        activity.popoverPresentationController.sourceView = self.view;
        activity.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width / 2, 0, 1, 1);
    }
    [self presentViewController:activity animated:YES completion:nil];
}

- (void)clearTapped:(id)sender {
    // Truncate ONLY the MultiWindow log file to empty, nothing else.
    [@"" writeToFile:MWLogViewerLogPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [self reloadLog];
}

- (void)closeTapped:(id)sender {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

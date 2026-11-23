#import "DecoratedAppSceneView.h"
#import "LauncherViewController.h"
#import "ViewController.h"

// A single rounded "card" row, matching the reference UI: app icon on the
// left, name + bundle id stacked in the middle, version on the right.
@interface AppCardCell : UITableViewCell
@property(nonatomic) UIView *card;
@property(nonatomic) UIImageView *appIcon;
@property(nonatomic) UILabel *nameLabel;
@property(nonatomic) UILabel *bundleLabel;
@property(nonatomic) UILabel *versionLabel;
@end

@implementation AppCardCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
        self.contentView.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        UIView *card = [[UIView alloc] initWithFrame:CGRectZero];
        card.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
        card.layer.cornerRadius = 14;
        card.layer.masksToBounds = YES;
        [self.contentView addSubview:card];
        self.card = card;

        UIImageView *icon = [[UIImageView alloc] initWithFrame:CGRectZero];
        icon.layer.cornerRadius = 11;
        icon.layer.masksToBounds = YES;
        icon.contentMode = UIViewContentModeScaleAspectFit;
        [card addSubview:icon];
        self.appIcon = icon;

        UILabel *name = [[UILabel alloc] initWithFrame:CGRectZero];
        name.font = [UIFont boldSystemFontOfSize:17];
        name.textColor = UIColor.labelColor;
        [card addSubview:name];
        self.nameLabel = name;

        UILabel *bundle = [[UILabel alloc] initWithFrame:CGRectZero];
        bundle.font = [UIFont systemFontOfSize:12];
        bundle.textColor = UIColor.secondaryLabelColor;
        bundle.lineBreakMode = NSLineBreakByTruncatingTail;
        [card addSubview:bundle];
        self.bundleLabel = bundle;

        UILabel *version = [[UILabel alloc] initWithFrame:CGRectZero];
        version.font = [UIFont systemFontOfSize:13];
        version.textColor = UIColor.secondaryLabelColor;
        version.textAlignment = NSTextAlignmentRight;
        [card addSubview:version];
        self.versionLabel = version;
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.contentView.bounds.size.width;
    self.card.frame = CGRectMake(16, 4, w - 32, 68);

    self.appIcon.frame = CGRectMake(14, 12, 44, 44);

    CGFloat tx = 70;
    self.nameLabel.frame = CGRectMake(tx, 13, w - 32 - tx - 84, 24);
    self.bundleLabel.frame = CGRectMake(tx, 38, w - 32 - tx - 84, 18);
    self.versionLabel.frame = CGRectMake(w - 32 - 80 - 12, 22, 80, 20);
}
@end

// Table header that lays out its search bar from its ACTUAL width.
// UITableView resizes tableHeaderView to the table's real width (which is
// narrower than the screen inside the floating window), so a fixed frame
// computed from screen width overflows and clips the search bar's right
// rounded corner. Laying out in layoutSubviews always uses the real width.
@interface SearchHeaderView : UIView
@property(nonatomic) UISearchBar *searchBar;
@end

@implementation SearchHeaderView
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width;
    self.searchBar.frame = CGRectMake(16, 8, w - 32, 44);
}
@end

static BOOL NameHasChinese(NSString *s) {
    for (NSInteger i = 0; i < s.length; i++) {
        unichar c = [s characterAtIndex:i];
        if (c >= 0x4E00 && c <= 0x9FFF) return YES; // CJK unified ideographs
    }
    return NO;
}

@interface LauncherViewController () <UISearchBarDelegate>
@property(nonatomic) NSMutableArray<LSApplicationProxy *> *apps;
@property(nonatomic) NSArray<LSApplicationProxy *> *filteredApps;
@property(nonatomic) UISearchBar *searchBar;
@property(nonatomic) NSMutableDictionary<NSString *, NSString *> *displayNameCache;
@end

@implementation LauncherViewController
-(void)loadView {
    [super loadView];
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.title = @"巨魔分屏";
    self.displayNameCache = [NSMutableDictionary dictionary];

    self.apps = [[NSMutableArray alloc] init];
    NSArray *app_list = [LSApplicationWorkspace.defaultWorkspace allInstalledApplications];
    for (LSApplicationProxy *app in app_list) {
        if ([app.applicationType isEqual:@"User"] || ([app.applicationType isEqual:@"System"] && ![app.appTags containsObject:@"hidden"] && !app.launchProhibited && !app.placeholder && !app.removedSystemApp)) {
            [self.apps addObject:app];
        }
    }
    // Sort by the cheap localized name. Chinese display names are resolved
    // lazily per visible cell only (see displayNameForApp:) — doing a full
    // synchronous pre-pass here reads thousands of files on the main thread
    // and freezes the whole UI, which broke taps/menus after launch.
    [self.apps sortUsingDescriptors:@[
        [NSSortDescriptor sortDescriptorWithKey:@"localizedName" ascending:YES],
    ]];
    self.filteredApps = self.apps;

    // Card-style list: no separators, grouped background, a little breathing
    // room above the first card and below the last.
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.tableView.contentInset = UIEdgeInsetsMake(6, 0, 24, 0);
    // The vertical scroll indicator was overlapping the search bar's right
    // corner in the floating (narrower-than-screen) window. Hide it so the
    // rounded field is fully visible.
    self.tableView.showsVerticalScrollIndicator = NO;

    // Search bar below the big title. SearchHeaderView re-lays out the field
    // from its real bounds, so it always gets the same 16pt left/right margins
    // as the cards even though the table lives in a narrower floating window.
    SearchHeaderView *searchHeader = [[SearchHeaderView alloc] initWithFrame:CGRectMake(0, 0, self.tableView.bounds.size.width, 60)];
    searchHeader.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    UISearchBar *searchBar = [[UISearchBar alloc] initWithFrame:CGRectZero];
    searchBar.placeholder = @"搜索";
    searchBar.delegate = self;
    searchBar.autocorrectionType = UITextAutocorrectionTypeNo;
    searchBar.autocapitalizationType = UITextAutocapitalizationTypeNone;
    searchBar.returnKeyType = UIReturnKeyDone;
    // Remove the built-in hairline above (and below) the search bar.
    [searchBar setBackgroundImage:[[UIImage alloc] init] forBarPosition:UIBarPositionAny barMetrics:UIBarMetricsDefault];
    [searchHeader addSubview:searchBar];
    searchHeader.searchBar = searchBar;
    self.searchBar = searchBar;
    self.tableView.tableHeaderView = searchHeader;
}

#pragma mark - Display name

// Prefer a Chinese name. localizedName is often the English bundle name, so
// fall back to the app's Info.plist (CFBundleDisplayName / CFBundleName) and
// its zh-Hans localization. Results are cached per bundle id.
- (NSString *)displayNameForApp:(LSApplicationProxy *)app {
    NSString *bid = app.bundleIdentifier ?: @"";
    NSString *cached = self.displayNameCache[bid];
    if (cached) return cached;

    NSString *fallback = app.localizedName ?: bid;
    NSString *result = fallback;

    // If the localized name is already Chinese, avoid all file IO.
    if (NameHasChinese(fallback)) {
        self.displayNameCache[bid] = result;
        return result;
    }

    NSURL *bundleURL = nil;
    @try {
        bundleURL = [app valueForKey:@"bundleURL"]; // private but widely available
    } @catch (__unused NSException *e) {
        bundleURL = nil;
    }
    if ([bundleURL isKindOfClass:NSURL.class]) {
        NSString *bundlePath = bundleURL.path;
        NSMutableArray<NSString *> *candidates = [NSMutableArray array];

        // Localized strings first (zh-Hans / zh-Hant / zh).
        for (NSString *lproj in @[@"zh-Hans.lproj", @"zh-Hant.lproj", @"zh.lproj", @"zh_CN.lproj"]) {
            NSString *stringsPath = [bundlePath stringByAppendingPathComponent:
                                     [lproj stringByAppendingPathComponent:@"InfoPlist.strings"]];
            NSDictionary *strings = [NSDictionary dictionaryWithContentsOfFile:stringsPath];
            NSString *n = strings[@"CFBundleDisplayName"] ?: strings[@"CFBundleName"];
            if (n.length) [candidates addObject:n];
        }
        // Raw Info.plist values.
        NSString *infoPath = [bundlePath stringByAppendingPathComponent:@"Info.plist"];
        NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:infoPath];
        NSString *dn = info[@"CFBundleDisplayName"];
        NSString *bn = info[@"CFBundleName"];
        if (dn.length) [candidates addObject:dn];
        if (bn.length) [candidates addObject:bn];

        for (NSString *candidate in candidates) {
            if (NameHasChinese(candidate)) { result = candidate; break; }
        }
    }

    self.displayNameCache[bid] = result;
    return result;
}

#pragma mark - Search

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    if (searchText.length == 0) {
        self.filteredApps = self.apps;
    } else {
        NSMutableArray *result = [NSMutableArray array];
        for (LSApplicationProxy *app in self.apps) {
            NSString *name = [self displayNameForApp:app];
            NSString *bundle = app.bundleIdentifier ?: @"";
            if ([name localizedCaseInsensitiveContainsString:searchText] ||
                [bundle localizedCaseInsensitiveContainsString:searchText]) {
                [result addObject:app];
            }
        }
        self.filteredApps = result;
    }
    [self.tableView reloadData];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
}

#pragma mark - Table data

-(CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 76;
}

-(UITableViewCell *)tableView:(nonnull UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    AppCardCell *cell = [tableView dequeueReusableCellWithIdentifier:@"CardCell"];
    if (cell == nil) {
        cell = [[AppCardCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"CardCell"];
    }

    LSApplicationProxy *app = self.filteredApps[indexPath.row];
    cell.nameLabel.text = [self displayNameForApp:app];
    cell.bundleLabel.text = app.bundleIdentifier;
    NSString *ver = [app valueForKey:@"shortVersionString"];
    cell.versionLabel.text = ver.length ? [@"v" stringByAppendingString:ver] : @"";
    cell.appIcon.image = [UIImage _applicationIconImageForBundleIdentifier:app.bundleIdentifier format:0 scale:UIScreen.mainScreen.scale];
    return cell;
}

-(void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:NO];
    [self.searchBar resignFirstResponder];
    LSApplicationProxy *app = self.filteredApps[indexPath.row];
    DecoratedAppSceneView *view = [[DecoratedAppSceneView alloc] initWithApp:app windowName:[self displayNameForApp:app]];

    // 原行为：从单元格展开到全屏分屏
    CGRect origFrame = view.frame;
    CGRect cellFrame = view.frame;
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
    cellFrame.origin = [cell.superview convertPoint:cell.frame.origin toView:self.navigationController.parentViewController.view];
    cellFrame.size = cell.frame.size;

    view.alpha = 0;
    view.frame = cellFrame;
    view.backgroundColor = [UIColor systemBackgroundColor];
    [self.parentViewController.view addSubview:view];
    [UIView animateWithDuration:0.4
                     animations:^{
        view.alpha = 1;
        view.frame = origFrame;
    } completion:nil];
}

-(NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

-(NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.filteredApps.count;
}
@end

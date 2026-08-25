// Helion — original iOS host for a Ryujinx engine fork.
#import <UIKit/UIKit.h>
#import <MetalKit/MetalKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <dlfcn.h>
#import <pthread.h>
#import <os/log.h>

static UIColor *HVoid(void)   { return [UIColor colorWithRed:0.03 green:0.03 blue:0.045 alpha:1]; }
static UIColor *HGold(void)   { return [UIColor colorWithRed:0.93 green:0.74 blue:0.38 alpha:1]; }
static UIColor *HEmber(void)  { return [UIColor colorWithRed:0.95 green:0.42 blue:0.22 alpha:1]; }
static UIColor *HCard(void)   { return [UIColor colorWithRed:0.09 green:0.09 blue:0.13 alpha:1]; }
static UIColor *HMute(void)   { return [UIColor colorWithWhite:0.55 alpha:1]; }

typedef void (*HelionInit)(void);
typedef void (*HelionSetWin)(void *);
typedef int  (*HelionMain)(int, char **);
typedef void (*HelionSetSize)(int, int);

static void *GLib;
static HelionInit GInit;
static HelionSetWin GSetWin;
static HelionMain GMain;
static HelionSetSize GSetSize;

static NSString *HelionRoot(void) {
    NSString *d = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject
                   stringByAppendingPathComponent:@"Helion"];
    [[NSFileManager defaultManager] createDirectoryAtPath:[d stringByAppendingPathComponent:@"games"]
                              withIntermediateDirectories:YES attributes:nil error:nil];
    return d;
}

static BOOL HelionLoadEngine(NSString **err) {
    if (GLib) return YES;
    NSString *fw = [[NSBundle mainBundle].privateFrameworksPath stringByAppendingPathComponent:@"Ryujinx.Headless.SDL2.dylib"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:fw])
        fw = [[NSBundle mainBundle].bundlePath stringByAppendingPathComponent:@"Frameworks/Ryujinx.Headless.SDL2.dylib"];
    GLib = dlopen(fw.fileSystemRepresentation, RTLD_NOW);
    if (!GLib) { *err = [NSString stringWithUTF8String:dlerror() ?: "dlopen"]; return NO; }
    GInit = dlsym(GLib, "initialize");
    GSetWin = dlsym(GLib, "set_native_window");
    GMain = dlsym(GLib, "main_ryujinx_sdl");
    GSetSize = dlsym(GLib, "set_view_size");
    if (!GMain) { *err = @"engine entry missing"; return NO; }
    if (GInit) GInit();
    return YES;
}

@interface HelionMark : UIView
@end
@implementation HelionMark
- (instancetype)initWithFrame:(CGRect)f {
    self = [super initWithFrame:f];
    self.backgroundColor = UIColor.clearColor;
    self.opaque = NO;
    return self;
}
- (void)drawRect:(CGRect)r {
    CGContextRef c = UIGraphicsGetCurrentContext();
    CGFloat w = r.size.width, h = r.size.height, cx = w/2, cy = h/2, rad = MIN(w,h)*0.38;
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGFloat loc[] = {0, 1};
    CGFloat cols[] = {0.98, 0.78, 0.32, 1,  0.85, 0.28, 0.12, 1};
    CGGradientRef g = CGGradientCreateWithColorComponents(cs, cols, loc, 2);
    CGContextDrawRadialGradient(c, g, CGPointMake(cx, cy), 0, CGPointMake(cx, cy), rad, 0);
    CGGradientRelease(g); CGColorSpaceRelease(cs);
    CGContextSetStrokeColorWithColor(c, [UIColor colorWithWhite:1 alpha:0.85].CGColor);
    CGContextSetLineWidth(c, 2.2);
    for (int i = 0; i < 8; i++) {
        CGFloat a = (CGFloat)i * M_PI / 4.0;
        CGContextMoveToPoint(c, cx + cos(a)*rad*0.55, cy + sin(a)*rad*0.55);
        CGContextAddLineToPoint(c, cx + cos(a)*rad*1.18, cy + sin(a)*rad*1.18);
    }
    CGContextStrokePath(c);
    CGContextSetFillColorWithColor(c, UIColor.whiteColor.CGColor);
    CGContextFillEllipseInRect(c, CGRectMake(cx-rad*0.18, cy-rad*0.18, rad*0.36, rad*0.36));
}
@end

@interface HelionPlay : UIViewController
- (instancetype)initWithPath:(NSString *)path;
@end
@implementation HelionPlay {
    NSString *_path;
    CAMetalLayer *_ml;
}
- (instancetype)initWithPath:(NSString *)path { self = [super init]; _path = [path copy]; return self; }
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Stop" style:UIBarButtonItemStylePlain target:self action:@selector(stop)];
    _ml = [CAMetalLayer layer];
    _ml.frame = self.view.bounds;
    _ml.contentsScale = UIScreen.mainScreen.scale;
    _ml.pixelFormat = MTLPixelFormatBGRA8Unorm;
    [self.view.layer addSublayer:_ml];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    _ml.frame = self.view.bounds;
    if (GSetSize) GSetSize((int)_ml.bounds.size.width, (int)_ml.bounds.size.height);
}
- (void)viewDidAppear:(BOOL)a {
    [super viewDidAppear:a];
    if (GSetWin) GSetWin((__bridge void *)_ml);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{ [self boot]; });
}
- (void)boot {
    NSString *root = HelionRoot();
    NSMutableArray<NSString *> *a = [@[
        @"Helion",
        @"--root-data-dir", root,
        @"--graphics-backend", @"Vulkan",
        @"--fullscreen", @"true",
        _path
    ] mutableCopy];
    int argc = (int)a.count;
    char **argv = calloc((size_t)argc + 1, sizeof(char *));
    for (int i = 0; i < argc; i++) argv[i] = strdup(a[i].UTF8String);
    int rc = GMain ? GMain(argc, argv) : -1;
    for (int i = 0; i < argc; i++) free(argv[i]);
    free(argv);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (rc != 0) {
            UIAlertController *al = [UIAlertController alertControllerWithTitle:@"Engine"
                message:[NSString stringWithFormat:@"exit %d — enable JIT (StikDebug) and add keys if needed.", rc]
                preferredStyle:UIAlertControllerStyleAlert];
            [al addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:al animated:YES completion:nil];
        }
    });
}
- (void)stop { [self.navigationController popViewControllerAnimated:YES]; }
@end

@interface HelionHome : UIViewController <UIDocumentPickerDelegate>
@end
@implementation HelionHome {
    UIStackView *_list;
    UILabel *_jit;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = HVoid();
    self.navigationController.navigationBar.hidden = YES;

    HelionMark *mark = [[HelionMark alloc] initWithFrame:CGRectZero];
    mark.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:mark];

    UILabel *t = [UILabel new];
    t.text = @"HELION";
    t.font = [UIFont systemFontOfSize:42 weight:UIFontWeightBlack];
    t.textColor = UIColor.whiteColor;
    t.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:t];

    UILabel *s = [UILabel new];
    s.text = @"Ryujinx. Rebuilt for the palm.";
    s.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    s.textColor = HGold();
    s.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:s];

    _jit = [UILabel new];
    _jit.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    _jit.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_jit];

    UIButton *add = [UIButton buttonWithType:UIButtonTypeSystem];
    [add setTitle:@"  Add file  " forState:UIControlStateNormal];
    add.backgroundColor = HGold();
    [add setTitleColor:HVoid() forState:UIControlStateNormal];
    add.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightBold];
    add.layer.cornerRadius = 16;
    [add addTarget:self action:@selector(add) forControlEvents:UIControlEventTouchUpInside];
    add.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:add];

    UIScrollView *sc = [UIScrollView new];
    sc.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:sc];
    _list = [UIStackView new];
    _list.axis = UILayoutConstraintAxisVertical;
    _list.spacing = 12;
    _list.translatesAutoresizingMaskIntoConstraints = NO;
    [sc addSubview:_list];

    [NSLayoutConstraint activateConstraints:@[
        [mark.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:18],
        [mark.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:22],
        [mark.widthAnchor constraintEqualToConstant:72],
        [mark.heightAnchor constraintEqualToConstant:72],
        [t.centerYAnchor constraintEqualToAnchor:mark.centerYAnchor constant:-10],
        [t.leadingAnchor constraintEqualToAnchor:mark.trailingAnchor constant:14],
        [s.topAnchor constraintEqualToAnchor:t.bottomAnchor constant:2],
        [s.leadingAnchor constraintEqualToAnchor:t.leadingAnchor],
        [_jit.topAnchor constraintEqualToAnchor:mark.bottomAnchor constant:18],
        [_jit.leadingAnchor constraintEqualToAnchor:mark.leadingAnchor],
        [add.topAnchor constraintEqualToAnchor:_jit.bottomAnchor constant:14],
        [add.leadingAnchor constraintEqualToAnchor:mark.leadingAnchor],
        [add.heightAnchor constraintEqualToConstant:46],
        [sc.topAnchor constraintEqualToAnchor:add.bottomAnchor constant:20],
        [sc.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [sc.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [sc.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
        [_list.topAnchor constraintEqualToAnchor:sc.topAnchor],
        [_list.leadingAnchor constraintEqualToAnchor:sc.leadingAnchor],
        [_list.trailingAnchor constraintEqualToAnchor:sc.trailingAnchor],
        [_list.bottomAnchor constraintEqualToAnchor:sc.bottomAnchor],
        [_list.widthAnchor constraintEqualToAnchor:sc.widthAnchor]
    ]];
    [self reload];
}
- (void)viewWillAppear:(BOOL)a { [super viewWillAppear:a]; [self reload]; }
- (void)reload {
    NSString *err = nil;
    BOOL ok = HelionLoadEngine(&err);
    _jit.text = ok ? @"Engine  loaded  ·  StikDebug JIT first" : [NSString stringWithFormat:@"Engine  %@", err];
    _jit.textColor = ok ? HGold() : HEmber();
    for (UIView *v in _list.arrangedSubviews) [_list removeArrangedSubview:v], [v removeFromSuperview];
    NSString *g = [HelionRoot() stringByAppendingPathComponent:@"games"];
    NSArray *all = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:g error:nil] ?: @[];
    if (!all.count) {
        UILabel *e = [UILabel new];
        e.text = @"Bring your own dumps from hardware you own.";
        e.textColor = HMute();
        e.font = [UIFont systemFontOfSize:14];
        e.numberOfLines = 0;
        [_list addArrangedSubview:e];
    }
    for (NSString *n in all) {
        NSString *e = n.pathExtension.lowercaseString;
        if (![@[@"nsp", @"xci", @"nro", @"nso"] containsObject:e]) continue;
        [_list addArrangedSubview:[self row:[g stringByAppendingPathComponent:n]]];
    }
}
- (UIView *)row:(NSString *)path {
    UIView *v = [UIView new];
    v.backgroundColor = HCard();
    v.layer.cornerRadius = 18;
    v.layer.borderWidth = 0.5;
    v.layer.borderColor = [HGold() colorWithAlphaComponent:0.25].CGColor;
    UILabel *t = [UILabel new];
    t.text = path.lastPathComponent;
    t.textColor = UIColor.whiteColor;
    t.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    t.translatesAutoresizingMaskIntoConstraints = NO;
    [v addSubview:t];
    UIButton *go = [UIButton buttonWithType:UIButtonTypeSystem];
    [go setTitle:@"Start" forState:UIControlStateNormal];
    go.backgroundColor = HEmber();
    [go setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    go.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
    go.layer.cornerRadius = 12;
    go.accessibilityValue = path;
    [go addTarget:self action:@selector(start:) forControlEvents:UIControlEventTouchUpInside];
    go.translatesAutoresizingMaskIntoConstraints = NO;
    [v addSubview:go];
    [NSLayoutConstraint activateConstraints:@[
        [v.heightAnchor constraintEqualToConstant:68],
        [t.leadingAnchor constraintEqualToAnchor:v.leadingAnchor constant:16],
        [t.centerYAnchor constraintEqualToAnchor:v.centerYAnchor],
        [t.trailingAnchor constraintLessThanOrEqualToAnchor:go.leadingAnchor constant:-8],
        [go.trailingAnchor constraintEqualToAnchor:v.trailingAnchor constant:-12],
        [go.centerYAnchor constraintEqualToAnchor:v.centerYAnchor],
        [go.widthAnchor constraintEqualToConstant:88],
        [go.heightAnchor constraintEqualToConstant:38]
    ]];
    return v;
}
- (void)add {
    UIDocumentPickerViewController *p = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeData, UTTypeItem]];
    p.delegate = self;
    p.allowsMultipleSelection = YES;
    [self presentViewController:p animated:YES completion:nil];
}
- (void)documentPicker:(UIDocumentPickerViewController *)c didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSString *g = [HelionRoot() stringByAppendingPathComponent:@"games"];
    for (NSURL *u in urls) {
        BOOL acc = [u startAccessingSecurityScopedResource];
        NSString *dest = [g stringByAppendingPathComponent:u.lastPathComponent];
        [[NSFileManager defaultManager] removeItemAtPath:dest error:nil];
        [[NSFileManager defaultManager] copyItemAtURL:u toURL:[NSURL fileURLWithPath:dest] error:nil];
        if (acc) [u stopAccessingSecurityScopedResource];
    }
    [self reload];
}
- (void)start:(UIButton *)b {
    HelionPlay *p = [[HelionPlay alloc] initWithPath:b.accessibilityValue];
    [self.navigationController pushViewController:p animated:YES];
}
@end

@interface HelionAppDelegate : UIResponder <UIApplicationDelegate>
@end
@implementation HelionAppDelegate
- (BOOL)application:(UIApplication *)a didFinishLaunchingWithOptions:(NSDictionary *)o { return YES; }
@end
@interface HelionSceneDelegate : UIResponder <UIWindowSceneDelegate>
@property (nonatomic, strong) UIWindow *window;
@end
@implementation HelionSceneDelegate
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)opts {
    if (![scene isKindOfClass:[UIWindowScene class]]) return;
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:[HelionHome new]];
    nav.navigationBar.barStyle = UIBarStyleBlack;
    nav.navigationBar.tintColor = HGold();
    self.window.rootViewController = nav;
    [self.window makeKeyAndVisible];
}
@end
int main(int argc, char *argv[]) {
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass([HelionAppDelegate class])); }
}

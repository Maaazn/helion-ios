// Helion — original iOS Switch emulator host. NCE + Metal.
// Not MeloNX. Not Nintendo. User-supplied dumps only.
#import <UIKit/UIKit.h>
#import <MetalKit/MetalKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <GameController/GameController.h>
#import "nce.h"

static UIColor *HNavy(void)  { return [UIColor colorWithRed:0.04 green:0.05 blue:0.09 alpha:1]; }
static UIColor *HCard(void)  { return [UIColor colorWithRed:0.09 green:0.11 blue:0.17 alpha:1]; }
static UIColor *HCopper(void){ return [UIColor colorWithRed:0.93 green:0.68 blue:0.48 alpha:1]; }
static UIColor *HIce(void)   { return [UIColor colorWithRed:0.32 green:0.86 blue:0.88 alpha:1]; }
static UIColor *HMuted(void) { return [UIColor colorWithWhite:0.55 alpha:1]; }

#pragma mark - Store

@interface HelionStore : NSObject
+ (NSString *)root;
+ (NSString *)keysPath;
+ (BOOL)hasKeys;
+ (NSArray<NSString *> *)games; // paths
+ (BOOL)importURL:(NSURL *)url error:(NSError **)error;
@end
@implementation HelionStore
+ (NSString *)root {
    NSString *d = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject
                   stringByAppendingPathComponent:@"Helion"];
    [[NSFileManager defaultManager] createDirectoryAtPath:d withIntermediateDirectories:YES attributes:nil error:nil];
    [[NSFileManager defaultManager] createDirectoryAtPath:[d stringByAppendingPathComponent:@"games"] withIntermediateDirectories:YES attributes:nil error:nil];
    return d;
}
+ (NSString *)keysPath { return [[self root] stringByAppendingPathComponent:@"prod.keys"]; }
+ (BOOL)hasKeys {
    NSNumber *n = [[NSFileManager defaultManager] attributesOfItemAtPath:[self keysPath] error:nil][NSFileSize];
    return n.unsignedLongLongValue > 32;
}
+ (NSArray<NSString *> *)games {
    NSString *g = [[self root] stringByAppendingPathComponent:@"games"];
    NSArray *all = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:g error:nil] ?: @[];
    NSMutableArray *o = [NSMutableArray array];
    for (NSString *n in all) {
        NSString *e = n.pathExtension.lowercaseString;
        if ([e isEqual:@"nro"] || [e isEqual:@"nsp"] || [e isEqual:@"xci"] || [e isEqual:@"nso"])
            [o addObject:[g stringByAppendingPathComponent:n]];
    }
    return o;
}
+ (BOOL)importURL:(NSURL *)url error:(NSError **)error {
    BOOL acc = [url startAccessingSecurityScopedResource];
    NSString *name = url.lastPathComponent;
    NSString *ext = name.pathExtension.lowercaseString;
    NSString *dest;
    if ([ext isEqual:@"keys"] || [name.lowercaseString containsString:@"prod.keys"] || [name isEqualToString:@"prod.keys"])
        dest = [self keysPath];
    else
        dest = [[[self root] stringByAppendingPathComponent:@"games"] stringByAppendingPathComponent:name];
    [[NSFileManager defaultManager] removeItemAtPath:dest error:nil];
    BOOL ok = [[NSFileManager defaultManager] copyItemAtURL:url toURL:[NSURL fileURLWithPath:dest] error:error];
    if (acc) [url stopAccessingSecurityScopedResource];
    return ok;
}
@end

#pragma mark - Screen

@interface HelionMetal : MTKView
@property (nonatomic) HelionNCE *nce;
@end
@implementation HelionMetal {
    id<MTLCommandQueue> _q;
    id<MTLTexture> _tex;
}
- (instancetype)initWithNCE:(HelionNCE *)nce {
    id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
    self = [super initWithFrame:CGRectZero device:dev];
    self.nce = nce;
    self.framebufferOnly = NO;
    self.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
    self.preferredFramesPerSecond = 120;
    _q = [dev newCommandQueue];
    MTLTextureDescriptor *d = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                                                 width:HELION_FB_W height:HELION_FB_H mipmapped:NO];
    d.usage = MTLTextureUsageShaderRead | MTLTextureUsageRenderTarget;
    _tex = [dev newTextureWithDescriptor:d];
    self.drawableSize = CGSizeMake(HELION_FB_W, HELION_FB_H);
    self.enableSetNeedsDisplay = NO;
    self.paused = NO;
    self.layer.cornerRadius = 16;
    self.clipsToBounds = YES;
    return self;
}
- (void)drawRect:(CGRect)r {
    [super drawRect:r];
    uint32_t *fb = helion_nce_fb(self.nce);
    if (!fb || !_tex) return;
    MTLRegion reg = MTLRegionMake2D(0, 0, HELION_FB_W, HELION_FB_H);
    [_tex replaceRegion:reg mipmapLevel:0 withBytes:fb bytesPerRow:HELION_FB_W * 4];
    id<MTLCommandBuffer> cb = [_q commandBuffer];
    MTLRenderPassDescriptor *p = self.currentRenderPassDescriptor;
    if (!p) return;
    p.colorAttachments[0].loadAction = MTLLoadActionClear;
    p.colorAttachments[0].clearColor = MTLClearColorMake(0.02, 0.03, 0.05, 1);
    id<MTLRenderCommandEncoder> e = [cb renderCommandEncoderWithDescriptor:p];
    /* blit via encoder isn't blit — use blit encoder */
    [e endEncoding];
    id<MTLBlitCommandEncoder> b = [cb blitCommandEncoder];
    id<MTLTexture> dst = self.currentDrawable.texture;
    if (dst) {
        MTLOrigin o = {0,0,0};
        NSUInteger w = MIN((NSUInteger)HELION_FB_W, dst.width);
        NSUInteger h = MIN((NSUInteger)HELION_FB_H, dst.height);
        [b copyFromTexture:_tex sourceSlice:0 sourceLevel:0 sourceOrigin:o sourceSize:MTLSizeMake(w, h, 1)
                 toTexture:dst destinationSlice:0 destinationLevel:0 destinationOrigin:o];
    }
    [b endEncoding];
    if (self.currentDrawable) [cb presentDrawable:self.currentDrawable];
    [cb commit];
}
@end

#pragma mark - Session

@interface HelionSession : UIViewController
- (instancetype)initWithPath:(NSString *)path probe:(BOOL)probe;
@end
@implementation HelionSession {
    NSString *_path; BOOL _probe;
    HelionNCE *_nce; HelionMetal *_metal;
    UITextView *_log; NSTimer *_t;
}
- (instancetype)initWithPath:(NSString *)path probe:(BOOL)probe {
    self = [super init]; _path = [path copy]; _probe = probe; return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = HNavy();
    self.title = _probe ? @"NCE Probe" : _path.lastPathComponent;
    self.navigationItem.hidesBackButton = YES;
    _nce = helion_nce_create();
    _metal = [[HelionMetal alloc] initWithNCE:_nce];
    _metal.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_metal];
    _log = [UITextView new];
    _log.editable = NO;
    _log.backgroundColor = [UIColor colorWithWhite:0.05 alpha:1];
    _log.textColor = [UIColor colorWithWhite:0.82 alpha:1];
    _log.font = [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular];
    _log.layer.cornerRadius = 10;
    _log.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_log];
    UIButton *stop = [UIButton buttonWithType:UIButtonTypeSystem];
    [stop setTitle:@"Stop" forState:UIControlStateNormal];
    stop.tintColor = HCopper();
    stop.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    [stop addTarget:self action:@selector(stop) forControlEvents:UIControlEventTouchUpInside];
    stop.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:stop];
    [NSLayoutConstraint activateConstraints:@[
        [_metal.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:8],
        [_metal.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:12],
        [_metal.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-12],
        [_metal.heightAnchor constraintEqualToAnchor:self.view.heightAnchor multiplier:0.48],
        [_log.topAnchor constraintEqualToAnchor:_metal.bottomAnchor constant:10],
        [_log.leadingAnchor constraintEqualToAnchor:_metal.leadingAnchor],
        [_log.trailingAnchor constraintEqualToAnchor:_metal.trailingAnchor],
        [_log.bottomAnchor constraintEqualToAnchor:stop.topAnchor constant:-10],
        [stop.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [stop.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-8],
        [stop.heightAnchor constraintEqualToConstant:40]
    ]];
    char err[256] = {0};
    int rc = _probe ? helion_nce_run_probe(_nce, err, sizeof err)
                    : helion_nce_run_nro(_nce, _path.fileSystemRepresentation, err, sizeof err);
    _log.text = rc ? [NSString stringWithUTF8String:err] : @"NCE started";
    _t = [NSTimer scheduledTimerWithTimeInterval:0.4 target:self selector:@selector(poll) userInfo:nil repeats:YES];
}
- (void)poll {
    _log.text = [NSString stringWithUTF8String:helion_nce_log(_nce)];
}
- (void)stop {
    [_t invalidate]; _t = nil;
    helion_nce_stop(_nce);
    [self.navigationController popViewControllerAnimated:YES];
}
- (void)dealloc { helion_nce_destroy(_nce); }
@end

#pragma mark - Home

@interface HelionHome : UIViewController <UIDocumentPickerDelegate>
@end
@implementation HelionHome {
    UILabel *_jit, *_keys;
    UIStackView *_list;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = HNavy();
    self.navigationController.navigationBar.hidden = YES;

    UILabel *mark = [UILabel new];
    mark.text = @"HELION";
    mark.font = [UIFont systemFontOfSize:36 weight:UIFontWeightHeavy];
    mark.textColor = UIColor.whiteColor;
    mark.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:mark];

    UILabel *sub = [UILabel new];
    sub.text = @"Switch. Your dumps. Native ARM64.";
    sub.font = [UIFont systemFontOfSize:15 weight:UIFontWeightRegular];
    sub.textColor = [HCopper() colorWithAlphaComponent:0.9];
    sub.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:sub];

    _jit = [UILabel new];
    _jit.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    _jit.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_jit];

    _keys = [UILabel new];
    _keys.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    _keys.textColor = HMuted();
    _keys.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_keys];

    UIButton *add = [self pill:@"Add game / keys" ice:YES];
    [add addTarget:self action:@selector(add) forControlEvents:UIControlEventTouchUpInside];
    UIButton *probe = [self pill:@"NCE probe" ice:NO];
    [probe addTarget:self action:@selector(runProbe) forControlEvents:UIControlEventTouchUpInside];
    add.translatesAutoresizingMaskIntoConstraints = NO;
    probe.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:add];
    [self.view addSubview:probe];

    UIScrollView *sc = [UIScrollView new];
    sc.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:sc];
    _list = [UIStackView new];
    _list.axis = UILayoutConstraintAxisVertical;
    _list.spacing = 12;
    _list.translatesAutoresizingMaskIntoConstraints = NO;
    [sc addSubview:_list];

    [NSLayoutConstraint activateConstraints:@[
        [mark.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:28],
        [mark.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:24],
        [sub.topAnchor constraintEqualToAnchor:mark.bottomAnchor constant:6],
        [sub.leadingAnchor constraintEqualToAnchor:mark.leadingAnchor],
        [_jit.topAnchor constraintEqualToAnchor:sub.bottomAnchor constant:16],
        [_jit.leadingAnchor constraintEqualToAnchor:mark.leadingAnchor],
        [_keys.topAnchor constraintEqualToAnchor:_jit.bottomAnchor constant:4],
        [_keys.leadingAnchor constraintEqualToAnchor:mark.leadingAnchor],
        [add.topAnchor constraintEqualToAnchor:_keys.bottomAnchor constant:18],
        [add.leadingAnchor constraintEqualToAnchor:mark.leadingAnchor],
        [add.heightAnchor constraintEqualToConstant:44],
        [probe.centerYAnchor constraintEqualToAnchor:add.centerYAnchor],
        [probe.leadingAnchor constraintEqualToAnchor:add.trailingAnchor constant:10],
        [probe.heightAnchor constraintEqualToConstant:44],
        [sc.topAnchor constraintEqualToAnchor:add.bottomAnchor constant:20],
        [sc.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [sc.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [sc.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-12],
        [_list.topAnchor constraintEqualToAnchor:sc.topAnchor],
        [_list.leadingAnchor constraintEqualToAnchor:sc.leadingAnchor],
        [_list.trailingAnchor constraintEqualToAnchor:sc.trailingAnchor],
        [_list.bottomAnchor constraintEqualToAnchor:sc.bottomAnchor],
        [_list.widthAnchor constraintEqualToAnchor:sc.widthAnchor]
    ]];
    [self reload];
}
- (UIButton *)pill:(NSString *)t ice:(BOOL)ice {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setTitle:t forState:UIControlStateNormal];
    b.backgroundColor = ice ? HIce() : HCopper();
    [b setTitleColor:HNavy() forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightBold];
    b.layer.cornerRadius = 14;
    b.contentEdgeInsets = UIEdgeInsetsMake(0, 16, 0, 16);
    return b;
}
- (void)viewWillAppear:(BOOL)a { [super viewWillAppear:a]; [self reload]; }
- (void)reload {
    BOOL jit = helion_nce_jit_ok();
    _jit.text = jit ? @"JIT  on" : @"JIT  off — StikDebug first";
    _jit.textColor = jit ? HIce() : HCopper();
    _keys.text = [HelionStore hasKeys] ? @"prod.keys  ready" : @"No prod.keys  (needed for NSP/XCI)";
    for (UIView *v in _list.arrangedSubviews) [_list removeArrangedSubview:v], [v removeFromSuperview];
    NSArray *games = [HelionStore games];
    if (!games.count) {
        UILabel *e = [UILabel new];
        e.text = @"No games yet. Add an NRO, NSP or XCI you dumped.";
        e.textColor = HMuted();
        e.font = [UIFont systemFontOfSize:14];
        e.numberOfLines = 0;
        [_list addArrangedSubview:e];
    }
    for (NSString *p in games) [_list addArrangedSubview:[self row:p]];
}
- (UIView *)row:(NSString *)path {
    UIView *v = [UIView new];
    v.backgroundColor = HCard();
    v.layer.cornerRadius = 16;
    UILabel *t = [UILabel new];
    t.text = path.lastPathComponent;
    t.textColor = UIColor.whiteColor;
    t.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    t.translatesAutoresizingMaskIntoConstraints = NO;
    [v addSubview:t];
    UIButton *go = [UIButton buttonWithType:UIButtonTypeSystem];
    [go setTitle:@"Start" forState:UIControlStateNormal];
    go.backgroundColor = HIce();
    [go setTitleColor:HNavy() forState:UIControlStateNormal];
    go.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
    go.layer.cornerRadius = 12;
    go.accessibilityValue = path;
    [go addTarget:self action:@selector(start:) forControlEvents:UIControlEventTouchUpInside];
    go.translatesAutoresizingMaskIntoConstraints = NO;
    [v addSubview:go];
    [NSLayoutConstraint activateConstraints:@[
        [v.heightAnchor constraintEqualToConstant:64],
        [t.leadingAnchor constraintEqualToAnchor:v.leadingAnchor constant:16],
        [t.centerYAnchor constraintEqualToAnchor:v.centerYAnchor],
        [t.trailingAnchor constraintLessThanOrEqualToAnchor:go.leadingAnchor constant:-8],
        [go.trailingAnchor constraintEqualToAnchor:v.trailingAnchor constant:-12],
        [go.centerYAnchor constraintEqualToAnchor:v.centerYAnchor],
        [go.widthAnchor constraintEqualToConstant:84],
        [go.heightAnchor constraintEqualToConstant:36]
    ]];
    return v;
}
- (void)add {
    NSMutableArray *types = [NSMutableArray arrayWithObject:UTTypeData];
    for (NSString *e in @[@"nro", @"nsp", @"xci", @"nso", @"keys"]) {
        UTType *t = [UTType typeWithFilenameExtension:e];
        if (t) [types addObject:t];
    }
    UIDocumentPickerViewController *p = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:types];
    p.delegate = self;
    p.allowsMultipleSelection = YES;
    [self presentViewController:p animated:YES completion:nil];
}
- (void)documentPicker:(UIDocumentPickerViewController *)c didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    for (NSURL *u in urls) [HelionStore importURL:u error:nil];
    [self reload];
}
- (void)runProbe {
    HelionSession *s = [[HelionSession alloc] initWithPath:nil probe:YES];
    [self.navigationController pushViewController:s animated:YES];
}
- (void)start:(UIButton *)b {
    NSString *path = b.accessibilityValue;
    NSString *ext = path.pathExtension.lowercaseString;
    if ([ext isEqual:@"nsp"] || [ext isEqual:@"xci"]) {
        if (![HelionStore hasKeys]) {
            UIAlertController *a = [UIAlertController alertControllerWithTitle:@"prod.keys required"
                message:@"NSP/XCI need keys dumped from your own Switch. This app never ships keys or games."
                preferredStyle:UIAlertControllerStyleAlert];
            [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:a animated:YES completion:nil];
            return;
        }
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"NCA loaded"
            message:@"Keys are present. 3D GPU HLE for commercial titles is the next core drop. NRO homebrew runs now via NCE."
            preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:a animated:YES completion:nil];
        return;
    }
    HelionSession *s = [[HelionSession alloc] initWithPath:path probe:NO];
    [self.navigationController pushViewController:s animated:YES];
}
@end

@interface HelionAppDelegate : UIResponder <UIApplicationDelegate>
@end
@implementation HelionAppDelegate
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)opt { return YES; }
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
    nav.navigationBar.tintColor = HIce();
    self.window.rootViewController = nav;
    [self.window makeKeyAndVisible];
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass([HelionAppDelegate class])); }
}

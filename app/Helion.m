// Helion — Windows & macOS on iPhone. QEMU in-process (GPL-2.0). Not UTM.
#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <GameController/GameController.h>
#import <dlfcn.h>
#import <pthread.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <fcntl.h>
#import <unistd.h>
#import <errno.h>
#import <string.h>
#import <sys/stat.h>

extern char **environ;

int qemu_init(int argc, char **argv, char **envp) __attribute__((weak));
void qemu_main_loop(void) __attribute__((weak));
void qemu_cleanup(int status) __attribute__((weak));

static UIColor *HNavy(void) { return [UIColor colorWithRed:0.05 green:0.07 blue:0.12 alpha:1]; }
static UIColor *HCard(void) { return [UIColor colorWithRed:0.10 green:0.13 blue:0.20 alpha:1]; }
static UIColor *HCopper(void) { return [UIColor colorWithRed:0.91 green:0.66 blue:0.49 alpha:1]; }
static UIColor *HIce(void) { return [UIColor colorWithRed:0.36 green:0.88 blue:0.90 alpha:1]; }

#pragma mark - Store

@interface HelionStore : NSObject
+ (NSString *)root;
+ (NSString *)isoPath:(NSString *)kind;
+ (BOOL)hasISO:(NSString *)kind;
+ (BOOL)installISO:(NSURL *)url kind:(NSString *)kind error:(NSError **)error;
+ (NSString *)diskPath:(NSString *)kind;
+ (void)ensureDisk:(NSString *)kind;
@end
@implementation HelionStore
+ (NSString *)root {
    NSString *d = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject
        stringByAppendingPathComponent:@"Helion"];
    [[NSFileManager defaultManager] createDirectoryAtPath:d withIntermediateDirectories:YES attributes:nil error:nil];
    return d;
}
+ (NSString *)isoPath:(NSString *)kind {
    return [[self root] stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.iso", kind]];
}
+ (BOOL)hasISO:(NSString *)kind {
    NSNumber *n = [[NSFileManager defaultManager] attributesOfItemAtPath:[self isoPath:kind] error:nil][NSFileSize];
    return n.unsignedLongLongValue > (8ull << 20);
}
+ (BOOL)installISO:(NSURL *)url kind:(NSString *)kind error:(NSError **)error {
    NSURL *dest = [NSURL fileURLWithPath:[self isoPath:kind]];
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm removeItemAtURL:dest error:nil];
    BOOL acc = [url startAccessingSecurityScopedResource];
    BOOL ok = [fm linkItemAtURL:url toURL:dest error:error];
    if (!ok) { if (error) *error = nil; ok = [fm copyItemAtURL:url toURL:dest error:error]; }
    if (acc) [url stopAccessingSecurityScopedResource];
    return ok;
}
+ (NSString *)diskPath:(NSString *)kind {
    return [[self root] stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.img", kind]];
}
+ (void)ensureDisk:(NSString *)kind {
    NSString *p = [self diskPath:kind];
    if ([[NSFileManager defaultManager] fileExistsAtPath:p]) return;
    int fd = open(p.fileSystemRepresentation, O_RDWR | O_CREAT, 0644);
    if (fd >= 0) { ftruncate(fd, 8ull << 30); close(fd); }
}
@end

#pragma mark - In-process QEMU (UTM-style dylib)

@interface HelionEngine : NSObject
+ (NSString *)libX86;
+ (NSString *)libARM;
+ (BOOL)ready;
+ (NSString *)status;
- (NSString *)startKind:(NSString *)kind log:(void (^)(NSString *))log;
- (void)stop;
@property(atomic) BOOL running;
@end
@implementation HelionEngine {
    void *_dl;
    pthread_t _thr;
}
static HelionEngine *GEng;
+ (instancetype)shared { static dispatch_once_t o; dispatch_once(&o, ^{ GEng = [HelionEngine new]; }); return GEng; }
+ (NSString *)libX86 {
    return [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"libqemu-system-x86_64.dylib"];
}
+ (NSString *)libARM {
    return [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"libqemu-system-aarch64.dylib"];
}
+ (unsigned long long)sz:(NSString *)p {
    return [[[NSFileManager defaultManager] attributesOfItemAtPath:p error:nil][NSFileSize] unsignedLongLongValue];
}
+ (BOOL)ready { return [self sz:[self libX86]] > 1000000ull || [self sz:[self libARM]] > 1000000ull; }
+ (NSString *)status {
    unsigned long long xs = [self sz:[self libX86]];
    unsigned long long asz = [self sz:[self libARM]];
    return [NSString stringWithFormat:@"qemu_init %s\nx86 dylib %llu\narm dylib %llu",
        qemu_init ? "linked" : "missing", xs, asz];
}
- (NSArray *)argvFor:(NSString *)kind {
    BOOL mac = [kind isEqualToString:@"mac"];
    NSString *work = [[HelionStore root] stringByAppendingPathComponent:@"run"];
    [[NSFileManager defaultManager] createDirectoryAtPath:work withIntermediateDirectories:YES attributes:nil error:nil];
    [HelionStore ensureDisk:kind];
    NSMutableArray *a = [NSMutableArray arrayWithObjects:
        @"qemu-system-x86_64",
        @"-machine", @"q35",
        @"-cpu", @"qemu64",
        @"-accel", @"tcg",
        @"-m", @"1024",
        @"-smp", @"2",
        @"-display", @"vnc=127.0.0.1:0",
        @"-vga", @"std",
        @"-usb", @"-device", @"usb-tablet",
        nil];
    if (mac) {
        NSString *fw = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"OSX-KVM"];
        NSString *code = [fw stringByAppendingPathComponent:@"OVMF_CODE_4M.fd"];
        NSString *varsSrc = [fw stringByAppendingPathComponent:@"OVMF_VARS.fd"];
        NSString *vars = [work stringByAppendingPathComponent:@"OVMF_VARS.fd"];
        if ([[NSFileManager defaultManager] fileExistsAtPath:varsSrc]) {
            [[NSFileManager defaultManager] removeItemAtPath:vars error:nil];
            [[NSFileManager defaultManager] copyItemAtPath:varsSrc toPath:vars error:nil];
        }
        if ([[NSFileManager defaultManager] fileExistsAtPath:code]) {
            [a addObject:@"-drive"];
            [a addObject:[NSString stringWithFormat:@"if=pflash,format=raw,readonly=on,file=%@", code]];
            [a addObject:@"-drive"];
            [a addObject:[NSString stringWithFormat:@"if=pflash,format=raw,file=%@", vars]];
        }
        NSString *oc = [fw stringByAppendingPathComponent:@"OpenCore.qcow2"];
        if ([[NSFileManager defaultManager] fileExistsAtPath:oc]) {
            [a addObject:@"-drive"];
            [a addObject:[NSString stringWithFormat:@"if=ide,format=qcow2,file=%@", oc]];
        }
    }
    if ([HelionStore hasISO:kind]) {
        [a addObject:@"-cdrom"];
        [a addObject:[HelionStore isoPath:kind]];
    }
    [a addObject:@"-drive"];
    [a addObject:[NSString stringWithFormat:@"if=ide,format=raw,file=%@", [HelionStore diskPath:kind]]];
    return a;
}
- (NSString *)startKind:(NSString *)kind log:(void (^)(NSString *))log {
    if (self.running) return @"already running";
    NSArray *args = [self argvFor:kind];
    if (log) log([args componentsJoinedByString:@" "]);
    int argc = (int)args.count;
    char **argv = calloc((size_t)argc + 1, sizeof(char *));
    for (int i = 0; i < argc; i++) argv[i] = strdup([args[i] UTF8String]);
    self.running = YES;
    if (qemu_init && qemu_main_loop) {
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            qemu_init(argc, argv, environ);
            qemu_main_loop();
            if (qemu_cleanup) qemu_cleanup(0);
            self.running = NO;
        });
        return nil;
    }
    NSString *lib = [HelionEngine libX86];
    if ([HelionEngine sz:lib] < 1000000ull) lib = [HelionEngine libARM];
    if ([HelionEngine sz:lib] < 1000000ull)
        return @"QEMU not linked into Helion (rebuild required)";
    _dl = dlopen(lib.fileSystemRepresentation, RTLD_NOW | RTLD_GLOBAL);
    if (!_dl) return [NSString stringWithFormat:@"dlopen: %s", dlerror()];
    int (*qinit)(int, char **, char **) = dlsym(_dl, "qemu_init");
    void (*qloop)(void) = dlsym(_dl, "qemu_main_loop");
    int (*qmain)(int, char **) = dlsym(_dl, "main");
    if (!qinit && !qmain)
        return @"dylib has no qemu_init/main";
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        if (qinit) {
            qinit(argc, argv, environ);
            if (qloop) qloop();
        } else if (qmain) {
            qmain(argc, argv);
        }
        self.running = NO;
    });
    return nil;
}
- (void)stop { self.running = NO; }
@end

#pragma mark - Tiny RFB (localhost VNC)

@interface HelionScreen : UIView
- (void)connectLoop;
- (void)disconnect;
@end
@implementation HelionScreen {
    int _fd;
    int _w, _h;
    NSMutableData *_fb;
    CALayer *_img;
    BOOL _run;
}
- (instancetype)init {
    self = [super initWithFrame:CGRectZero];
    self.backgroundColor = UIColor.blackColor;
    _img = [CALayer layer];
    _img.contentsGravity = kCAGravityResizeAspect;
    [self.layer addSublayer:_img];
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tap:)];
    [self addGestureRecognizer:tap];
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pan:)];
    [self addGestureRecognizer:pan];
    return self;
}
- (void)layoutSubviews { [super layoutSubviews]; _img.frame = self.bounds; }
- (void)disconnect { _run = NO; if (_fd > 0) { close(_fd); _fd = -1; } }
- (void)connectLoop {
    _run = YES;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        for (int i = 0; i < 40 && self->_run; i++) {
            if ([self tryConnect]) break;
            usleep(250000);
        }
    });
}
- (BOOL)readn:(void *)b n:(int)n {
    uint8_t *p = b; int g = 0;
    while (g < n && _fd >= 0) {
        ssize_t r = recv(_fd, p + g, (size_t)(n - g), 0);
        if (r <= 0) return NO;
        g += (int)r;
    }
    return YES;
}
- (BOOL)tryConnect {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return NO;
    struct sockaddr_in a = {0};
    a.sin_family = AF_INET;
    a.sin_port = htons(5900);
    inet_pton(AF_INET, "127.0.0.1", &a.sin_addr);
    if (connect(fd, (struct sockaddr *)&a, sizeof(a)) != 0) { close(fd); return NO; }
    _fd = fd;
    char ver[12];
    if (![self readn:ver n:12]) return NO;
    send(fd, "RFB 003.008\n", 12, 0);
    uint8_t nsec = 0;
    if (![self readn:&nsec n:1]) return NO;
    uint8_t types[16] = {0};
    if (nsec && nsec < 16) [self readn:types n:nsec];
    uint8_t none = 1;
    send(fd, &none, 1, 0);
    uint8_t res[4];
    [self readn:res n:4];
    uint8_t shared = 1;
    send(fd, &shared, 1, 0);
    uint8_t si[24];
    if (![self readn:si n:24]) return NO;
    _w = (si[0] << 8) | si[1];
    _h = (si[2] << 8) | si[3];
    uint32_t nlen = (si[20] << 24) | (si[21] << 16) | (si[22] << 8) | si[23];
    if (nlen && nlen < 4096) {
        char name[4096];
        [self readn:name n:(int)nlen];
    }
    uint8_t pf[20] = {0};
    pf[0] = 32; pf[1] = 24; pf[4] = 1; pf[6] = 8; pf[8] = 8; pf[10] = 8;
    pf[12] = 16; pf[14] = 8; pf[16] = 0;
    uint8_t spf[20] = {0};
    spf[0] = 0; memcpy(spf + 4, pf, 16);
    send(fd, spf, 20, 0);
    uint8_t se[8] = {2, 0, 0, 1, 0, 0, 0, 0};
    send(fd, se, 8, 0);
    [self requestFull];
    while (_run && _fd >= 0) {
        uint8_t t = 0;
        if (![self readn:&t n:1]) break;
        if (t == 0) [self fbUpdate];
        else if (t == 1) { uint8_t d[5]; [self readn:d n:5]; }
        else if (t == 2) { uint8_t d[1]; [self readn:d n:1]; uint16_t nc; [self readn:&nc n:2]; }
        else if (t == 3) { uint8_t d[9]; [self readn:d n:9]; }
    }
    return YES;
}
- (void)requestFull {
    uint8_t r[10] = {3, 0, 0, 0, 0, 0, (uint8_t)(_w >> 8), (uint8_t)_w, (uint8_t)(_h >> 8), (uint8_t)_h};
    if (_fd >= 0) send(_fd, r, 10, 0);
}
- (void)fbUpdate {
    uint8_t pad; [self readn:&pad n:1];
    uint8_t nbuf[2]; [self readn:nbuf n:2];
    int n = (nbuf[0] << 8) | nbuf[1];
    if (_w <= 0 || _h <= 0 || _w > 4096 || _h > 4096) return;
    if (!_fb || _fb.length != (NSUInteger)_w * (NSUInteger)_h * 4)
        _fb = [NSMutableData dataWithLength:(NSUInteger)_w * (NSUInteger)_h * 4];
    uint8_t *pix = _fb.mutableBytes;
    for (int i = 0; i < n; i++) {
        uint8_t rh[12];
        if (![self readn:rh n:12]) return;
        int x = (rh[0] << 8) | rh[1], y = (rh[2] << 8) | rh[3];
        int w = (rh[4] << 8) | rh[5], h = (rh[6] << 8) | rh[7];
        int enc = (rh[8] << 24) | (rh[9] << 16) | (rh[10] << 8) | rh[11];
        if (enc != 0 || w <= 0 || h <= 0) return;
        NSUInteger bytes = (NSUInteger)w * (NSUInteger)h * 4;
        NSMutableData *rect = [NSMutableData dataWithLength:bytes];
        if (![self readn:rect.mutableBytes n:(int)bytes]) return;
        uint8_t *src = rect.mutableBytes;
        for (int row = 0; row < h; row++) {
            if (y + row >= _h) break;
            memcpy(pix + ((y + row) * _w + x) * 4, src + row * w * 4, (size_t)w * 4);
        }
    }
    int w = _w, h = _h;
    NSData *copy = [_fb copy];
    dispatch_async(dispatch_get_main_queue(), ^{
        CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
        CGContextRef ctx = CGBitmapContextCreate((void *)copy.bytes, (size_t)w, (size_t)h, 8, (size_t)w * 4, cs,
            kCGImageAlphaNoneSkipLast | kCGBitmapByteOrder32Little);
        CGImageRef img = ctx ? CGBitmapContextCreateImage(ctx) : NULL;
        self->_img.contents = (__bridge id)img;
        if (img) CGImageRelease(img);
        if (ctx) CGContextRelease(ctx);
        CGColorSpaceRelease(cs);
        [self requestFull];
    });
}
- (void)sendPtr:(CGPoint)pt btn:(int)btn {
    if (_fd < 0 || _w <= 0) return;
    int x = (int)(pt.x / MAX(self.bounds.size.width, 1) * _w);
    int y = (int)(pt.y / MAX(self.bounds.size.height, 1) * _h);
    uint8_t m[6] = {5, (uint8_t)btn, (uint8_t)(x >> 8), (uint8_t)x, (uint8_t)(y >> 8), (uint8_t)y};
    send(_fd, m, 6, 0);
}
- (void)tap:(UITapGestureRecognizer *)g {
    CGPoint p = [g locationInView:self];
    [self sendPtr:p btn:1];
    [self sendPtr:p btn:0];
}
- (void)pan:(UIPanGestureRecognizer *)g {
    [self sendPtr:[g locationInView:self] btn:(g.state == UIGestureRecognizerStateEnded ? 0 : 1)];
}
@end

#pragma mark - Session

@interface HelionSession : UIViewController
- (instancetype)initWithKind:(NSString *)kind;
@end
@implementation HelionSession {
    NSString *_kind;
    HelionScreen *_screen;
    UILabel *_hint;
}
- (instancetype)initWithKind:(NSString *)kind {
    self = [super init];
    _kind = [kind copy];
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = HNavy();
    self.title = [_kind isEqualToString:@"mac"] ? @"macOS" : @"Windows";
    _screen = [HelionScreen new];
    _screen.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_screen];
    _hint = [UILabel new];
    _hint.textColor = [HIce() colorWithAlphaComponent:0.8];
    _hint.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    _hint.textAlignment = NSTextAlignmentCenter;
    _hint.numberOfLines = 0;
    BOOL mouse = GCMouse.mice.count > 0;
    _hint.text = mouse ? @"Mouse connected — click inside the machine."
                       : @"Touch: tap to click, drag to move. Attach a mouse anytime.";
    _hint.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_hint];
    [NSLayoutConstraint activateConstraints:@[
        [_hint.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:8],
        [_hint.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [_hint.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [_screen.topAnchor constraintEqualToAnchor:_hint.bottomAnchor constant:8],
        [_screen.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_screen.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_screen.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor]
    ]];
    NSString *err = [[HelionEngine shared] startKind:_kind log:^(NSString *l) {
        dispatch_async(dispatch_get_main_queue(), ^{ self->_hint.text = l; });
    }];
    if (err) _hint.text = err;
    else [_screen connectLoop];
}
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [_screen disconnect];
}
@end

#pragma mark - Home

@interface HelionHome : UIViewController <UIDocumentPickerDelegate>
@end
@implementation HelionHome {
    NSString *_pickKind;
    UILabel *_engine;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = HNavy();
    self.navigationController.navigationBar.hidden = YES;

    UILabel *mark = [UILabel new];
    mark.text = @"HELION";
    mark.font = [UIFont systemFontOfSize:34 weight:UIFontWeightHeavy];
    mark.textColor = UIColor.whiteColor;
    mark.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:mark];

    UILabel *sub = [UILabel new];
    sub.text = @"Windows and macOS. You bring the ISO.";
    sub.font = [UIFont systemFontOfSize:15 weight:UIFontWeightRegular];
    sub.textColor = [HCopper() colorWithAlphaComponent:0.95];
    sub.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:sub];

    UIView *mac = [self card:@"macOS" kind:@"mac" ice:YES];
    UIView *win = [self card:@"Windows" kind:@"win" ice:NO];
    mac.translatesAutoresizingMaskIntoConstraints = NO;
    win.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:mac];
    [self.view addSubview:win];

    _engine = [UILabel new];
    _engine.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    _engine.textColor = [UIColor colorWithWhite:0.55 alpha:1];
    _engine.numberOfLines = 3;
    _engine.text = [HelionEngine status];
    _engine.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_engine];

    [NSLayoutConstraint activateConstraints:@[
        [mark.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:28],
        [mark.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:24],
        [sub.topAnchor constraintEqualToAnchor:mark.bottomAnchor constant:6],
        [sub.leadingAnchor constraintEqualToAnchor:mark.leadingAnchor],
        [mac.topAnchor constraintEqualToAnchor:sub.bottomAnchor constant:28],
        [mac.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [mac.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [mac.heightAnchor constraintEqualToConstant:148],
        [win.topAnchor constraintEqualToAnchor:mac.bottomAnchor constant:16],
        [win.leadingAnchor constraintEqualToAnchor:mac.leadingAnchor],
        [win.trailingAnchor constraintEqualToAnchor:mac.trailingAnchor],
        [win.heightAnchor constraintEqualToConstant:148],
        [_engine.leadingAnchor constraintEqualToAnchor:mac.leadingAnchor],
        [_engine.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-16]
    ]];
}
- (UIView *)card:(NSString *)title kind:(NSString *)kind ice:(BOOL)ice {
    UIView *v = [UIView new];
    v.backgroundColor = HCard();
    v.layer.cornerRadius = 22;
    v.layer.borderWidth = 1;
    v.layer.borderColor = [(ice ? HIce() : HCopper()) colorWithAlphaComponent:0.35].CGColor;

    UILabel *t = [UILabel new];
    t.text = title;
    t.font = [UIFont systemFontOfSize:26 weight:UIFontWeightSemibold];
    t.textColor = UIColor.whiteColor;
    t.translatesAutoresizingMaskIntoConstraints = NO;
    [v addSubview:t];

    UILabel *iso = [UILabel new];
    iso.tag = 50;
    iso.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    iso.textColor = [UIColor colorWithWhite:0.7 alpha:1];
    iso.text = [HelionStore hasISO:kind] ? @"ISO ready" : @"No ISO — add your image";
    iso.translatesAutoresizingMaskIntoConstraints = NO;
    [v addSubview:iso];

    UIButton *add = [UIButton buttonWithType:UIButtonTypeSystem];
    [add setTitle:@"Add ISO" forState:UIControlStateNormal];
    add.tintColor = ice ? HIce() : HCopper();
    add.tag = ice ? 1 : 2;
    [add addTarget:self action:@selector(addISO:) forControlEvents:UIControlEventTouchUpInside];
    add.translatesAutoresizingMaskIntoConstraints = NO;
    [v addSubview:add];

    UIButton *go = [UIButton buttonWithType:UIButtonTypeSystem];
    [go setTitle:@"Start" forState:UIControlStateNormal];
    go.backgroundColor = ice ? HIce() : HCopper();
    [go setTitleColor:HNavy() forState:UIControlStateNormal];
    go.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightBold];
    go.layer.cornerRadius = 14;
    go.tag = ice ? 1 : 2;
    [go addTarget:self action:@selector(start:) forControlEvents:UIControlEventTouchUpInside];
    go.translatesAutoresizingMaskIntoConstraints = NO;
    [v addSubview:go];

    [NSLayoutConstraint activateConstraints:@[
        [t.topAnchor constraintEqualToAnchor:v.topAnchor constant:20],
        [t.leadingAnchor constraintEqualToAnchor:v.leadingAnchor constant:20],
        [iso.topAnchor constraintEqualToAnchor:t.bottomAnchor constant:6],
        [iso.leadingAnchor constraintEqualToAnchor:t.leadingAnchor],
        [add.leadingAnchor constraintEqualToAnchor:t.leadingAnchor],
        [add.bottomAnchor constraintEqualToAnchor:v.bottomAnchor constant:-16],
        [go.trailingAnchor constraintEqualToAnchor:v.trailingAnchor constant:-18],
        [go.centerYAnchor constraintEqualToAnchor:v.centerYAnchor],
        [go.widthAnchor constraintEqualToConstant:96],
        [go.heightAnchor constraintEqualToConstant:44]
    ]];
    v.accessibilityIdentifier = kind;
    return v;
}
- (NSString *)kindFrom:(UIButton *)b { return b.tag == 1 ? @"mac" : @"win"; }
- (void)addISO:(UIButton *)b {
    _pickKind = [self kindFrom:b];
    UTType *iso = [UTType typeWithFilenameExtension:@"iso"];
    UIDocumentPickerViewController *p =
        [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:iso ? @[iso, UTTypeData] : @[UTTypeData]];
    p.delegate = self;
    [self presentViewController:p animated:YES completion:nil];
}
- (void)documentPicker:(UIDocumentPickerViewController *)c didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    [HelionStore installISO:urls.firstObject kind:_pickKind error:nil];
    [self viewDidLoadRefreshISO];
}
- (void)viewDidLoadRefreshISO {
    for (UIView *v in self.view.subviews) {
        UILabel *iso = [v viewWithTag:50];
        if (![iso isKindOfClass:[UILabel class]]) continue;
        NSString *kind = v.accessibilityIdentifier;
        if (kind.length) iso.text = [HelionStore hasISO:kind] ? @"ISO ready" : @"No ISO — add your image";
    }
}
- (void)start:(UIButton *)b {
    NSString *kind = [self kindFrom:b];
    HelionSession *s = [[HelionSession alloc] initWithKind:kind];
    [self.navigationController pushViewController:s animated:YES];
}
@end

@interface HelionAppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end
@implementation HelionAppDelegate
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)opt {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:[HelionHome new]];
    nav.navigationBar.barStyle = UIBarStyleBlack;
    nav.navigationBar.tintColor = HIce();
    self.window.rootViewController = nav;
    [self.window makeKeyAndVisible];
    return YES;
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([HelionAppDelegate class]));
    }
}

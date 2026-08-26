#import "PuckPair.h"
#import <AVFoundation/AVFoundation.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <arpa/inet.h>
#import <netinet/in.h>
#import <sys/socket.h>
#import <os/log.h>

#if __has_include("puck_pair.h")
#import "puck_pair.h"
#define PUCK_PAIR_LIB 1
#endif

static UIColor *PInk(void)   { return [UIColor colorWithRed:0.04 green:0.045 blue:0.06 alpha:1]; }
static UIColor *PMint(void)  { return [UIColor colorWithRed:0.49 green:1.00 blue:0.80 alpha:1]; }
static UIColor *PPearl(void) { return [UIColor colorWithRed:0.96 green:0.97 blue:0.98 alpha:1]; }
static UIColor *PCard(void)  { return [UIColor colorWithRed:0.10 green:0.11 blue:0.14 alpha:1]; }
static UIColor *PDim(void)   { return [UIColor colorWithWhite:0.55 alpha:1]; }

static BOOL PIsAR(void) {
    for (NSString *l in NSLocale.preferredLanguages) if ([l hasPrefix:@"ar"]) return YES;
    return [[NSLocale currentLocale].languageCode.lowercaseString hasPrefix:@"ar"];
}
static NSString *PS(NSString *en, NSString *ar) { return PIsAR() ? ar : en; }

static void POpenPrefs(NSArray<NSString *> *urls) {
    for (NSString *s in urls) {
        NSURL *u = [NSURL URLWithString:s];
        if (!u) continue;
        if ([UIApplication.sharedApplication canOpenURL:u]) {
            [UIApplication.sharedApplication openURL:u options:@{} completionHandler:nil];
            return;
        }
        [UIApplication.sharedApplication openURL:u options:@{} completionHandler:nil];
    }
}

@interface PuckPair () <NSNetServiceDelegate, UIDocumentPickerDelegate, NSStreamDelegate>
@end

@implementation PuckPair {
    UILabel *_pin;
    UILabel *_status;
    UILabel *_info;
    UIButton *_start;
    UIButton *_settings;
    UIButton *_export;
    NSNetService *_svc;
    NSNetService *_probe;
    NSFileHandle *_listen;
    uint16_t _port;
    NSString *_serviceId;
    NSString *_pinCode;
    NSString *_pairPath;
    NSDictionary *_record;
    AVAudioPlayer *_keep;
    BOOL _running;
    BOOL _paired;
}

- (BOOL)prefersStatusBarHidden { return NO; }
- (UIStatusBarStyle)preferredStatusBarStyle { return UIStatusBarStyleLightContent; }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = PInk();
    self.view.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;

    UIButton *back = [UIButton buttonWithType:UIButtonTypeSystem];
    [back setTitle:PS(@"Pointer", @"المؤشر") forState:UIControlStateNormal];
    [back setTitleColor:PMint() forState:UIControlStateNormal];
    back.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    back.translatesAutoresizingMaskIntoConstraints = NO;
    [back addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:back];

    UILabel *title = [UILabel new];
    title.text = @"PUCK PAIR";
    title.font = [UIFont systemFontOfSize:28 weight:UIFontWeightBlack];
    title.textColor = PPearl();
    title.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:title];

    UILabel *sub = [UILabel new];
    sub.numberOfLines = 0;
    sub.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    sub.textColor = PMint();
    sub.text = PS(@"This phone treats Puck as a trusted computer. iOS 27 Developer Mode pairing — same path as SideInstaller / StikPair.",
                  @"الآيفون يعامل Puck ككمبيوتر موثوق. اقتران نمط المطوّر في iOS 27 — نفس مسار SideInstaller و StikPair.");
    sub.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:sub];

    UIView *pinCard = [UIView new];
    pinCard.backgroundColor = PCard();
    pinCard.layer.cornerRadius = 22;
    pinCard.layer.borderWidth = 1;
    pinCard.layer.borderColor = [PMint() colorWithAlphaComponent:0.22].CGColor;
    pinCard.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:pinCard];

    UILabel *pinL = [UILabel new];
    pinL.text = PS(@"PAIRING PIN", @"رمز الاقتران");
    pinL.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightSemibold];
    pinL.textColor = PMint();
    pinL.textAlignment = NSTextAlignmentCenter;
    pinL.translatesAutoresizingMaskIntoConstraints = NO;
    [pinCard addSubview:pinL];

    _pin = [UILabel new];
    _pin.text = @"••••••";
    _pin.font = [UIFont monospacedDigitSystemFontOfSize:44 weight:UIFontWeightBold];
    _pin.textColor = PPearl();
    _pin.textAlignment = NSTextAlignmentCenter;
    _pin.translatesAutoresizingMaskIntoConstraints = NO;
    [pinCard addSubview:_pin];

    _status = [UILabel new];
    _status.numberOfLines = 0;
    _status.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    _status.textColor = PDim();
    _status.textAlignment = NSTextAlignmentCenter;
    _status.text = PS(@"Tap Start pairing. Allow Local Network.",
                      @"اضغط ابدأ الاقتران. اسمح بالشبكة المحلية.");
    _status.translatesAutoresizingMaskIntoConstraints = NO;
    [pinCard addSubview:_status];

    _start = [self btn:PS(@"Start pairing", @"ابدأ الاقتران") mint:YES action:@selector(startPair)];
    _settings = [self btn:PS(@"Open Developer Mode", @"فتح نمط المطوّر") mint:NO action:@selector(openDev)];
    UIButton *imp = [self btn:PS(@"Import pairing file", @"استيراد ملف الاقتران") mint:NO action:@selector(importFile)];
    _export = [self btn:PS(@"Export pairing file", @"تصدير ملف الاقتران") mint:NO action:@selector(exportFile)];
    _export.enabled = NO;
    _export.alpha = 0.45;

    UIStackView *col = [[UIStackView alloc] initWithArrangedSubviews:@[_start, _settings, imp, _export]];
    col.axis = UILayoutConstraintAxisVertical;
    col.spacing = 8;
    col.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:col];

    _info = [UILabel new];
    _info.numberOfLines = 0;
    _info.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    _info.textColor = PDim();
    _info.text = [self deviceCard];
    _info.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_info];

    UILabel *note = [UILabel new];
    note.numberOfLines = 0;
    note.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
    note.textColor = PDim();
    note.text = PS(@"Pairing does not hide AssistiveTouch. The Home Screen pointer is still AssistiveTouch. Pairing gives this app a computer identity and the pairing record for your device.",
                   @"الاقتران لا يخفي اللمس المساعد. مؤشر الشاشة الرئيسية يبقى AssistiveTouch. الاقتران يعطي التطبيق هوية كمبيوتر وملف الاقتران لجهازك.");
    note.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:note];

    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [back.topAnchor constraintEqualToAnchor:g.topAnchor constant:8],
        [back.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [back.heightAnchor constraintEqualToConstant:44],
        [title.topAnchor constraintEqualToAnchor:back.bottomAnchor constant:4],
        [title.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [title.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [sub.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:6],
        [sub.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [sub.trailingAnchor constraintEqualToAnchor:title.trailingAnchor],
        [pinCard.topAnchor constraintEqualToAnchor:sub.bottomAnchor constant:16],
        [pinCard.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [pinCard.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [pinL.topAnchor constraintEqualToAnchor:pinCard.topAnchor constant:14],
        [pinL.leadingAnchor constraintEqualToAnchor:pinCard.leadingAnchor],
        [pinL.trailingAnchor constraintEqualToAnchor:pinCard.trailingAnchor],
        [_pin.topAnchor constraintEqualToAnchor:pinL.bottomAnchor constant:4],
        [_pin.leadingAnchor constraintEqualToAnchor:pinCard.leadingAnchor constant:12],
        [_pin.trailingAnchor constraintEqualToAnchor:pinCard.trailingAnchor constant:-12],
        [_status.topAnchor constraintEqualToAnchor:_pin.bottomAnchor constant:8],
        [_status.leadingAnchor constraintEqualToAnchor:pinCard.leadingAnchor constant:14],
        [_status.trailingAnchor constraintEqualToAnchor:pinCard.trailingAnchor constant:-14],
        [_status.bottomAnchor constraintEqualToAnchor:pinCard.bottomAnchor constant:-14],
        [col.topAnchor constraintEqualToAnchor:pinCard.bottomAnchor constant:16],
        [col.leadingAnchor constraintEqualToAnchor:pinCard.leadingAnchor],
        [col.trailingAnchor constraintEqualToAnchor:pinCard.trailingAnchor],
        [_info.topAnchor constraintEqualToAnchor:col.bottomAnchor constant:16],
        [_info.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [_info.trailingAnchor constraintEqualToAnchor:title.trailingAnchor],
        [note.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [note.trailingAnchor constraintEqualToAnchor:title.trailingAnchor],
        [note.bottomAnchor constraintEqualToAnchor:g.bottomAnchor constant:-12]
    ]];
}

- (UIButton *)btn:(NSString *)t mint:(BOOL)mint action:(SEL)s {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setTitle:t forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightBold];
    b.layer.cornerRadius = 12;
    b.translatesAutoresizingMaskIntoConstraints = NO;
    [b.heightAnchor constraintEqualToConstant:46].active = YES;
    if (mint) {
        b.backgroundColor = PMint();
        [b setTitleColor:PInk() forState:UIControlStateNormal];
    } else {
        b.backgroundColor = PCard();
        b.layer.borderWidth = 1;
        b.layer.borderColor = [PMint() colorWithAlphaComponent:0.22].CGColor;
        [b setTitleColor:PMint() forState:UIControlStateNormal];
    }
    [b addTarget:self action:s forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (NSString *)deviceCard {
    UIDevice *d = UIDevice.currentDevice;
    NSMutableString *s = [NSMutableString string];
    [s appendFormat:@"name     %@\n", d.name];
    [s appendFormat:@"system   %@ %@\n", d.systemName, d.systemVersion];
    [s appendFormat:@"model    %@\n", d.model];
    [s appendFormat:@"idiom    %@\n", d.userInterfaceIdiom == UIUserInterfaceIdiomPhone ? @"iPhone" : @"iPad"];
    if (_serviceId) [s appendFormat:@"host-id  %@\n", _serviceId];
    if (_record) {
        for (NSString *k in @[@"HostID", @"UDID", @"DeviceID", @"WiFiMACAddress", @"ProductType", @"identifier", @"public_key"]) {
            id v = _record[k];
            if (!v) continue;
            if ([v isKindOfClass:[NSData class]]) [s appendFormat:@"%@  present (%lu B)\n", k, (unsigned long)[(NSData *)v length]];
            else [s appendFormat:@"%@  %@\n", k, v];
        }
        [s appendString:PS(@"private keys stored on device — not shown\n", @"المفاتيح الخاصة مخزّنة على الجهاز — غير معروضة\n")];
    }
    return s;
}

- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }

- (void)openDev {
    POpenPrefs(@[
        @"App-prefs:root=Privacy&path=DEVELOPER_MODE",
        @"prefs:root=DEVELOPER_MODE",
        @"App-prefs:root=DEVELOPER_SETTINGS",
        @"App-prefs:root=Privacy"
    ]);
}

- (void)keepAlive {
    NSError *err = nil;
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback
                                     withOptions:AVAudioSessionCategoryOptionMixWithOthers
                                           error:&err];
    [[AVAudioSession sharedInstance] setActive:YES error:nil];
    NSString *path = [[NSBundle mainBundle] pathForResource:@"silence" ofType:@"wav"];
    if (!path) return;
    _keep = [[AVAudioPlayer alloc] initWithContentsOfURL:[NSURL fileURLWithPath:path] error:nil];
    _keep.numberOfLoops = -1;
    _keep.volume = 0.01;
    [_keep play];
}

- (void)startPair {
    if (_running) return;
    _running = YES;
    _paired = NO;
    [_start setTitle:PS(@"Listening…", @"يستمع…") forState:UIControlStateNormal];
    _status.text = PS(@"Allow Local Network. Then Settings → Privacy & Security → Developer Mode → Pair with Puck.",
                      @"اسمح بالشبكة المحلية. ثم الإعدادات ← الخصوصية والأمن ← نمط المطوّر ← الاقتران مع Puck.");
    [self keepAlive];
    [self probeLocalNetwork];

#ifdef PUCK_PAIR_LIB
    [self startLibHost];
#else
    [self startObjCHost];
#endif
}

- (void)probeLocalNetwork {
    _probe = [[NSNetService alloc] initWithDomain:@"local." type:@"_puckprobe._tcp." name:@"Puck" port:9];
    _probe.delegate = self;
    [_probe publish];
}

#ifdef PUCK_PAIR_LIB
static void PuckReady(void *ctx, const char *sid, uint16_t port, const char *const *keys, const char *const *vals, size_t n) {
    PuckPair *self = (__bridge PuckPair *)ctx;
    NSString *ident = sid ? @(sid) : [[NSUUID UUID] UUIDString];
    NSMutableDictionary *txt = [NSMutableDictionary dictionary];
    for (size_t i = 0; i < n; i++) {
        if (keys[i] && vals[i]) txt[@(keys[i])] = [@(vals[i]) dataUsingEncoding:NSUTF8StringEncoding];
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [self advertise:ident port:port txt:txt];
    });
}
static void PuckPin(const char *pin, void *ctx) {
    PuckPair *self = (__bridge PuckPair *)ctx;
    NSString *p = pin ? @(pin) : @"";
    dispatch_async(dispatch_get_main_queue(), ^{
        [self showPin:p];
    });
}
static void PuckDone(int32_t ok, const char *error, const char *path, const char *name, const char *udid, const char *irk, void *ctx) {
    PuckPair *self = (__bridge PuckPair *)ctx;
    NSString *err = error ? @(error) : nil;
    NSString *p = path ? @(path) : nil;
    NSString *u = udid ? @(udid) : nil;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self finished:ok != 0 path:p error:err udid:u];
    });
}

- (void)startLibHost {
    NSString *dir = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *out = [dir stringByAppendingPathComponent:@"Puck.mobiledevicepairing"];
    NSString *name = [NSString stringWithFormat:@"Puck on %@", UIDevice.currentDevice.name];
    void *ctx = (__bridge void *)self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        puck_pair_run("0.0.0.0", 0, name.UTF8String, "Mac17,7", out.UTF8String, PuckReady, PuckPin, PuckDone, ctx);
    });
}
#endif

- (void)startObjCHost {
    int fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (fd < 0) { [self fail:@"socket"]; return; }
    int yes = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_ANY);
    addr.sin_port = 0;
    if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) { close(fd); [self fail:@"bind"]; return; }
    socklen_t len = sizeof(addr);
    getsockname(fd, (struct sockaddr *)&addr, &len);
    _port = ntohs(addr.sin_port);
    listen(fd, 1);
    _listen = [[NSFileHandle alloc] initWithFileDescriptor:fd closeOnDealloc:YES];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(accepted:) name:NSFileHandleConnectionAcceptedNotification object:_listen];
    [_listen acceptConnectionInBackgroundAndNotify];

    _serviceId = [[NSUUID UUID] UUIDString];
    NSString *pin = [NSString stringWithFormat:@"%06d", arc4random_uniform(1000000)];
    [self showPin:pin];
    NSDictionary *txt = @{
        @"name": [@"Puck" dataUsingEncoding:NSUTF8StringEncoding],
        @"identifier": [_serviceId dataUsingEncoding:NSUTF8StringEncoding],
        @"model": [@"Mac17,7" dataUsingEncoding:NSUTF8StringEncoding],
        @"flags": [@"1" dataUsingEncoding:NSUTF8StringEncoding],
        @"ver": [@"26" dataUsingEncoding:NSUTF8StringEncoding],
        @"minVer": [@"17" dataUsingEncoding:NSUTF8StringEncoding],
        @"authTag": [[NSData alloc] initWithBase64EncodedString:@"AAAAAAAAAAAAAAAAAAAAAA==" options:0] ?: [NSData data]
    };
    [self advertise:_serviceId port:_port txt:txt];
}

- (void)advertise:(NSString *)ident port:(uint16_t)port txt:(NSDictionary *)txt {
    _serviceId = ident;
    _port = port;
    [_svc stop];
    NSString *inst = ident.length > 15 ? [ident substringToIndex:15] : ident;
    _svc = [[NSNetService alloc] initWithDomain:@"local." type:@"_remotepairing-pairable-host._tcp." name:inst port:port];
    _svc.delegate = self;
    if (txt.count) [_svc setTXTRecordData:[NSNetService dataFromTXTRecordDictionary:txt]];
    [_svc publish];
    _info.text = [self deviceCard];
    _status.text = PS(@"Broadcasting as a Mac. Open Developer Mode → Pair with Puck, then type the PIN.",
                      @"يُعلن ككمبيوتر Mac. افتح نمط المطوّر ← الاقتران مع Puck، ثم أدخل الرمز.");
}

- (void)showPin:(NSString *)pin {
    _pinCode = pin;
    _pin.text = pin;
    [UIPasteboard generalPasteboard].string = pin;
    _status.text = PS(@"PIN ready. Enter it under Pair with Puck. Copied.",
                      @"الرمز جاهز. أدخله في الاقتران مع Puck. نُسخ.");
}

- (void)accepted:(NSNotification *)n {
    NSFileHandle *inc = n.userInfo[NSFileHandleNotificationFileHandleItem];
    (void)inc;
    _status.text = PS(@"A device connected. Waiting for Developer Mode PIN confirm.",
                      @"جهاز اتصل. بانتظار تأكيد الرمز في نمط المطوّر.");
}

- (void)finished:(BOOL)ok path:(NSString *)path error:(NSString *)err udid:(NSString *)udid {
    _running = NO;
    if (!ok) {
        _status.text = err.length ? err : PS(@"Pairing failed", @"فشل الاقتران");
        [_start setTitle:PS(@"Try again", @"حاول مرة أخرى") forState:UIControlStateNormal];
        return;
    }
    _paired = YES;
    _pairPath = path;
    if (path) {
        NSData *d = [NSData dataWithContentsOfFile:path];
        if (d) {
            id obj = [NSPropertyListSerialization propertyListWithData:d options:0 format:NULL error:nil];
            if ([obj isKindOfClass:[NSDictionary class]]) _record = obj;
        }
    }
    _export.enabled = YES;
    _export.alpha = 1;
    [_start setTitle:PS(@"Paired", @"مقترن") forState:UIControlStateNormal];
    _status.text = PS(@"Paired. Export the file for StikDebug / SideStore if you need it.",
                      @"تم الاقتران. صدّر الملف لـ StikDebug أو SideStore إن احتجته.");
    _info.text = [self deviceCard];
    (void)udid;
}

- (void)fail:(NSString *)why {
    _running = NO;
    _status.text = why;
    [_start setTitle:PS(@"Try again", @"حاول مرة أخرى") forState:UIControlStateNormal];
}

- (void)netServiceDidPublish:(NSNetService *)sender {
    if (sender == _probe) return;
    os_log(OS_LOG_DEFAULT, "puck pair published %{public}@:%d", sender.type, (int)sender.port);
}

- (void)netService:(NSNetService *)sender didNotPublish:(NSDictionary<NSString *,NSNumber *> *)errorDict {
    if (sender == _probe) return;
    _status.text = PS(@"Could not advertise on the local network. Allow Local Network for Puck.",
                      @"تعذر الإعلان على الشبكة المحلية. اسمح لـ Puck بالشبكة المحلية.");
}

- (void)importFile {
    UTType *plist = [UTType typeWithFilenameExtension:@"plist"] ?: UTTypePropertyList;
    UTType *pair = [UTType typeWithFilenameExtension:@"mobiledevicepairing"] ?: UTTypeData;
    UIDocumentPickerViewController *p = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[plist, pair, UTTypeData] asCopy:YES];
    p.delegate = self;
    [self presentViewController:p animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)c didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *u = urls.firstObject;
    if (!u) return;
    BOOL acc = [u startAccessingSecurityScopedResource];
    NSData *d = [NSData dataWithContentsOfURL:u];
    if (acc) [u stopAccessingSecurityScopedResource];
    if (!d) { _status.text = PS(@"Unreadable file", @"ملف غير مقروء"); return; }
    id obj = [NSPropertyListSerialization propertyListWithData:d options:0 format:NULL error:nil];
    if (![obj isKindOfClass:[NSDictionary class]]) { _status.text = PS(@"Not a pairing plist", @"ليس ملف اقتران"); return; }
    _record = obj;
    NSString *dir = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    _pairPath = [dir stringByAppendingPathComponent:@"Puck.mobiledevicepairing"];
    [d writeToFile:_pairPath atomically:YES];
    _paired = YES;
    _export.enabled = YES;
    _export.alpha = 1;
    _status.text = PS(@"Pairing file imported. This device’s computer record is stored in Puck.",
                      @"تم استيراد ملف الاقتران. سجل الكمبيوتر لهذا الجهاز مخزّن في Puck.");
    _info.text = [self deviceCard];
}

- (void)exportFile {
    if (!_pairPath) return;
    NSURL *u = [NSURL fileURLWithPath:_pairPath];
    UIActivityViewController *a = [[UIActivityViewController alloc] initWithActivityItems:@[u] applicationActivities:nil];
    a.popoverPresentationController.sourceView = _export;
    [self presentViewController:a animated:YES completion:nil];
}

- (void)dealloc {
    [_svc stop];
    [_probe stop];
    [_keep stop];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}
@end

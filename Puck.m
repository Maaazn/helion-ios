// Puck 2.0.0 — system pointer + iOS 27 Developer Mode pairing.
// Pairing: the phone treats Puck as a trusted computer (RPPairing pairable host).
// Home Screen pointer is AssistiveTouch. Pairing does not hide that overlay.


#import <UIKit/UIKit.h>
#import <GameController/GameController.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <WebKit/WebKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <notify.h>
#import "PuckPair.h"

typedef NS_ENUM(NSInteger, PuckShape) { PuckShapeMac = 0, PuckShapeWin, PuckShapePuck, PuckShapeCross, PuckShapeFile };
typedef NS_ENUM(NSInteger, PuckDesk)  { PuckDeskVoid = 0, PuckDeskGrid, PuckDeskPaper, PuckDeskPhoto };

static NSString *const kPuckSystemKey = @"puck.systemPointer";

static UIColor *Ink(void)   { return [UIColor colorWithRed:0.04 green:0.045 blue:0.06 alpha:1]; }
static UIColor *Mint(void)  { return [UIColor colorWithRed:0.49 green:1.00 blue:0.80 alpha:1]; }
static UIColor *Pearl(void) { return [UIColor colorWithRed:0.96 green:0.97 blue:0.98 alpha:1]; }
static UIColor *Card(void)  { return [UIColor colorWithRed:0.10 green:0.11 blue:0.14 alpha:1]; }
static UIColor *Dim(void)   { return [UIColor colorWithWhite:0.55 alpha:1]; }

static BOOL PuckWantSystem(void) {
    return [NSUserDefaults.standardUserDefaults boolForKey:kPuckSystemKey];
}
static void PuckSetWantSystem(BOOL on) {
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    [d setBool:on forKey:kPuckSystemKey];
    [d synchronize];
}

static BOOL PuckIsAR(void) {
    for (NSString *l in NSLocale.preferredLanguages) {
        if ([l hasPrefix:@"ar"]) return YES;
    }
    return [[NSLocale currentLocale].languageCode.lowercaseString hasPrefix:@"ar"];
}
static NSString *PuckS(NSString *en, NSString *ar) {
    return PuckIsAR() ? ar : en;
}

static BOOL PuckOpenSensitive(NSString *s) {
    NSURL *u = [NSURL URLWithString:s];
    if (!u) return NO;
    static int (*sbs)(CFURLRef, Boolean) = NULL;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *h = dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices", RTLD_NOW);
        if (h) sbs = dlsym(h, "SBSOpenSensitiveURLAndUnlock");
    });
    if (sbs && sbs((__bridge CFURLRef)u, true) == 0) return YES;
    Class LS = NSClassFromString(@"LSApplicationWorkspace");
    if (LS) {
        SEL def = @selector(defaultWorkspace);
        if ([LS respondsToSelector:def]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            id ws = [LS performSelector:def];
#pragma clang diagnostic pop
            SEL open = sel_getUid("openSensitiveURL:withOptions:");
            if (ws && [ws respondsToSelector:open]) {
                NSMethodSignature *sig = [ws methodSignatureForSelector:open];
                NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                inv.target = ws;
                inv.selector = open;
                [inv setArgument:&u atIndex:2];
                id opts = nil;
                [inv setArgument:&opts atIndex:3];
                [inv invoke];
                return YES;
            }
        }
    }
    if ([UIApplication.sharedApplication canOpenURL:u]) {
        [UIApplication.sharedApplication openURL:u options:@{} completionHandler:nil];
        return YES;
    }
    return NO;
}

static void PuckOpenPrefs(NSArray<NSString *> *urls) {
    for (NSString *s in urls) {
        if (PuckOpenSensitive(s)) return;
    }
}

static void PuckLoadAX(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dlopen("/System/Library/PrivateFrameworks/AccessibilityUtilities.framework/AccessibilityUtilities", RTLD_NOW);
        dlopen("/usr/lib/libAccessibility.dylib", RTLD_NOW);
    });
}

static id PuckAXSettings(void) {
    PuckLoadAX();
    Class c = NSClassFromString(@"AXSettings");
    if (!c) return nil;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    for (NSString *s in @[@"sharedInstance", @"sharedSettings", @"shared"]) {
        SEL sel = NSSelectorFromString(s);
        if ([c respondsToSelector:sel]) return [c performSelector:sel];
    }
#pragma clang diagnostic pop
    return nil;
}

static BOOL PuckAXCallC(const char *name, BOOL on) {
    PuckLoadAX();
    void (*fn)(BOOL) = dlsym(RTLD_DEFAULT, name);
    if (!fn) return NO;
    fn(on);
    return YES;
}

static BOOL PuckAXSet(id obj, NSString *name, BOOL on) {
    if (!obj) return NO;
    SEL sel = NSSelectorFromString(name);
    if (![obj respondsToSelector:sel]) return NO;
    NSMethodSignature *sig = [obj methodSignatureForSelector:sel];
    if (!sig || sig.numberOfArguments < 3) return NO;
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    inv.target = obj;
    inv.selector = sel;
    const char *t = [sig getArgumentTypeAtIndex:2];
    if (t && t[0] == '@') {
        id v = on ? @YES : @NO;
        [inv setArgument:&v atIndex:2];
    } else {
        BOOL v = on;
        [inv setArgument:&v atIndex:2];
    }
    [inv invoke];
    return YES;
}

static BOOL PuckAXSetDouble(id obj, NSString *name, double v) {
    if (!obj) return NO;
    SEL sel = NSSelectorFromString(name);
    if (![obj respondsToSelector:sel]) return NO;
    NSMethodSignature *sig = [obj methodSignatureForSelector:sel];
    if (!sig || sig.numberOfArguments < 3) return NO;
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    inv.target = obj;
    inv.selector = sel;
    [inv setArgument:&v atIndex:2];
    [inv invoke];
    return YES;
}

static void PuckPrefBool(CFStringRef key, BOOL on) {
    CFPreferencesSetValue(key, on ? kCFBooleanTrue : kCFBooleanFalse,
                          CFSTR("com.apple.Accessibility"),
                          kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
}

static NSString *PuckHIDDump(void) {
    NSArray *mice = GCMouse.mice;
    if (!mice.count) return @"no HID";
    NSMutableArray *parts = [NSMutableArray new];
    for (GCMouse *m in mice) {
        NSMutableArray *n = [NSMutableArray new];
        if (m.vendorName.length) [n addObject:m.vendorName];
        NSString *cat = m.productCategory;
        if (cat.length && ![n containsObject:cat]) [n addObject:cat];
        [parts addObject:n.count ? [n componentsJoinedByString:@"/"] : @"?"];
    }
    return [NSString stringWithFormat:@"%lu %@", (unsigned long)mice.count, [parts componentsJoinedByString:@" + "]];
}

/* Video: 1 USB = visual only. 2 = USB + AssistiveTouch virtual "Mouse" = system pointer. */
static BOOL PuckTwoMice(void) {
    return GCMouse.mice.count >= 2;
}

static BOOL PuckSystemLive(BOOL sawHover) {
    if (PuckTwoMice()) return YES;
    if (sawHover) return YES;
    if (UIAccessibilityIsAssistiveTouchRunning()) return YES;
    return NO;
}

static void PuckNudgeAssistiveTouch(void) {
    id ax = PuckAXSettings();
    PuckAXCallC("AXSAssistiveTouchSetEnabled", YES);
    PuckAXCallC("AXSAssistiveTouchSetHardwareEnabled", YES);
    PuckAXCallC("AXSAssistiveTouchSetUIEnabled", YES);
    PuckAXCallC("AXSAssistiveTouchSetAlwaysShowMenu", NO);

    PuckAXSet(ax, @"setAssistiveTouchEnabled:", YES);
    PuckAXSet(ax, @"setAssistiveTouchHardwareEnabled:", YES);
    PuckAXSet(ax, @"setAssistiveTouchUIEnabled:", YES);
    PuckAXSet(ax, @"setAssistiveTouchAlwaysShowMenu:", NO);
    PuckAXSet(ax, @"setAssistiveTouchAlwaysShowMenuEnabled:", NO);
    PuckAXSet(ax, @"setAssistiveTouchInternalOnlyHiddenNubbitModeEnabled:", YES);
    PuckAXSetDouble(ax, @"setAssistiveTouchIdleOpacity:", 0);

    PuckPrefBool(CFSTR("AssistiveTouchEnabled"), YES);
    PuckPrefBool(CFSTR("AlwaysShowMenu"), NO);
    PuckPrefBool(CFSTR("AssistiveTouchAlwaysShowMenu"), NO);
    CFPreferencesSynchronize(CFSTR("com.apple.Accessibility"),
                             kCFPreferencesCurrentUser, kCFPreferencesAnyHost);

    notify_post("com.apple.accessibility.cache.assistivetouch");
    notify_post("com.apple.accessibility.cache.assistivetouch.menu");
    notify_post("com.apple.pointerui.reset");
}

static NSArray<NSString *> *PuckAssistiveTouchURLs(void) {
    return @[
        @"prefs:root=ACCESSIBILITY&path=TOUCH_REACHABILITY_TITLE/AIR_TOUCH_TITLE",
        @"App-prefs:root=ACCESSIBILITY&path=TOUCH_REACHABILITY_TITLE/AIR_TOUCH_TITLE",
        @"app-prefs:root=ACCESSIBILITY&path=TOUCH_REACHABILITY_TITLE/AIR_TOUCH_TITLE",
        @"prefs:root=ACCESSIBILITY&path=TOUCH_REACHABILITY_TITLE/AIR_TOUCH_TITLE#AlwaysShowMenu",
        @"App-prefs:root=ACCESSIBILITY&path=TOUCH/ASSISTIVE_TOUCH",
        @"prefs:root=ACCESSIBILITY#TOUCH_REACHABILITY_TITLE"
    ];
}

static UIImage *PuckImageFromData(NSData *data, CGPoint *hotOut) {
    if (data.length < 8) return nil;
    const uint8_t *b = data.bytes;
    if (b[0]==0x89 && b[1]==0x50) return [UIImage imageWithData:data];
    if (b[0]==0xFF && b[1]==0xD8) return [UIImage imageWithData:data];
    if (data.length >= 22 && (b[2]|b[3]<<8) <= 2) {
        uint16_t hx = (uint16_t)(b[10] | (b[11]<<8));
        uint16_t hy = (uint16_t)(b[12] | (b[13]<<8));
        uint32_t size = b[14]|(b[15]<<8)|(b[16]<<16)|(b[17]<<24);
        uint32_t off  = b[18]|(b[19]<<8)|(b[20]<<16)|(b[21]<<24);
        if (off < data.length && b[off]==0x89 && off+8 < data.length) {
            NSUInteger n = MIN((NSUInteger)size, data.length-off);
            UIImage *img = [UIImage imageWithData:[NSData dataWithBytes:b+off length:n]];
            if (img && hotOut) *hotOut = CGPointMake(hx, hy);
            if (img) return img;
        }
    }
    UIImage *img = [UIImage imageWithData:data];
    return img;
}

@interface PuckDeskView : UIView
@property (nonatomic) PuckDesk desk;
@property (nonatomic, strong) UIImage *photo;
@end
@implementation PuckDeskView
- (void)setDesk:(PuckDesk)d { _desk = d; [self setNeedsDisplay]; }
- (void)setPhoto:(UIImage *)p { _photo = p; [self setNeedsDisplay]; }
- (void)drawRect:(CGRect)r {
    if (_desk == PuckDeskPhoto && _photo) {
        [_photo drawInRect:r];
        [[UIColor colorWithWhite:0 alpha:0.18] setFill];
        UIRectFill(r);
        return;
    }
    if (_desk == PuckDeskPaper) {
        [[UIColor colorWithRed:0.93 green:0.91 blue:0.86 alpha:1] setFill];
        UIRectFill(r);
        return;
    }
    [Card() setFill];
    UIRectFill(r);
    if (_desk == PuckDeskGrid) {
        UIBezierPath *p = [UIBezierPath bezierPath];
        p.lineWidth = 1;
        [[Mint() colorWithAlphaComponent:0.10] setStroke];
        for (CGFloat x = 0; x < r.size.width; x += 28) {
            [p moveToPoint:CGPointMake(x, 0)]; [p addLineToPoint:CGPointMake(x, r.size.height)];
        }
        for (CGFloat y = 0; y < r.size.height; y += 28) {
            [p moveToPoint:CGPointMake(0, y)]; [p addLineToPoint:CGPointMake(r.size.width, y)];
        }
        [p stroke];
    }
}
@end

@interface PuckCursor : UIView
@property (nonatomic) BOOL pressed;
@property (nonatomic) UIColor *accent;
@property (nonatomic) PuckShape shape;
@property (nonatomic, strong) UIImage *custom;
@property (nonatomic) CGPoint tip;
@end
@implementation PuckCursor
- (instancetype)initWithFrame:(CGRect)f {
    self = [super initWithFrame:f];
    self.opaque = NO;
    self.userInteractionEnabled = NO;
    _accent = Mint();
    _tip = CGPointMake(0.5, 0.5);
    return self;
}
- (UIBezierPath *)arrowPath:(CGRect)r {
    CGFloat w = r.size.width, h = r.size.height;
    UIBezierPath *p = [UIBezierPath bezierPath];
    [p moveToPoint:CGPointMake(w*0.12, h*0.08)];
    [p addLineToPoint:CGPointMake(w*0.12, h*0.72)];
    [p addLineToPoint:CGPointMake(w*0.30, h*0.56)];
    [p addLineToPoint:CGPointMake(w*0.46, h*0.92)];
    [p addLineToPoint:CGPointMake(w*0.60, h*0.86)];
    [p addLineToPoint:CGPointMake(w*0.42, h*0.50)];
    [p addLineToPoint:CGPointMake(w*0.78, h*0.50)];
    [p closePath];
    return p;
}
- (void)drawRect:(CGRect)r {
    CGFloat w = r.size.width, h = r.size.height, cx = w/2, cy = h/2;
    if (self.shape == PuckShapeFile && self.custom) {
        [self.custom drawInRect:r];
        return;
    }
    if (self.shape == PuckShapeMac || self.shape == PuckShapeWin) {
        UIBezierPath *p = [self arrowPath:r];
        UIBezierPath *sh = [p copy];
        [sh applyTransform:CGAffineTransformMakeTranslation(1.2, 1.8)];
        [[UIColor colorWithWhite:0 alpha:0.28] setFill];
        [sh fill];
        if (self.shape == PuckShapeMac) {
            [[UIColor colorWithWhite:0.08 alpha:1] setFill];
            [p fill];
            [[UIColor whiteColor] setStroke];
            p.lineWidth = MAX(1.2, w*0.045);
            [p stroke];
        } else {
            [[UIColor whiteColor] setFill];
            [p fill];
            [[UIColor blackColor] setStroke];
            p.lineWidth = MAX(1.4, w*0.05);
            [p stroke];
        }
        return;
    }
    if (self.shape == PuckShapeCross) {
        UIBezierPath *p = [UIBezierPath bezierPath];
        p.lineWidth = 2;
        [self.accent setStroke];
        [p moveToPoint:CGPointMake(cx, 4)]; [p addLineToPoint:CGPointMake(cx, h-4)];
        [p moveToPoint:CGPointMake(4, cy)]; [p addLineToPoint:CGPointMake(w-4, cy)];
        [p stroke];
        return;
    }
    CGFloat ring = self.pressed ? MIN(w,h)*0.46 : MIN(w,h)*0.38;
    CGRect rr = CGRectInset(r, (w-ring)/2, (h-ring)/2);
    UIBezierPath *outer = [UIBezierPath bezierPathWithOvalInRect:rr];
    [self.accent setStroke];
    outer.lineWidth = 2.4;
    [outer stroke];
    [[self.accent colorWithAlphaComponent:self.pressed ? 0.95 : 0.32] setFill];
    [[UIBezierPath bezierPathWithOvalInRect:CGRectInset(rr, 6, 6)] fill];
}
@end

@interface PuckHome : UIViewController <UIPointerInteractionDelegate, UIDocumentPickerDelegate>
@end
@implementation PuckHome {
    PuckDeskView *_stage;
    PuckCursor *_cursor;
    UILabel *_status;
    UILabel *_coords;
    UILabel *_device;
    UILabel *_sub;
    UISwitch *_visible;
    UISwitch *_system;
    UISlider *_size;
    UISlider *_speed;
    CGPoint _pos;
    BOOL _shown;
    CGFloat _scale;
    CGFloat _accel;
    UIColor *_accent;
    PuckShape _shape;
    PuckDesk _desk;
    NSMutableArray<UIView *> *_trail;
    UINotificationFeedbackGenerator *_haptic;
    id _connectObs;
    id _disconnectObs;
    id _activeObs;
    NSArray<UIButton *> *_shapeBtns;
    NSArray<UIButton *> *_deskBtns;
    UILabel *_sysNote;
    UIButton *_enableBtn;
    UIButton *_pairBtn;
    NSInteger _pickKind;
    BOOL _sawHover;
    BOOL _setupShown;
    UIView *_veil;
    NSTimer *_watch;
}
- (void)dealloc {
    [_watch invalidate];
    if (_connectObs) [NSNotificationCenter.defaultCenter removeObserver:_connectObs];
    if (_disconnectObs) [NSNotificationCenter.defaultCenter removeObserver:_disconnectObs];
    if (_activeObs) [NSNotificationCenter.defaultCenter removeObserver:_activeObs];
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = Ink();
    _scale = 1.2;
    _accel = 1.15;
    _shown = YES;
    _accent = Mint();
    _shape = PuckShapeMac;
    _desk = PuckDeskVoid;
    _trail = [NSMutableArray new];
    _haptic = [UINotificationFeedbackGenerator new];

    UILabel *title = [UILabel new];
    title.text = @"PUCK";
    title.font = [UIFont systemFontOfSize:32 weight:UIFontWeightBlack];
    title.textColor = Pearl();
    title.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:title];

    _pairBtn = [self mintBtn:PuckS(@"Pair", @"اقتران") action:@selector(openPair) ghost:YES];
    _pairBtn.translatesAutoresizingMaskIntoConstraints = NO;
    _pairBtn.hidden = YES;
    [self.view addSubview:_pairBtn];

    _sub = [UILabel new];
    _sub.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    _sub.textColor = Mint();
    _sub.numberOfLines = 2;
    _sub.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_sub];

    _device = [UILabel new];
    _device.font = [UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightSemibold];
    _device.textColor = Dim();
    _device.textAlignment = NSTextAlignmentRight;
    _device.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_device];

    _stage = [PuckDeskView new];
    _stage.layer.cornerRadius = 22;
    _stage.layer.borderWidth = 1;
    _stage.layer.borderColor = [Mint() colorWithAlphaComponent:0.18].CGColor;
    _stage.clipsToBounds = YES;
    _stage.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_stage];

    UIHoverGestureRecognizer *hover = [[UIHoverGestureRecognizer alloc] initWithTarget:self action:@selector(hover:)];
    [self.view addGestureRecognizer:hover];
    [self.view addInteraction:[[UIPointerInteraction alloc] initWithDelegate:self]];

    for (int i = 0; i < 3; i++) {
        UIButton *t = [UIButton buttonWithType:UIButtonTypeSystem];
        [t setTitle:@[@"Click", @"Hold", @"Hover"][i] forState:UIControlStateNormal];
        [t setTitleColor:Ink() forState:UIControlStateNormal];
        t.backgroundColor = Mint();
        t.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
        t.layer.cornerRadius = 14;
        t.frame = CGRectMake(18 + i * 100, 18, 88, 44);
        [t addTarget:self action:@selector(targetTap:) forControlEvents:UIControlEventTouchUpInside];
        [_stage addSubview:t];
    }

    _status = [UILabel new];
    _status.text = PuckS(@"Move the mouse", @"حرّك الماوس");
    _status.textColor = Pearl();
    _status.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    _status.translatesAutoresizingMaskIntoConstraints = NO;
    [_stage addSubview:_status];

    _coords = [UILabel new];
    _coords.textColor = Dim();
    _coords.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightRegular];
    _coords.translatesAutoresizingMaskIntoConstraints = NO;
    [_stage addSubview:_coords];

    _cursor = [[PuckCursor alloc] initWithFrame:CGRectMake(0, 0, 48, 48)];
    _cursor.accent = _accent;
    _cursor.shape = _shape;
    _cursor.tip = CGPointMake(0.12, 0.08);
    [self.view addSubview:_cursor];

    UIView *bar = [UIView new];
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:bar];

    UIStackView *shapes = [self chipRow:@[@"Mac", @"Win", @"Puck", @"Cross", @"File"] action:@selector(pickShape:)];
    _shapeBtns = shapes.arrangedSubviews;
    shapes.translatesAutoresizingMaskIntoConstraints = NO;
    [bar addSubview:shapes];

    UIStackView *desks = [self chipRow:@[@"Void", @"Grid", @"Paper", @"Photo"] action:@selector(pickDesk:)];
    _deskBtns = desks.arrangedSubviews;
    desks.translatesAutoresizingMaskIntoConstraints = NO;
    [bar addSubview:desks];

    UIButton *loadC = [self mintBtn:PuckS(@"Cursor file  (.cur / .png)", @"ملف المؤشر  (.cur / .png)") action:@selector(loadCursor)];
    UIButton *loadW = [self mintBtn:PuckS(@"Wallpaper", @"خلفية") action:@selector(loadWall) ghost:YES];
    loadC.translatesAutoresizingMaskIntoConstraints = NO;
    loadW.translatesAutoresizingMaskIntoConstraints = NO;
    [bar addSubview:loadC];
    [bar addSubview:loadW];

    UILabel *visL = [UILabel new];
    visL.text = PuckS(@"Show pointer", @"إظهار المؤشر");
    visL.textColor = Pearl();
    visL.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    visL.translatesAutoresizingMaskIntoConstraints = NO;
    [bar addSubview:visL];
    _visible = [UISwitch new];
    _visible.on = YES;
    _visible.onTintColor = Mint();
    [_visible addTarget:self action:@selector(toggleVisible) forControlEvents:UIControlEventValueChanged];
    _visible.translatesAutoresizingMaskIntoConstraints = NO;
    [bar addSubview:_visible];

    UILabel *sysL = [UILabel new];
    sysL.text = PuckS(@"System pointer · stays on", @"مؤشر النظام · يبقى شغال");
    sysL.textColor = Pearl();
    sysL.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    sysL.translatesAutoresizingMaskIntoConstraints = NO;
    [bar addSubview:sysL];
    _system = [UISwitch new];
    _system.on = PuckWantSystem();
    _system.onTintColor = Mint();
    [_system addTarget:self action:@selector(toggleSystem) forControlEvents:UIControlEventValueChanged];
    _system.translatesAutoresizingMaskIntoConstraints = NO;
    [bar addSubview:_system];

    UILabel *szL = [UILabel new];
    szL.text = PuckS(@"Size", @"الحجم"); szL.textColor = Dim();
    szL.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    szL.translatesAutoresizingMaskIntoConstraints = NO;
    [bar addSubview:szL];
    _size = [UISlider new];
    _size.minimumValue = 0.4; _size.maximumValue = 4.0; _size.value = 1.2;
    _size.minimumTrackTintColor = Mint();
    [_size addTarget:self action:@selector(sizeChanged) forControlEvents:UIControlEventValueChanged];
    _size.translatesAutoresizingMaskIntoConstraints = NO;
    [bar addSubview:_size];

    UILabel *spL = [UILabel new];
    spL.text = PuckS(@"Speed", @"السرعة"); spL.textColor = Dim();
    spL.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    spL.translatesAutoresizingMaskIntoConstraints = NO;
    [bar addSubview:spL];
    _speed = [UISlider new];
    _speed.minimumValue = 0.3; _speed.maximumValue = 3.0; _speed.value = 1.15;
    _speed.minimumTrackTintColor = Mint();
    [_speed addTarget:self action:@selector(speedChanged) forControlEvents:UIControlEventValueChanged];
    _speed.translatesAutoresizingMaskIntoConstraints = NO;
    [bar addSubview:_speed];

    _enableBtn = [self mintBtn:PuckS(@"Enable on iPhone", @"تفعيل على الآيفون") action:@selector(openSetup)];
    _enableBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [bar addSubview:_enableBtn];

    _sysNote = [UILabel new];
    _sysNote.textColor = Dim();
    _sysNote.font = [UIFont systemFontOfSize:11 weight:UIFontWeightRegular];
    _sysNote.numberOfLines = 2;
    _sysNote.translatesAutoresizingMaskIntoConstraints = NO;
    [bar addSubview:_sysNote];

    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [title.topAnchor constraintEqualToAnchor:g.topAnchor constant:2],
        [title.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [_sub.topAnchor constraintEqualToAnchor:title.bottomAnchor],
        [_sub.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [_sub.trailingAnchor constraintEqualToAnchor:_device.leadingAnchor constant:-8],
        [_device.centerYAnchor constraintEqualToAnchor:title.centerYAnchor],
        [_pairBtn.centerYAnchor constraintEqualToAnchor:title.centerYAnchor],
        [_pairBtn.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [_pairBtn.heightAnchor constraintEqualToConstant:32],
        [_pairBtn.widthAnchor constraintGreaterThanOrEqualToConstant:68],
        [_device.trailingAnchor constraintEqualToAnchor:_pairBtn.leadingAnchor constant:-8],
        [_device.widthAnchor constraintLessThanOrEqualToConstant:170],
        [_stage.topAnchor constraintEqualToAnchor:_sub.bottomAnchor constant:8],
        [_stage.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:14],
        [_stage.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-14],
        [_stage.bottomAnchor constraintEqualToAnchor:bar.topAnchor constant:-8],
        [_status.centerXAnchor constraintEqualToAnchor:_stage.centerXAnchor],
        [_status.centerYAnchor constraintEqualToAnchor:_stage.centerYAnchor],
        [_coords.bottomAnchor constraintEqualToAnchor:_stage.bottomAnchor constant:-10],
        [_coords.centerXAnchor constraintEqualToAnchor:_stage.centerXAnchor],
        [bar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [bar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [bar.bottomAnchor constraintEqualToAnchor:g.bottomAnchor constant:-2],
        [shapes.topAnchor constraintEqualToAnchor:bar.topAnchor],
        [shapes.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor],
        [shapes.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor],
        [desks.topAnchor constraintEqualToAnchor:shapes.bottomAnchor constant:6],
        [desks.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor],
        [desks.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor],
        [loadC.topAnchor constraintEqualToAnchor:desks.bottomAnchor constant:8],
        [loadC.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor],
        [loadC.trailingAnchor constraintEqualToAnchor:bar.centerXAnchor constant:-4],
        [loadC.heightAnchor constraintEqualToConstant:34],
        [loadW.topAnchor constraintEqualToAnchor:loadC.topAnchor],
        [loadW.leadingAnchor constraintEqualToAnchor:bar.centerXAnchor constant:4],
        [loadW.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor],
        [loadW.heightAnchor constraintEqualToConstant:34],
        [visL.topAnchor constraintEqualToAnchor:loadC.bottomAnchor constant:8],
        [visL.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor],
        [_visible.centerYAnchor constraintEqualToAnchor:visL.centerYAnchor],
        [_visible.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor],
        [sysL.topAnchor constraintEqualToAnchor:visL.bottomAnchor constant:10],
        [sysL.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor],
        [sysL.trailingAnchor constraintEqualToAnchor:_system.leadingAnchor constant:-8],
        [_system.centerYAnchor constraintEqualToAnchor:sysL.centerYAnchor],
        [_system.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor],
        [szL.topAnchor constraintEqualToAnchor:sysL.bottomAnchor constant:8],
        [szL.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor],
        [_size.centerYAnchor constraintEqualToAnchor:szL.centerYAnchor],
        [_size.leadingAnchor constraintEqualToAnchor:szL.trailingAnchor constant:10],
        [_size.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor],
        [spL.topAnchor constraintEqualToAnchor:szL.bottomAnchor constant:8],
        [spL.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor],
        [_speed.centerYAnchor constraintEqualToAnchor:spL.centerYAnchor],
        [_speed.leadingAnchor constraintEqualToAnchor:spL.trailingAnchor constant:10],
        [_speed.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor],
        [_enableBtn.topAnchor constraintEqualToAnchor:spL.bottomAnchor constant:8],
        [_enableBtn.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor],
        [_enableBtn.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor],
        [_enableBtn.heightAnchor constraintEqualToConstant:40],
        [_sysNote.topAnchor constraintEqualToAnchor:_enableBtn.bottomAnchor constant:4],
        [_sysNote.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor],
        [_sysNote.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor],
        [_sysNote.bottomAnchor constraintEqualToAnchor:bar.bottomAnchor]
    ]];

    [self buildSetup];

    __weak PuckHome *wself = self;
    _connectObs = [NSNotificationCenter.defaultCenter addObserverForName:GCMouseDidConnectNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *n) {
        [wself bindMouse:n.object];
        [wself refreshDevice];
        [wself maybeFinishSetup];
    }];
    _disconnectObs = [NSNotificationCenter.defaultCenter addObserverForName:GCMouseDidDisconnectNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *n) {
        [wself refreshDevice];
    }];
    _activeObs = [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *n) {
        [wself refreshDevice];
        if (PuckWantSystem()) {
            PuckNudgeAssistiveTouch();
            [wself maybeFinishSetup];
        }
    }];
    [self applyTip];
    [self markChips];
    [self refreshDevice];
}
- (UIButton *)mintBtn:(NSString *)t action:(SEL)s {
    return [self mintBtn:t action:s ghost:NO];
}
- (UIButton *)mintBtn:(NSString *)t action:(SEL)s ghost:(BOOL)ghost {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setTitle:t forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
    b.layer.cornerRadius = 12;
    if (ghost) {
        [b setTitleColor:Mint() forState:UIControlStateNormal];
        b.backgroundColor = Card();
        b.layer.borderWidth = 1;
        b.layer.borderColor = [Mint() colorWithAlphaComponent:0.35].CGColor;
    } else {
        [b setTitleColor:Ink() forState:UIControlStateNormal];
        b.backgroundColor = Mint();
    }
    [b addTarget:self action:s forControlEvents:UIControlEventTouchUpInside];
    return b;
}
- (UIStackView *)chipRow:(NSArray<NSString *> *)titles action:(SEL)sel {
    UIStackView *row = [UIStackView new];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.spacing = 6;
    row.distribution = UIStackViewDistributionFillEqually;
    [titles enumerateObjectsUsingBlock:^(NSString *t, NSUInteger i, BOOL *stop) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        [b setTitle:t forState:UIControlStateNormal];
        b.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightBold];
        b.layer.cornerRadius = 10;
        b.tag = (NSInteger)i;
        [b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
        [row addArrangedSubview:b];
        [b.heightAnchor constraintEqualToConstant:28].active = YES;
    }];
    return row;
}
- (void)markChips {
    [_shapeBtns enumerateObjectsUsingBlock:^(UIButton *b, NSUInteger i, BOOL *s) {
        BOOL on = (NSInteger)i == _shape;
        b.backgroundColor = on ? Mint() : Card();
        [b setTitleColor:on ? Ink() : Pearl() forState:UIControlStateNormal];
    }];
    [_deskBtns enumerateObjectsUsingBlock:^(UIButton *b, NSUInteger i, BOOL *s) {
        BOOL on = (NSInteger)i == _desk;
        b.backgroundColor = on ? Mint() : Card();
        [b setTitleColor:on ? Ink() : Pearl() forState:UIControlStateNormal];
    }];
}
- (void)applyTip {
    if (_shape == PuckShapeMac || _shape == PuckShapeWin) _cursor.tip = CGPointMake(0.12, 0.08);
    else if (_shape == PuckShapeFile) _cursor.tip = CGPointMake(0.12, 0.08);
    else _cursor.tip = CGPointMake(0.5, 0.5);
}
- (void)viewDidAppear:(BOOL)a {
    [super viewDidAppear:a];
    _pairBtn.hidden = YES;
    _pos = CGPointMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2);
    [self placeCursor];
    for (GCMouse *m in GCMouse.mice) [self bindMouse:m];
    [self refreshDevice];
    if (PuckWantSystem()) {
        PuckNudgeAssistiveTouch();
        if (!PuckSystemLive(_sawHover)) [self openSetup];
        else [self maybeFinishSetup];
        [self startWatch];
    }
}
- (void)viewDidLayoutSubviews { [super viewDidLayoutSubviews]; [self placeCursor]; }
- (UIPointerRegion *)pointerInteraction:(UIPointerInteraction *)interaction regionForRequest:(UIPointerRegionRequest *)request defaultRegion:(UIPointerRegion *)defaultRegion API_AVAILABLE(ios(13.4)) {
    return [UIPointerRegion regionWithRect:self.view.bounds identifier:@"full"];
}
- (UIPointerStyle *)pointerInteraction:(UIPointerInteraction *)interaction styleForRegion:(UIPointerRegion *)region API_AVAILABLE(ios(13.4)) {
    return [UIPointerStyle hiddenPointerStyle];
}
- (void)bindMouse:(GCMouse *)mouse {
    if (![mouse isKindOfClass:[GCMouse class]]) return;
    GCMouseInput *in = mouse.mouseInput;
    __weak PuckHome *w = self;
    in.mouseMovedHandler = ^(GCMouseInput *input, float dx, float dy) {
        dispatch_async(dispatch_get_main_queue(), ^{ [w nudge:CGPointMake(dx, -dy)]; });
    };
    in.leftButton.pressedChangedHandler = ^(GCControllerButtonInput *b, float v, BOOL p) {
        dispatch_async(dispatch_get_main_queue(), ^{ [w click:p]; });
    };
    if (in.rightButton) {
        in.rightButton.pressedChangedHandler = ^(GCControllerButtonInput *b, float v, BOOL p) {
            dispatch_async(dispatch_get_main_queue(), ^{ if (p) [w rightClick]; });
        };
    }
    if (in.scroll) {
        in.scroll.valueChangedHandler = ^(GCControllerDirectionPad *d, float dx, float dy) {
            dispatch_async(dispatch_get_main_queue(), ^{ [w note:[NSString stringWithFormat:@"scroll  %.0f", dy]]; });
        };
    }
}
- (NSString *)idleStatus {
    return PuckSystemLive(_sawHover)
        ? PuckS(@"System pointer live", @"مؤشر النظام شغال")
        : PuckS(@"Pointer live", @"المؤشر شغال");
}
- (void)refreshDevice {
    BOOL live = PuckSystemLive(_sawHover);
    BOOL want = PuckWantSystem();
    GCMouse *m = GCMouse.current ?: GCMouse.mice.firstObject;
    if (m) {
        _device.text = PuckHIDDump();
        _device.textColor = Mint();
        NSString *st = _status.text;
        BOOL busy = [st hasPrefix:@"click"] || [st hasPrefix:@"hit"] || [st hasPrefix:@"scroll"]
            || [st hasPrefix:@"Hover"] || [st hasPrefix:@"تمرير"];
        if (!busy) _status.text = [self idleStatus];
        _cursor.hidden = !_shown;
    } else {
        _device.text = PuckS(@"No mouse", @"ما في ماوس");
        _device.textColor = Dim();
        _status.text = PuckS(@"Plug a mouse", @"وصّل ماوس");
    }
    if (want && live) {
        _sub.text = PuckS(@"System pointer on. Home Screen too. Stays on.",
                          @"مؤشر النظام شغال. الشاشة الرئيسية بعد. يبقى.");
        [_enableBtn setTitle:PuckS(@"On · Home Screen · stays on", @"شغال · الشاشة الرئيسية · يبقى") forState:UIControlStateNormal];
        _enableBtn.alpha = 1;
        _sysNote.text = [NSString stringWithFormat:@"%@ · %@", PuckHIDDump(), PuckS(@"system LIVE", @"system LIVE")];
    } else if (want) {
        _sub.text = PuckS(@"Turn AssistiveTouch on once — then it stays.",
                          @"فعّل اللمس المساعد مرة واحدة — بعدها يبقى.");
        [_enableBtn setTitle:PuckS(@"Enable on iPhone", @"تفعيل على الآيفون") forState:UIControlStateNormal];
        _enableBtn.alpha = 1;
        _sysNote.text = [NSString stringWithFormat:@"%@ · %@", PuckHIDDump(), PuckS(@"visual only", @"visual only")];
    } else {
        _sub.text = PuckS(@"Your pointer. Visual only.", @"مؤشّرك. داخل التطبيق فقط.");
        [_enableBtn setTitle:PuckS(@"System pointer is off", @"مؤشر النظام طافي") forState:UIControlStateNormal];
        _enableBtn.alpha = 0.55;
        _sysNote.text = [NSString stringWithFormat:@"%@ · %@", PuckHIDDump(), PuckS(@"in-app", @"in-app")];
    }
}
- (void)hover:(UIHoverGestureRecognizer *)g {
    CGPoint p = [g locationInView:self.view];
    if (g.state == UIGestureRecognizerStateChanged || g.state == UIGestureRecognizerStateBegan) {
        BOOL first = !_sawHover;
        _sawHover = YES;
        _pos = p;
        [self placeCursor];
        [self drip];
        _status.text = PuckS(@"Hover", @"تمرير");
        _coords.text = [NSString stringWithFormat:@"%.0f  ×  %.0f", _pos.x, _pos.y];
        if (_shown) _cursor.hidden = NO;
        if (first) {
            [self refreshDevice];
            [self maybeFinishSetup];
        }
    }
}
- (void)nudge:(CGPoint)d {
    _pos.x += d.x * _accel;
    _pos.y += d.y * _accel;
    CGRect b = self.view.bounds;
    UIEdgeInsets in = self.view.safeAreaInsets;
    _pos.x = MAX(8, MIN(b.size.width-8, _pos.x));
    _pos.y = MAX(in.top+8, MIN(b.size.height-in.bottom-8, _pos.y));
    [self placeCursor];
    _coords.text = [NSString stringWithFormat:@"%.0f  ×  %.0f", _pos.x, _pos.y];
    if (_shown) _cursor.hidden = NO;
    [self drip];
    _status.text = [self idleStatus];
}
- (void)placeCursor {
    CGFloat z = 48 * _scale;
    _cursor.bounds = CGRectMake(0, 0, z, z);
    _cursor.center = CGPointMake(_pos.x + (0.5 - _cursor.tip.x)*z, _pos.y + (0.5 - _cursor.tip.y)*z);
    [_cursor setNeedsDisplay];
    [self.view bringSubviewToFront:_cursor];
    if (_veil && !_veil.hidden) [self.view bringSubviewToFront:_veil];
}
- (void)drip {
    if (!_shown) return;
    UIView *d = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 6, 6)];
    d.backgroundColor = [_accent colorWithAlphaComponent:0.28];
    d.layer.cornerRadius = 3;
    d.center = _pos;
    d.userInteractionEnabled = NO;
    [self.view insertSubview:d belowSubview:_cursor];
    [_trail addObject:d];
    while (_trail.count > 10) { [_trail.firstObject removeFromSuperview]; [_trail removeObjectAtIndex:0]; }
    [UIView animateWithDuration:0.3 animations:^{ d.alpha = 0; d.transform = CGAffineTransformMakeScale(0.2, 0.2); } completion:^(BOOL f) {
        [d removeFromSuperview];
        [self->_trail removeObject:d];
    }];
}
- (void)click:(BOOL)p {
    _cursor.pressed = p;
    [_cursor setNeedsDisplay];
    _status.text = p ? @"click" : [self idleStatus];
    if (p) [_haptic notificationOccurred:UINotificationFeedbackTypeSuccess];
}
- (void)rightClick { _status.text = @"right click"; }
- (void)note:(NSString *)s { _status.text = s; }
- (void)targetTap:(UIButton *)b { _status.text = [NSString stringWithFormat:@"hit  %@", b.currentTitle]; }
- (void)toggleVisible { _shown = _visible.on; _cursor.hidden = !_shown; }
- (void)sizeChanged { _scale = _size.value; [self placeCursor]; }
- (void)speedChanged { _accel = _speed.value; }
- (void)pickShape:(UIButton *)b {
    _shape = (PuckShape)b.tag;
    _cursor.shape = _shape;
    if (_shape == PuckShapeFile && !_cursor.custom) [self loadCursor];
    [self applyTip];
    [_cursor setNeedsDisplay];
    [self placeCursor];
    [self markChips];
}
- (void)pickDesk:(UIButton *)b {
    _desk = (PuckDesk)b.tag;
    if (_desk == PuckDeskPhoto && !_stage.photo) [self loadWall];
    _stage.desk = _desk;
    [self markChips];
}
- (void)loadCursor { _pickKind = 0; [self pickFile]; }
- (void)loadWall { _pickKind = 1; [self pickFile]; }
- (void)pickFile {
    NSArray *types = @[
        [UTType typeWithIdentifier:@"public.image"],
        [UTType typeWithIdentifier:@"public.png"],
        [UTType typeWithIdentifier:@"public.jpeg"],
        [UTType typeWithIdentifier:@"public.heic"],
        [UTType typeWithFilenameExtension:@"cur"] ?: [UTType typeWithIdentifier:@"public.data"],
        [UTType typeWithFilenameExtension:@"ani"] ?: [UTType typeWithIdentifier:@"public.data"]
    ];
    UIDocumentPickerViewController *p = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:types asCopy:YES];
    p.delegate = self;
    p.allowsMultipleSelection = NO;
    [self presentViewController:p animated:YES completion:nil];
}
- (void)documentPicker:(UIDocumentPickerViewController *)c didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *u = urls.firstObject;
    if (!u) return;
    BOOL acc = [u startAccessingSecurityScopedResource];
    NSData *d = [NSData dataWithContentsOfURL:u];
    if (acc) [u stopAccessingSecurityScopedResource];
    if (!d) { _status.text = @"file unreadable"; return; }
    CGPoint hot = CGPointMake(-1, -1);
    UIImage *img = PuckImageFromData(d, &hot);
    if (!img) { _status.text = @"not an image / .cur"; return; }
    if (_pickKind == 0) {
        _cursor.custom = img;
        _shape = PuckShapeFile;
        _cursor.shape = PuckShapeFile;
        if (hot.x >= 0 && img.size.width > 0)
            _cursor.tip = CGPointMake(hot.x / img.size.width, hot.y / img.size.height);
        else
            _cursor.tip = CGPointMake(0.12, 0.08);
        [_cursor setNeedsDisplay];
        [self placeCursor];
        [self markChips];
        _status.text = @"cursor file loaded";
    } else {
        _stage.photo = img;
        _desk = PuckDeskPhoto;
        _stage.desk = _desk;
        [self markChips];
        _status.text = @"wallpaper loaded";
    }
}
- (void)toggleSystem {
    BOOL on = _system.on;
    PuckSetWantSystem(on);
    if (on) {
        PuckNudgeAssistiveTouch();
        [self refreshDevice];
        [self startWatch];
        if (PuckSystemLive(_sawHover)) [self maybeFinishSetup];
        else [self openSetup];
    } else {
        [self hideSetup];
        [_watch invalidate];
        _watch = nil;
        [self refreshDevice];
    }
}
- (void)startWatch {
    if (_watch) return;
    __weak PuckHome *w = self;
    _watch = [NSTimer scheduledTimerWithTimeInterval:0.7 repeats:YES block:^(NSTimer *t) {
        [w refreshDevice];
        [w maybeFinishSetup];
        if (!PuckWantSystem()) { [t invalidate]; }
    }];
}
- (void)buildSetup {
    _veil = [UIView new];
    _veil.backgroundColor = [UIColor colorWithWhite:0 alpha:0.62];
    _veil.hidden = YES;
    _veil.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_veil];
    [NSLayoutConstraint activateConstraints:@[
        [_veil.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_veil.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [_veil.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_veil.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor]
    ]];

    UIView *sheet = [UIView new];
    sheet.backgroundColor = Card();
    sheet.layer.cornerRadius = 22;
    sheet.layer.borderWidth = 1;
    sheet.layer.borderColor = [Mint() colorWithAlphaComponent:0.28].CGColor;
    sheet.translatesAutoresizingMaskIntoConstraints = NO;
    [_veil addSubview:sheet];

    UILabel *h = [UILabel new];
    h.text = PuckS(@"Permanent pointer", @"المؤشر الدائم");
    h.font = [UIFont systemFontOfSize:22 weight:UIFontWeightBold];
    h.textColor = Pearl();
    h.textAlignment = NSTextAlignmentCenter;
    h.translatesAutoresizingMaskIntoConstraints = NO;
    [sheet addSubview:h];

    UILabel *b = [UILabel new];
    b.numberOfLines = 0;
    b.textAlignment = NSTextAlignmentNatural;
    b.font = [UIFont systemFontOfSize:14 weight:UIFontWeightRegular];
    b.textColor = Pearl();
    b.text = PuckS(
        @"iPhone hides the mouse pointer unless AssistiveTouch is on.\n\n1. Tap Open Settings\n2. Turn AssistiveTouch on\n3. Turn Always Show Menu off — the floating button hides\n\nAfter that the pointer is on the Home Screen and in every app. It stays until you turn AssistiveTouch off. One time.",
        @"الآيفون يخفي مؤشر الماوس إلا إذا كان اللمس المساعد شغال.\n\n١. اضغط فتح الإعدادات\n٢. فعّل اللمس المساعد\n٣. أطفئ «إظهار القائمة دائماً» حتى يختفي الزر العائم\n\nبعدها المؤشر يظهر على الشاشة الرئيسية وكل التطبيقات. يبقى حتى تطفئه. مرة واحدة.");
    b.translatesAutoresizingMaskIntoConstraints = NO;
    [sheet addSubview:b];

    UIButton *open = [self mintBtn:PuckS(@"Open AssistiveTouch settings", @"فتح إعدادات اللمس المساعد") action:@selector(jumpSettings)];
    open.translatesAutoresizingMaskIntoConstraints = NO;
    [sheet addSubview:open];

    UIButton *later = [self mintBtn:PuckS(@"Later", @"لاحقاً") action:@selector(hideSetup) ghost:YES];
    later.translatesAutoresizingMaskIntoConstraints = NO;
    [sheet addSubview:later];

    [NSLayoutConstraint activateConstraints:@[
        [sheet.leadingAnchor constraintEqualToAnchor:_veil.leadingAnchor constant:18],
        [sheet.trailingAnchor constraintEqualToAnchor:_veil.trailingAnchor constant:-18],
        [sheet.centerYAnchor constraintEqualToAnchor:_veil.centerYAnchor],
        [h.topAnchor constraintEqualToAnchor:sheet.topAnchor constant:22],
        [h.leadingAnchor constraintEqualToAnchor:sheet.leadingAnchor constant:18],
        [h.trailingAnchor constraintEqualToAnchor:sheet.trailingAnchor constant:-18],
        [b.topAnchor constraintEqualToAnchor:h.bottomAnchor constant:12],
        [b.leadingAnchor constraintEqualToAnchor:sheet.leadingAnchor constant:18],
        [b.trailingAnchor constraintEqualToAnchor:sheet.trailingAnchor constant:-18],
        [open.topAnchor constraintEqualToAnchor:b.bottomAnchor constant:18],
        [open.leadingAnchor constraintEqualToAnchor:sheet.leadingAnchor constant:18],
        [open.trailingAnchor constraintEqualToAnchor:sheet.trailingAnchor constant:-18],
        [open.heightAnchor constraintEqualToConstant:46],
        [later.topAnchor constraintEqualToAnchor:open.bottomAnchor constant:8],
        [later.leadingAnchor constraintEqualToAnchor:open.leadingAnchor],
        [later.trailingAnchor constraintEqualToAnchor:open.trailingAnchor],
        [later.heightAnchor constraintEqualToConstant:40],
        [later.bottomAnchor constraintEqualToAnchor:sheet.bottomAnchor constant:-18]
    ]];
}
- (void)openSetup {
    if (!PuckWantSystem()) {
        _system.on = YES;
        PuckSetWantSystem(YES);
    }
    PuckNudgeAssistiveTouch();
    if (PuckSystemLive(_sawHover)) {
        [self maybeFinishSetup];
        return;
    }
    _setupShown = YES;
    _veil.hidden = NO;
    _veil.alpha = 0;
    [self.view bringSubviewToFront:_veil];
    [UIView animateWithDuration:0.22 animations:^{ self->_veil.alpha = 1; }];
    [self startWatch];
}
- (void)hideSetup {
    _setupShown = NO;
    [UIView animateWithDuration:0.18 animations:^{ self->_veil.alpha = 0; } completion:^(BOOL f) {
        self->_veil.hidden = YES;
    }];
}
- (void)jumpSettings {
    PuckNudgeAssistiveTouch();
    PuckOpenPrefs(PuckAssistiveTouchURLs());
    [self startWatch];
}
- (void)openPair {
    PuckPair *p = [PuckPair new];
    p.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:p animated:YES completion:nil];
}
- (void)maybeFinishSetup {
    if (!PuckWantSystem()) return;
    if (!PuckSystemLive(_sawHover)) return;
    if (_setupShown) {
        [_haptic notificationOccurred:UINotificationFeedbackTypeSuccess];
        [self hideSetup];
    }
    [self refreshDevice];
}
@end

@interface PuckAssets : NSObject <WKURLSchemeHandler>
@end
@implementation PuckAssets {
    NSMutableSet<id<WKURLSchemeTask>> *_live;
}
- (instancetype)init {
    self = [super init];
    if (self) _live = [NSMutableSet new];
    return self;
}
- (void)fail:(id<WKURLSchemeTask>)task code:(NSInteger)code {
    if (![_live containsObject:task]) return;
    [_live removeObject:task];
    [task didFailWithError:[NSError errorWithDomain:@"puck" code:code userInfo:nil]];
}
- (void)webView:(WKWebView *)webView startURLSchemeTask:(id<WKURLSchemeTask>)task {
    [_live addObject:task];
    NSURL *url = task.request.URL;
    NSString *path = url.path ?: @"/index.html";
    if (path.length == 0 || [path isEqualToString:@"/"]) path = @"/index.html";
    if ([path hasPrefix:@"/"]) path = [path substringFromIndex:1];
    if ([path hasPrefix:@"arch/"]) {
        NSString *root = [[NSBundle mainBundle].resourcePath stringByAppendingPathComponent:@"computer"];
        NSString *local = [[root stringByAppendingPathComponent:path] stringByStandardizingPath];
        if (![[NSFileManager defaultManager] fileExistsAtPath:local]) {
            [self proxyArch:task path:path];
            return;
        }
    }
    NSString *root = [[NSBundle mainBundle].resourcePath stringByAppendingPathComponent:@"computer"];
    NSString *file = [[root stringByAppendingPathComponent:path] stringByStandardizingPath];
    if (![file hasPrefix:[root stringByStandardizingPath]]) {
        [self fail:task code:403];
        return;
    }
    if (![[NSFileManager defaultManager] fileExistsAtPath:file]) {
        [self fail:task code:404];
        return;
    }
    NSData *data = [NSData dataWithContentsOfFile:file];
    if (!data) {
        [self fail:task code:500];
        return;
    }
    NSString *mime = @"application/octet-stream";
    if ([path hasSuffix:@".html"]) mime = @"text/html";
    else if ([path hasSuffix:@".js"]) mime = @"text/javascript";
    else if ([path hasSuffix:@".wasm"]) mime = @"application/wasm";
    else if ([path hasSuffix:@".css"]) mime = @"text/css";
    else if ([path hasSuffix:@".txt"]) mime = @"text/plain";
    else if ([path hasSuffix:@".zst"] || [path hasSuffix:@".bin"]) mime = @"application/octet-stream";
    NSDictionary *headers = @{
        @"Content-Type": mime,
        @"Content-Length": [NSString stringWithFormat:@"%lu", (unsigned long)data.length],
        @"Access-Control-Allow-Origin": @"*",
        @"Accept-Ranges": @"bytes",
        @"Cache-Control": @"public, max-age=3600"
    };
    NSHTTPURLResponse *resp = [[NSHTTPURLResponse alloc] initWithURL:url statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:headers];
    if (![_live containsObject:task]) return;
    [task didReceiveResponse:resp];
    [task didReceiveData:data];
    [_live removeObject:task];
    [task didFinish];
}
- (void)proxyArch:(id<WKURLSchemeTask>)task path:(NSString *)path {
    NSString *remote = [@"https://i.copy.sh/" stringByAppendingString:path];
    NSURL *ru = [NSURL URLWithString:remote];
    if (!ru) {
        [self fail:task code:400];
        return;
    }
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:ru];
    req.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    NSString *range = task.request.allHTTPHeaderFields[@"Range"] ?: task.request.allHTTPHeaderFields[@"range"];
    if (range.length) [req setValue:range forHTTPHeaderField:@"Range"];
    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (![_live containsObject:task]) return;
            if (err || !data) {
                [_live removeObject:task];
                [task didFailWithError:err ?: [NSError errorWithDomain:@"puck" code:502 userInfo:nil]];
                return;
            }
            NSHTTPURLResponse *http = [resp isKindOfClass:[NSHTTPURLResponse class]] ? (NSHTTPURLResponse *)resp : nil;
            NSInteger code = http.statusCode > 0 ? http.statusCode : 200;
            NSMutableDictionary *headers = [NSMutableDictionary dictionary];
            headers[@"Content-Type"] = http.MIMEType ?: @"application/octet-stream";
            headers[@"Content-Length"] = [NSString stringWithFormat:@"%lu", (unsigned long)data.length];
            headers[@"Access-Control-Allow-Origin"] = @"*";
            headers[@"Accept-Ranges"] = @"bytes";
            id cr = http.allHeaderFields[@"Content-Range"] ?: http.allHeaderFields[@"content-range"];
            if (cr) headers[@"Content-Range"] = cr;
            NSHTTPURLResponse *out = [[NSHTTPURLResponse alloc] initWithURL:task.request.URL statusCode:code HTTPVersion:@"HTTP/1.1" headerFields:headers];
            [task didReceiveResponse:out];
            [task didReceiveData:data];
            [_live removeObject:task];
            [task didFinish];
        });
    }] resume];
}
- (void)webView:(WKWebView *)webView stopURLSchemeTask:(id<WKURLSchemeTask>)task {
    [_live removeObject:task];
}
@end

@interface PuckComputer : GCEventViewController <WKScriptMessageHandler, UIPointerInteractionDelegate>
@end
@implementation PuckComputer {
    WKWebView *_web;
    PuckAssets *_assets;
}
- (BOOL)canBecomeFirstResponder {
    return YES;
}
- (BOOL)prefersPointerLocked {
    return YES;
}
- (BOOL)prefersStatusBarHidden {
    return YES;
}
- (BOOL)prefersHomeIndicatorAutoHidden {
    return YES;
}
- (UIRectEdge)preferredScreenEdgesDeferringSystemGestures {
    return UIRectEdgeAll;
}
- (void)hideHostPointerOnView:(UIView *)view {
    if (@available(iOS 13.4, *)) {
        UIPointerInteraction *pi = [[UIPointerInteraction alloc] initWithDelegate:self];
        [view addInteraction:pi];
    }
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.controllerUserInteractionEnabled = YES;
    self.view.backgroundColor = Ink();
    _assets = [PuckAssets new];
    WKWebViewConfiguration *cfg = [WKWebViewConfiguration new];
    [cfg setURLSchemeHandler:_assets forURLScheme:@"puckasset"];
    cfg.allowsInlineMediaPlayback = YES;
    [cfg.userContentController addScriptMessageHandler:self name:@"puck"];
    if (@available(iOS 14.0, *)) {
        cfg.defaultWebpagePreferences.allowsContentJavaScript = YES;
    }
    _web = [[WKWebView alloc] initWithFrame:CGRectZero configuration:cfg];
    _web.opaque = NO;
    _web.backgroundColor = Ink();
    _web.scrollView.bounces = NO;
    _web.scrollView.scrollEnabled = NO;
    _web.scrollView.delaysContentTouches = NO;
    _web.scrollView.panGestureRecognizer.enabled = NO;
    _web.scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    _web.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_web];
    [NSLayoutConstraint activateConstraints:@[
        [_web.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_web.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [_web.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_web.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor]
    ]];
    [self hideHostPointerOnView:self.view];
    [self hideHostPointerOnView:_web];
    [_web loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"puckasset://app/index.html"]]];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (@available(iOS 14.0, *)) {
        [self setNeedsUpdateOfPrefersPointerLocked];
    }
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self becomeFirstResponder];
    if (@available(iOS 14.0, *)) {
        [self setNeedsUpdateOfPrefersPointerLocked];
    }
    [self setNeedsStatusBarAppearanceUpdate];
}
- (UIPointerRegion *)pointerInteraction:(UIPointerInteraction *)interaction regionForRequest:(UIPointerRegionRequest *)request defaultRegion:(UIPointerRegion *)defaultRegion API_AVAILABLE(ios(13.4)) {
    UIView *v = interaction.view ?: self.view;
    return [UIPointerRegion regionWithRect:v.bounds identifier:@"linux"];
}
- (UIPointerStyle *)pointerInteraction:(UIPointerInteraction *)interaction styleForRegion:(UIPointerRegion *)region API_AVAILABLE(ios(13.4)) {
    return [UIPointerStyle hiddenPointerStyle];
}
- (void)userContentController:(WKUserContentController *)c didReceiveScriptMessage:(WKScriptMessage *)msg {
    if (![msg.body isKindOfClass:[NSString class]]) return;
    if ([msg.body isEqualToString:@"lock"] || [msg.body isEqualToString:@"pointer"]) {
        [self becomeFirstResponder];
        if (@available(iOS 14.0, *)) {
            [self setNeedsUpdateOfPrefersPointerLocked];
        }
        return;
    }
    if ([msg.body isEqualToString:@"a11y"]) {
        NSURL *u = [NSURL URLWithString:@"App-prefs:root=ACCESSIBILITY&path=TOUCH"];
        if (!u) u = [NSURL URLWithString:@"prefs:root=ACCESSIBILITY&path=TOUCH"];
        if (u) {
            [UIApplication.sharedApplication openURL:u options:@{} completionHandler:nil];
        }
    }
}
@end

@interface PuckApp : UIResponder <UIApplicationDelegate>
@end
@implementation PuckApp
- (BOOL)application:(UIApplication *)a didFinishLaunchingWithOptions:(NSDictionary *)o { return YES; }
@end
@interface PuckScene : UIResponder <UIWindowSceneDelegate>
@property (nonatomic, strong) UIWindow *window;
@end
@implementation PuckScene
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)opts {
    if (![scene isKindOfClass:[UIWindowScene class]]) return;
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    self.window.rootViewController = [PuckHome new];
    self.window.backgroundColor = Ink();
    [self.window makeKeyAndVisible];
}
@end
int main(int argc, char *argv[]) {
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass([PuckApp class])); }
}

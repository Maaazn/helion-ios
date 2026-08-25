// Puck 1.5 — pointer via AT hardware path; hide nubbit (Always Show Menu).

#import <UIKit/UIKit.h>
#import <GameController/GameController.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <notify.h>

typedef NS_ENUM(NSInteger, PuckShape) { PuckShapeMac = 0, PuckShapeWin, PuckShapePuck, PuckShapeCross, PuckShapeFile };
typedef NS_ENUM(NSInteger, PuckDesk)  { PuckDeskVoid = 0, PuckDeskGrid, PuckDeskPaper, PuckDeskPhoto };

static UIColor *Ink(void)   { return [UIColor colorWithRed:0.04 green:0.045 blue:0.06 alpha:1]; }
static UIColor *Mint(void)  { return [UIColor colorWithRed:0.49 green:1.00 blue:0.80 alpha:1]; }
static UIColor *Pearl(void) { return [UIColor colorWithRed:0.96 green:0.97 blue:0.98 alpha:1]; }
static UIColor *Card(void)  { return [UIColor colorWithRed:0.10 green:0.11 blue:0.14 alpha:1]; }
static UIColor *Dim(void)   { return [UIColor colorWithWhite:0.55 alpha:1]; }

static void PuckOpenPrefs(NSArray<NSString *> *urls) {
    UIApplication *app = UIApplication.sharedApplication;
    for (NSString *s in urls) {
        NSURL *u = [NSURL URLWithString:s];
        if (!u) continue;
        [app openURL:u options:@{} completionHandler:nil];
        return;
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

static BOOL PuckAXGetBool(id obj, NSString *name, BOOL *outVal) {
    if (!obj || !outVal) return NO;
    SEL sel = NSSelectorFromString(name);
    if (![obj respondsToSelector:sel]) return NO;
    NSMethodSignature *sig = [obj methodSignatureForSelector:sel];
    if (!sig) return NO;
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    inv.target = obj;
    inv.selector = sel;
    [inv invoke];
    BOOL v = NO;
    [inv getReturnValue:&v];
    *outVal = v;
    return YES;
}

static NSString *PuckEnableIPhonePointer(void) {
    id ax = PuckAXSettings();
    PuckAXCallC("AXSAssistiveTouchSetEnabled", YES);
    PuckAXSet(ax, @"setAssistiveTouchHardwareEnabled:", YES);
    PuckAXSet(ax, @"setAssistiveTouchEnabled:", YES);
    PuckAXSet(ax, @"setAssistiveTouchAlwaysShowMenu:", NO);
    PuckAXSet(ax, @"setAssistiveTouchAlwaysShowMenuEnabled:", NO);
    PuckAXSet(ax, @"setAssistiveTouchInternalOnlyHiddenNubbitModeEnabled:", YES);
    PuckAXSetDouble(ax, @"setAssistiveTouchIdleOpacity:", 0);
    notify_post("com.apple.accessibility.cache.assistivetouch");
    notify_post("com.apple.accessibility.AssistiveTouch.enabled");

    BOOL hid = (GCMouse.current != nil) || (GCMouse.mice.count > 0);
    BOOL running = UIAccessibilityIsAssistiveTouchRunning();
    BOOL en = NO, menu = YES, hw = NO, nub = NO;
    PuckAXGetBool(ax, @"assistiveTouchEnabled", &en);
    PuckAXGetBool(ax, @"assistiveTouchAlwaysShowMenuEnabled", &menu);
    PuckAXGetBool(ax, @"assistiveTouchHardwareEnabled", &hw);
    PuckAXGetBool(ax, @"assistiveTouchInternalOnlyHiddenNubbitModeEnabled", &nub);

    NSMutableArray *hit = [NSMutableArray new];
    [hit addObject:hid ? @"HID" : @"no mouse"];
    [hit addObject:[NSString stringWithFormat:@"AT %@", running || en ? @"on" : @"off"]];
    [hit addObject:[NSString stringWithFormat:@"menu %@", menu ? @"shown" : @"hidden"]];
    if (nub) [hit addObject:@"nubbit hidden"];
    if (hw) [hit addObject:@"hardware"];
    if (!running && !en) [hit addObject:@"open Always Show Menu"];
    return [hit componentsJoinedByString:@" · "];
}

static NSArray<NSString *> *PuckPointerControlURLs(void) {
    return @[
        @"App-prefs:root=ACCESSIBILITY&path=TOUCH_REACHABILITY_TITLE/AIR_TOUCH_TITLE#AlwaysShowMenu",
        @"prefs:root=ACCESSIBILITY&path=TOUCH_REACHABILITY_TITLE/AIR_TOUCH_TITLE#AlwaysShowMenu",
        @"App-prefs:root=ACCESSIBILITY&path=TOUCH_REACHABILITY_TITLE/AIR_TOUCH_TITLE",
        @"prefs:root=ACCESSIBILITY&path=TOUCH_REACHABILITY_TITLE/AIR_TOUCH_TITLE",
        @"App-prefs:root=General&path=TRACKPAD",
        @"prefs:root=General&path=TRACKPAD",
        @"App-prefs:root=ACCESSIBILITY&path=POINTER_CONTROL",
        @"prefs:root=ACCESSIBILITY&path=POINTER_CONTROL",
        @"App-prefs:root=ACCESSIBILITY"
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
@property (nonatomic) CGPoint tip; // 0-1
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
    UISwitch *_visible;
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
    NSArray<UIButton *> *_shapeBtns;
    NSArray<UIButton *> *_deskBtns;
    UILabel *_sysNote;
    NSInteger _pickKind; // 0 cursor, 1 wallpaper
}
- (void)dealloc {
    if (_connectObs) [NSNotificationCenter.defaultCenter removeObserver:_connectObs];
    if (_disconnectObs) [NSNotificationCenter.defaultCenter removeObserver:_disconnectObs];
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

    UILabel *sub = [UILabel new];
    sub.text = @"Your pointer. Visual only.";
    sub.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    sub.textColor = Mint();
    sub.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:sub];

    _device = [UILabel new];
    _device.font = [UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightSemibold];
    _device.textColor = Dim();
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
    _status.text = @"Move the mouse";
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

    UIButton *loadC = [self mintBtn:@"Cursor file  (.cur / .png)" action:@selector(loadCursor)];
    UIButton *loadW = [self mintBtn:@"Wallpaper" action:@selector(loadWall) ghost:YES];
    loadC.translatesAutoresizingMaskIntoConstraints = NO;
    loadW.translatesAutoresizingMaskIntoConstraints = NO;
    [bar addSubview:loadC];
    [bar addSubview:loadW];

    UILabel *visL = [UILabel new];
    visL.text = @"Show pointer";
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

    UILabel *szL = [UILabel new];
    szL.text = @"Size"; szL.textColor = Dim();
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
    spL.text = @"Speed"; spL.textColor = Dim();
    spL.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    spL.translatesAutoresizingMaskIntoConstraints = NO;
    [bar addSubview:spL];
    _speed = [UISlider new];
    _speed.minimumValue = 0.3; _speed.maximumValue = 3.0; _speed.value = 1.15;
    _speed.minimumTrackTintColor = Mint();
    [_speed addTarget:self action:@selector(speedChanged) forControlEvents:UIControlEventValueChanged];
    _speed.translatesAutoresizingMaskIntoConstraints = NO;
    [bar addSubview:_speed];

    UIButton *sys = [self mintBtn:@"Hide AT button" action:@selector(systemPointer)];
    sys.translatesAutoresizingMaskIntoConstraints = NO;
    [bar addSubview:sys];
    UIButton *pc = [self mintBtn:@"Pointer Control" action:@selector(openPointerControl) ghost:YES];
    pc.translatesAutoresizingMaskIntoConstraints = NO;
    [bar addSubview:pc];

    _sysNote = [UILabel new];
    _sysNote.text = @"AT on + Always Show Menu off = pointer, no button.";
    _sysNote.textColor = Dim();
    _sysNote.font = [UIFont systemFontOfSize:11 weight:UIFontWeightRegular];
    _sysNote.numberOfLines = 2;
    _sysNote.translatesAutoresizingMaskIntoConstraints = NO;
    [bar addSubview:_sysNote];

    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [title.topAnchor constraintEqualToAnchor:g.topAnchor constant:2],
        [title.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [sub.topAnchor constraintEqualToAnchor:title.bottomAnchor],
        [sub.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [_device.centerYAnchor constraintEqualToAnchor:title.centerYAnchor],
        [_device.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [_stage.topAnchor constraintEqualToAnchor:sub.bottomAnchor constant:8],
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
        [szL.topAnchor constraintEqualToAnchor:visL.bottomAnchor constant:8],
        [szL.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor],
        [_size.centerYAnchor constraintEqualToAnchor:szL.centerYAnchor],
        [_size.leadingAnchor constraintEqualToAnchor:szL.trailingAnchor constant:10],
        [_size.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor],
        [spL.topAnchor constraintEqualToAnchor:szL.bottomAnchor constant:8],
        [spL.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor],
        [_speed.centerYAnchor constraintEqualToAnchor:spL.centerYAnchor],
        [_speed.leadingAnchor constraintEqualToAnchor:spL.trailingAnchor constant:10],
        [_speed.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor],
        [sys.topAnchor constraintEqualToAnchor:spL.bottomAnchor constant:8],
        [sys.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor],
        [sys.trailingAnchor constraintEqualToAnchor:bar.centerXAnchor constant:-4],
        [sys.heightAnchor constraintEqualToConstant:40],
        [pc.topAnchor constraintEqualToAnchor:sys.topAnchor],
        [pc.leadingAnchor constraintEqualToAnchor:bar.centerXAnchor constant:4],
        [pc.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor],
        [pc.heightAnchor constraintEqualToConstant:40],
        [_sysNote.topAnchor constraintEqualToAnchor:sys.bottomAnchor constant:4],
        [_sysNote.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor],
        [_sysNote.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor],
        [_sysNote.bottomAnchor constraintEqualToAnchor:bar.bottomAnchor]
    ]];

    __weak PuckHome *wself = self;
    _connectObs = [NSNotificationCenter.defaultCenter addObserverForName:GCMouseDidConnectNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *n) {
        [wself bindMouse:n.object];
        [wself refreshDevice];
        [wself systemPointer];
    }];
    _disconnectObs = [NSNotificationCenter.defaultCenter addObserverForName:GCMouseDidDisconnectNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *n) {
        [wself refreshDevice];
    }];
    [self applyTip];
    [self markChips];
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
    _pos = CGPointMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2);
    [self placeCursor];
    for (GCMouse *m in GCMouse.mice) [self bindMouse:m];
    [self refreshDevice];
    if (GCMouse.mice.count) [self systemPointer];
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
- (void)refreshDevice {
    GCMouse *m = GCMouse.current ?: GCMouse.mice.firstObject;
    if (m) {
        _device.text = m.vendorName.length ? m.vendorName : @"Mouse";
        _device.textColor = Mint();
        _status.text = @"Pointer live";
        _cursor.hidden = !_shown;
    } else {
        _device.text = @"No mouse";
        _device.textColor = Dim();
        _status.text = @"Plug a mouse";
    }
}
- (void)hover:(UIHoverGestureRecognizer *)g {
    CGPoint p = [g locationInView:self.view];
    if (g.state == UIGestureRecognizerStateChanged || g.state == UIGestureRecognizerStateBegan) {
        _pos = p;
        [self placeCursor];
        [self drip];
        _status.text = @"Hover";
        _coords.text = [NSString stringWithFormat:@"%.0f  ×  %.0f", _pos.x, _pos.y];
        if (_shown) _cursor.hidden = NO;
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
    _status.text = @"Pointer live";
}
- (void)placeCursor {
    CGFloat z = 48 * _scale;
    _cursor.bounds = CGRectMake(0, 0, z, z);
    _cursor.center = CGPointMake(_pos.x + (0.5 - _cursor.tip.x)*z, _pos.y + (0.5 - _cursor.tip.y)*z);
    [_cursor setNeedsDisplay];
    [self.view bringSubviewToFront:_cursor];
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
    _status.text = p ? @"click" : @"Pointer live";
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
- (void)systemPointer {
    NSString *ok = PuckEnableIPhonePointer();
    _sysNote.text = ok;
    _status.text = ok;
    if ([ok containsString:@"AT off"] || [ok containsString:@"menu shown"]) {
        PuckOpenPrefs(PuckPointerControlURLs());
    }
}
- (void)openPointerControl {
    [self systemPointer];
    PuckOpenPrefs(PuckPointerControlURLs());
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

// Puck — iPhone pointer. The system cursor is tied to AssistiveTouch.
// We draw a live cursor from GCMouse + hover, and open the system toggle.

#import <UIKit/UIKit.h>
#import <GameController/GameController.h>
#import <objc/runtime.h>
#import <dlfcn.h>

static UIColor *Ink(void)   { return [UIColor colorWithRed:0.04 green:0.045 blue:0.06 alpha:1]; }
static UIColor *Mint(void)  { return [UIColor colorWithRed:0.49 green:1.00 blue:0.80 alpha:1]; }
static UIColor *Pearl(void) { return [UIColor colorWithRed:0.96 green:0.97 blue:0.98 alpha:1]; }
static UIColor *Card(void)  { return [UIColor colorWithRed:0.10 green:0.11 blue:0.14 alpha:1]; }
static UIColor *Dim(void)   { return [UIColor colorWithWhite:0.55 alpha:1]; }

static BOOL PuckTryAssistiveTouch(BOOL on) {
    void *h = dlopen("/System/Library/PrivateFrameworks/AccessibilityUtilities.framework/AccessibilityUtilities", RTLD_LAZY);
    if (!h) h = dlopen("/System/Library/PrivateFrameworks/AccessibilitySettingsLoader.framework/AccessibilitySettingsLoader", RTLD_LAZY);
    if (h) {
        void (*set)(BOOL) = dlsym(h, "AXSAssistiveTouchSetEnabled");
        if (!set) set = dlsym(h, "_AXSAssistiveTouchSetEnabled");
        if (set) { set(on); return YES; }
    }
    Class cls = NSClassFromString(@"AXSettings");
    if (cls) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        id shared = [cls performSelector:NSSelectorFromString(@"sharedInstance")];
        SEL sel = NSSelectorFromString(@"setAssistiveTouchEnabled:");
        if (shared && [shared respondsToSelector:sel]) {
            [shared performSelector:sel withObject:on ? @YES : @NO];
            return YES;
        }
#pragma clang diagnostic pop
    }
    return NO;
}

static void PuckOpenAssistiveTouchSettings(void) {
    NSArray<NSString *> *urls = @[
        @"App-prefs:root=ACCESSIBILITY&path=TOUCH/ASSISTIVE_TOUCH",
        @"prefs:root=ACCESSIBILITY&path=TOUCH/ASSISTIVE_TOUCH",
        @"App-prefs:root=ACCESSIBILITY&path=TOUCH",
        @"App-prefs:root=ACCESSIBILITY"
    ];
    for (NSString *s in urls) {
        NSURL *u = [NSURL URLWithString:s];
        if (u && [UIApplication.sharedApplication canOpenURL:u]) {
            [UIApplication.sharedApplication openURL:u options:@{} completionHandler:nil];
            return;
        }
    }
    NSURL *fb = [NSURL URLWithString:UIApplicationOpenSettingsURLString];
    if (fb) [UIApplication.sharedApplication openURL:fb options:@{} completionHandler:nil];
}

@interface PuckCursor : UIView
@property (nonatomic) BOOL pressed;
@property (nonatomic) UIColor *accent;
@end
@implementation PuckCursor
- (instancetype)initWithFrame:(CGRect)f {
    self = [super initWithFrame:f];
    self.opaque = NO;
    self.userInteractionEnabled = NO;
    _accent = Mint();
    return self;
}
- (void)drawRect:(CGRect)r {
    CGFloat s = MIN(r.size.width, r.size.height);
    CGFloat ring = self.pressed ? s * 0.46 : s * 0.38;
    CGRect rr = CGRectInset(r, (r.size.width-ring)/2, (r.size.height-ring)/2);
    UIBezierPath *outer = [UIBezierPath bezierPathWithOvalInRect:rr];
    [self.accent setStroke];
    outer.lineWidth = 2.4;
    [outer stroke];
    CGRect inner = CGRectInset(rr, 6, 6);
    [[self.accent colorWithAlphaComponent:self.pressed ? 0.95 : 0.35] setFill];
    [[UIBezierPath bezierPathWithOvalInRect:inner] fill];
    CGFloat cx = CGRectGetMidX(r), cy = CGRectGetMidY(r);
    UIBezierPath *cross = [UIBezierPath bezierPath];
    cross.lineWidth = 1.2;
    [Pearl() setStroke];
    [cross moveToPoint:CGPointMake(cx-5, cy)];
    [cross addLineToPoint:CGPointMake(cx+5, cy)];
    [cross moveToPoint:CGPointMake(cx, cy-5)];
    [cross addLineToPoint:CGPointMake(cx, cy+5)];
    [cross stroke];
}
@end

@interface PuckHome : UIViewController
@end
@implementation PuckHome {
    UIView *_stage;
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
    NSMutableArray<UIView *> *_trail;
    UINotificationFeedbackGenerator *_haptic;
    id _connectObs;
    id _disconnectObs;
}
- (void)dealloc {
    if (_connectObs) [NSNotificationCenter.defaultCenter removeObserver:_connectObs];
    if (_disconnectObs) [NSNotificationCenter.defaultCenter removeObserver:_disconnectObs];
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = Ink();
    _scale = 1.0;
    _accel = 1.15;
    _shown = YES;
    _accent = Mint();
    _trail = [NSMutableArray new];
    _haptic = [UINotificationFeedbackGenerator new];

    UILabel *title = [UILabel new];
    title.text = @"PUCK";
    title.font = [UIFont systemFontOfSize:34 weight:UIFontWeightBlack];
    title.textColor = Pearl();
    title.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:title];

    UILabel *sub = [UILabel new];
    sub.text = @"The pointer iPhone hides.";
    sub.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    sub.textColor = Mint();
    sub.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:sub];

    _device = [UILabel new];
    _device.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightSemibold];
    _device.textColor = Dim();
    _device.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_device];

    _stage = [UIView new];
    _stage.backgroundColor = Card();
    _stage.layer.cornerRadius = 22;
    _stage.layer.borderWidth = 1;
    _stage.layer.borderColor = [Mint() colorWithAlphaComponent:0.18].CGColor;
    _stage.clipsToBounds = YES;
    _stage.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_stage];

    UIHoverGestureRecognizer *hover = [[UIHoverGestureRecognizer alloc] initWithTarget:self action:@selector(hover:)];
    [_stage addGestureRecognizer:hover];

    for (int i = 0; i < 3; i++) {
        UIButton *t = [UIButton buttonWithType:UIButtonTypeSystem];
        [t setTitle:@[@"Click me", @"Hold", @"Hover"][i] forState:UIControlStateNormal];
        [t setTitleColor:Ink() forState:UIControlStateNormal];
        t.backgroundColor = Mint();
        t.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightBold];
        t.layer.cornerRadius = 16;
        t.frame = CGRectMake(24 + i * 108, 24, 96, 52);
        [t addTarget:self action:@selector(targetTap:) forControlEvents:UIControlEventTouchUpInside];
        if (@available(iOS 13.4, *)) {
            UIPointerInteraction *pi = [[UIPointerInteraction alloc] initWithDelegate:nil];
            [t addInteraction:pi];
        }
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

    _cursor = [[PuckCursor alloc] initWithFrame:CGRectMake(0, 0, 44, 44)];
    _cursor.accent = _accent;
    [_stage addSubview:_cursor];

    UIView *bar = [UIView new];
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:bar];

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
    szL.text = @"Size";
    szL.textColor = Dim();
    szL.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    szL.translatesAutoresizingMaskIntoConstraints = NO;
    [bar addSubview:szL];
    _size = [UISlider new];
    _size.minimumValue = 0.7; _size.maximumValue = 2.2; _size.value = 1.0;
    _size.minimumTrackTintColor = Mint();
    [_size addTarget:self action:@selector(sizeChanged) forControlEvents:UIControlEventValueChanged];
    _size.translatesAutoresizingMaskIntoConstraints = NO;
    [bar addSubview:_size];

    UILabel *spL = [UILabel new];
    spL.text = @"Speed";
    spL.textColor = Dim();
    spL.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    spL.translatesAutoresizingMaskIntoConstraints = NO;
    [bar addSubview:spL];
    _speed = [UISlider new];
    _speed.minimumValue = 0.4; _speed.maximumValue = 2.4; _speed.value = 1.15;
    _speed.minimumTrackTintColor = Mint();
    [_speed addTarget:self action:@selector(speedChanged) forControlEvents:UIControlEventValueChanged];
    _speed.translatesAutoresizingMaskIntoConstraints = NO;
    [bar addSubview:_speed];

    UIButton *sys = [UIButton buttonWithType:UIButtonTypeSystem];
    [sys setTitle:@"  System pointer (AssistiveTouch)  " forState:UIControlStateNormal];
    [sys setTitleColor:Ink() forState:UIControlStateNormal];
    sys.backgroundColor = Mint();
    sys.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightBold];
    sys.layer.cornerRadius = 14;
    [sys addTarget:self action:@selector(systemPointer) forControlEvents:UIControlEventTouchUpInside];
    sys.translatesAutoresizingMaskIntoConstraints = NO;
    [bar addSubview:sys];

    UIButton *hideSys = [UIButton buttonWithType:UIButtonTypeSystem];
    [hideSys setTitle:@"Hide system pointer" forState:UIControlStateNormal];
    [hideSys setTitleColor:Mint() forState:UIControlStateNormal];
    hideSys.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    [hideSys addTarget:self action:@selector(hideSystem) forControlEvents:UIControlEventTouchUpInside];
    hideSys.translatesAutoresizingMaskIntoConstraints = NO;
    [bar addSubview:hideSys];

    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [title.topAnchor constraintEqualToAnchor:g.topAnchor constant:8],
        [title.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:22],
        [sub.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:2],
        [sub.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [_device.centerYAnchor constraintEqualToAnchor:title.centerYAnchor],
        [_device.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-22],
        [_stage.topAnchor constraintEqualToAnchor:sub.bottomAnchor constant:16],
        [_stage.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [_stage.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [_stage.bottomAnchor constraintEqualToAnchor:bar.topAnchor constant:-14],
        [_status.centerXAnchor constraintEqualToAnchor:_stage.centerXAnchor],
        [_status.centerYAnchor constraintEqualToAnchor:_stage.centerYAnchor],
        [_coords.bottomAnchor constraintEqualToAnchor:_stage.bottomAnchor constant:-12],
        [_coords.centerXAnchor constraintEqualToAnchor:_stage.centerXAnchor],
        [bar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:22],
        [bar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-22],
        [bar.bottomAnchor constraintEqualToAnchor:g.bottomAnchor constant:-8],
        [visL.topAnchor constraintEqualToAnchor:bar.topAnchor],
        [visL.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor],
        [_visible.centerYAnchor constraintEqualToAnchor:visL.centerYAnchor],
        [_visible.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor],
        [szL.topAnchor constraintEqualToAnchor:visL.bottomAnchor constant:12],
        [szL.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor],
        [_size.centerYAnchor constraintEqualToAnchor:szL.centerYAnchor],
        [_size.leadingAnchor constraintEqualToAnchor:szL.trailingAnchor constant:12],
        [_size.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor],
        [spL.topAnchor constraintEqualToAnchor:szL.bottomAnchor constant:12],
        [spL.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor],
        [_speed.centerYAnchor constraintEqualToAnchor:spL.centerYAnchor],
        [_speed.leadingAnchor constraintEqualToAnchor:spL.trailingAnchor constant:12],
        [_speed.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor],
        [sys.topAnchor constraintEqualToAnchor:spL.bottomAnchor constant:14],
        [sys.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor],
        [sys.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor],
        [sys.heightAnchor constraintEqualToConstant:46],
        [hideSys.topAnchor constraintEqualToAnchor:sys.bottomAnchor constant:6],
        [hideSys.centerXAnchor constraintEqualToAnchor:bar.centerXAnchor],
        [hideSys.bottomAnchor constraintEqualToAnchor:bar.bottomAnchor]
    ]];

    __weak PuckHome *w = self;
    _connectObs = [NSNotificationCenter.defaultCenter addObserverForName:GCMouseDidConnectNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *n) {
        [w bindMouse:n.object];
        [w refreshDevice];
    }];
    _disconnectObs = [NSNotificationCenter.defaultCenter addObserverForName:GCMouseDidDisconnectNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *n) {
        [w refreshDevice];
    }];
}
- (void)viewDidAppear:(BOOL)a {
    [super viewDidAppear:a];
    _pos = CGPointMake(_stage.bounds.size.width/2, _stage.bounds.size.height/2);
    [self placeCursor];
    for (GCMouse *m in GCMouse.mice) [self bindMouse:m];
    [self refreshDevice];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self placeCursor];
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
        _status.text = @"Plug a mouse or pair Bluetooth";
    }
}
- (void)hover:(UIHoverGestureRecognizer *)g {
    if (g.state == UIGestureRecognizerStateChanged || g.state == UIGestureRecognizerStateBegan) {
        _pos = [g locationInView:_stage];
        [self placeCursor];
        _status.text = @"Hover";
    }
}
- (void)nudge:(CGPoint)d {
    CGFloat s = _accel;
    _pos.x += d.x * s;
    _pos.y += d.y * s;
    CGRect b = _stage.bounds;
    _pos.x = MAX(8, MIN(b.size.width-8, _pos.x));
    _pos.y = MAX(8, MIN(b.size.height-8, _pos.y));
    [self placeCursor];
    _coords.text = [NSString stringWithFormat:@"%.0f  ×  %.0f", _pos.x, _pos.y];
    if (_shown) _cursor.hidden = NO;
    [self drip];
}
- (void)placeCursor {
    CGFloat z = 44 * _scale;
    _cursor.bounds = CGRectMake(0, 0, z, z);
    _cursor.center = _pos;
    [_cursor setNeedsDisplay];
}
- (void)drip {
    if (!_shown) return;
    UIView *d = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 8, 8)];
    d.backgroundColor = [_accent colorWithAlphaComponent:0.35];
    d.layer.cornerRadius = 4;
    d.center = _pos;
    d.userInteractionEnabled = NO;
    [_stage insertSubview:d belowSubview:_cursor];
    [_trail addObject:d];
    while (_trail.count > 10) { [_trail.firstObject removeFromSuperview]; [_trail removeObjectAtIndex:0]; }
    [UIView animateWithDuration:0.35 animations:^{ d.alpha = 0; d.transform = CGAffineTransformMakeScale(0.2, 0.2); } completion:^(BOOL f) {
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
- (void)rightClick {
    _status.text = @"right click";
    [_haptic notificationOccurred:UINotificationFeedbackTypeWarning];
}
- (void)note:(NSString *)s { _status.text = s; }
- (void)targetTap:(UIButton *)b {
    _status.text = [NSString stringWithFormat:@"hit  %@", b.currentTitle];
}
    _status.text = [NSString stringWithFormat:@"hit  %@", b.currentTitle];
}
- (void)toggleVisible {
    _shown = _visible.on;
    _cursor.hidden = !_shown;
}
- (void)sizeChanged { _scale = _size.value; [self placeCursor]; }
- (void)speedChanged { _accel = _speed.value; }
- (void)systemPointer {
    BOOL ok = PuckTryAssistiveTouch(YES);
    if (!ok) PuckOpenAssistiveTouchSettings();
    UIAlertController *a = [UIAlertController alertControllerWithTitle:ok ? @"AssistiveTouch" : @"Open Settings"
        message:ok ? @"Tried to enable the system pointer. If you still don’t see it, turn AssistiveTouch on in Accessibility."
                   : @"iPhone only draws the system cursor with AssistiveTouch. Enable it, then turn off “Always Show Menu” so only the pointer remains."
        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}
- (void)hideSystem {
    PuckTryAssistiveTouch(NO);
    PuckOpenAssistiveTouchSettings();
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

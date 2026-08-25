// Puck 1.1 — iPhone pointer studio.
// System cursor on iPhone is AssistiveTouch. In-app we hide it and draw ours.

#import <UIKit/UIKit.h>
#import <GameController/GameController.h>
#import <objc/runtime.h>
#import <dlfcn.h>

typedef NS_ENUM(NSInteger, PuckShape) { PuckShapePuck = 0, PuckShapeArrow, PuckShapeCross, PuckShapeDot, PuckShapeBeam };
typedef NS_ENUM(NSInteger, PuckDesk)  { PuckDeskVoid = 0, PuckDeskGrid, PuckDeskPaper, PuckDeskAurora };

static UIColor *Ink(void)   { return [UIColor colorWithRed:0.04 green:0.045 blue:0.06 alpha:1]; }
static UIColor *Mint(void)  { return [UIColor colorWithRed:0.49 green:1.00 blue:0.80 alpha:1]; }
static UIColor *Pearl(void) { return [UIColor colorWithRed:0.96 green:0.97 blue:0.98 alpha:1]; }
static UIColor *Card(void)  { return [UIColor colorWithRed:0.10 green:0.11 blue:0.14 alpha:1]; }
static UIColor *Dim(void)   { return [UIColor colorWithWhite:0.55 alpha:1]; }

static BOOL PuckTryAssistiveTouch(BOOL on) {
    void *h = dlopen("/System/Library/PrivateFrameworks/AccessibilityUtilities.framework/AccessibilityUtilities", RTLD_LAZY);
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
}

@interface PuckDeskView : UIView
@property (nonatomic) PuckDesk desk;
@end
@implementation PuckDeskView
- (void)setDesk:(PuckDesk)d { _desk = d; [self setNeedsDisplay]; }
- (void)drawRect:(CGRect)r {
    if (_desk == PuckDeskPaper) {
        [[UIColor colorWithRed:0.93 green:0.91 blue:0.86 alpha:1] setFill];
        UIRectFill(r);
        return;
    }
    if (_desk == PuckDeskAurora) {
        CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
        CGFloat c[] = {0.07,0.10,0.18,1, 0.08,0.22,0.20,1, 0.12,0.08,0.22,1};
        CGGradientRef g = CGGradientCreateWithColorComponents(cs, c, NULL, 3);
        CGContextDrawLinearGradient(UIGraphicsGetCurrentContext(), g, r.origin, CGPointMake(CGRectGetMaxX(r), CGRectGetMaxY(r)), 0);
        CGGradientRelease(g); CGColorSpaceRelease(cs);
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
    CGFloat w = r.size.width, h = r.size.height, cx = w/2, cy = h/2;
    UIColor *a = self.accent;
    switch (self.shape) {
        case PuckShapeArrow: {
            UIBezierPath *p = [UIBezierPath bezierPath];
            [p moveToPoint:CGPointMake(w*0.18, h*0.12)];
            [p addLineToPoint:CGPointMake(w*0.18, h*0.78)];
            [p addLineToPoint:CGPointMake(w*0.38, h*0.60)];
            [p addLineToPoint:CGPointMake(w*0.52, h*0.90)];
            [p addLineToPoint:CGPointMake(w*0.64, h*0.84)];
            [p addLineToPoint:CGPointMake(w*0.48, h*0.54)];
            [p addLineToPoint:CGPointMake(w*0.78, h*0.54)];
            [p closePath];
            [[UIColor colorWithWhite:0 alpha:0.35] setFill];
            UIBezierPath *sh = [p copy];
            [sh applyTransform:CGAffineTransformMakeTranslation(1.5, 2)];
            [sh fill];
            [Pearl() setFill];
            [p fill];
            [a setStroke];
            p.lineWidth = 1.4;
            [p stroke];
            break;
        }
        case PuckShapeCross: {
            UIBezierPath *p = [UIBezierPath bezierPath];
            p.lineWidth = 2;
            [a setStroke];
            [p moveToPoint:CGPointMake(cx, 4)]; [p addLineToPoint:CGPointMake(cx, h-4)];
            [p moveToPoint:CGPointMake(4, cy)]; [p addLineToPoint:CGPointMake(w-4, cy)];
            [p stroke];
            [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(cx-3, cy-3, 6, 6)] fill];
            [Pearl() setFill];
            [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(cx-2, cy-2, 4, 4)] fill];
            break;
        }
        case PuckShapeDot: {
            CGFloat rad = self.pressed ? 10 : 7;
            [a setFill];
            [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(cx-rad, cy-rad, rad*2, rad*2)] fill];
            [[Pearl() colorWithAlphaComponent:0.9] setFill];
            [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(cx-2.5, cy-2.5, 5, 5)] fill];
            break;
        }
        case PuckShapeBeam: {
            UIBezierPath *p = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(cx-2, 6, 4, h-12) cornerRadius:1.5];
            [a setFill]; [p fill];
            UIBezierPath *caps = [UIBezierPath bezierPath];
            caps.lineWidth = 2.2;
            [a setStroke];
            [caps moveToPoint:CGPointMake(cx-8, 8)]; [caps addLineToPoint:CGPointMake(cx+8, 8)];
            [caps moveToPoint:CGPointMake(cx-8, h-8)]; [caps addLineToPoint:CGPointMake(cx+8, h-8)];
            [caps stroke];
            break;
        }
        default: {
            CGFloat ring = self.pressed ? MIN(w,h)*0.46 : MIN(w,h)*0.38;
            CGRect rr = CGRectInset(r, (w-ring)/2, (h-ring)/2);
            UIBezierPath *outer = [UIBezierPath bezierPathWithOvalInRect:rr];
            [a setStroke];
            outer.lineWidth = 2.4;
            [outer stroke];
            [[a colorWithAlphaComponent:self.pressed ? 0.95 : 0.32] setFill];
            [[UIBezierPath bezierPathWithOvalInRect:CGRectInset(rr, 6, 6)] fill];
            UIBezierPath *cross = [UIBezierPath bezierPath];
            cross.lineWidth = 1.2;
            [Pearl() setStroke];
            [cross moveToPoint:CGPointMake(cx-5, cy)]; [cross addLineToPoint:CGPointMake(cx+5, cy)];
            [cross moveToPoint:CGPointMake(cx, cy-5)]; [cross addLineToPoint:CGPointMake(cx, cy+5)];
            [cross stroke];
            break;
        }
    }
}
@end

@interface PuckHome : UIViewController <UIPointerInteractionDelegate>
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
}
- (void)dealloc {
    if (_connectObs) [NSNotificationCenter.defaultCenter removeObserver:_connectObs];
    if (_disconnectObs) [NSNotificationCenter.defaultCenter removeObserver:_disconnectObs];
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = Ink();
    _scale = 1.15;
    _accel = 1.15;
    _shown = YES;
    _accent = Mint();
    _shape = PuckShapePuck;
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
    sub.text = @"Pointer iPhone hides.";
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
    _stage.desk = _desk;
    _stage.layer.cornerRadius = 22;
    _stage.layer.borderWidth = 1;
    _stage.layer.borderColor = [Mint() colorWithAlphaComponent:0.18].CGColor;
    _stage.clipsToBounds = YES;
    _stage.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_stage];

    UIHoverGestureRecognizer *hover = [[UIHoverGestureRecognizer alloc] initWithTarget:self action:@selector(hover:)];
    [self.view addGestureRecognizer:hover];

    UIPointerInteraction *pi = [[UIPointerInteraction alloc] initWithDelegate:self];
    [self.view addInteraction:pi];

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
    [self.view addSubview:_cursor];

    UIView *bar = [UIView new];
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:bar];

    UIStackView *shapes = [self chipRow:@[@"Puck", @"Arrow", @"Cross", @"Dot", @"Beam"] action:@selector(pickShape:)];
    _shapeBtns = shapes.arrangedSubviews;
    shapes.translatesAutoresizingMaskIntoConstraints = NO;
    [bar addSubview:shapes];

    UIStackView *desks = [self chipRow:@[@"Void", @"Grid", @"Paper", @"Aurora"] action:@selector(pickDesk:)];
    _deskBtns = desks.arrangedSubviews;
    desks.translatesAutoresizingMaskIntoConstraints = NO;
    [bar addSubview:desks];

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
    _size.minimumValue = 0.4; _size.maximumValue = 4.0; _size.value = 1.15;
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
    _speed.minimumValue = 0.3; _speed.maximumValue = 3.0; _speed.value = 1.15;
    _speed.minimumTrackTintColor = Mint();
    [_speed addTarget:self action:@selector(speedChanged) forControlEvents:UIControlEventValueChanged];
    _speed.translatesAutoresizingMaskIntoConstraints = NO;
    [bar addSubview:_speed];

    UIButton *sys = [UIButton buttonWithType:UIButtonTypeSystem];
    [sys setTitle:@"  System pointer  " forState:UIControlStateNormal];
    [sys setTitleColor:Ink() forState:UIControlStateNormal];
    sys.backgroundColor = Mint();
    sys.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightBold];
    sys.layer.cornerRadius = 14;
    [sys addTarget:self action:@selector(systemPointer) forControlEvents:UIControlEventTouchUpInside];
    sys.translatesAutoresizingMaskIntoConstraints = NO;
    [bar addSubview:sys];

    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [title.topAnchor constraintEqualToAnchor:g.topAnchor constant:4],
        [title.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [sub.topAnchor constraintEqualToAnchor:title.bottomAnchor],
        [sub.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [_device.centerYAnchor constraintEqualToAnchor:title.centerYAnchor],
        [_device.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [_stage.topAnchor constraintEqualToAnchor:sub.bottomAnchor constant:10],
        [_stage.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:14],
        [_stage.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-14],
        [_stage.bottomAnchor constraintEqualToAnchor:bar.topAnchor constant:-10],
        [_status.centerXAnchor constraintEqualToAnchor:_stage.centerXAnchor],
        [_status.centerYAnchor constraintEqualToAnchor:_stage.centerYAnchor],
        [_coords.bottomAnchor constraintEqualToAnchor:_stage.bottomAnchor constant:-10],
        [_coords.centerXAnchor constraintEqualToAnchor:_stage.centerXAnchor],
        [bar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:18],
        [bar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-18],
        [bar.bottomAnchor constraintEqualToAnchor:g.bottomAnchor constant:-4],
        [shapes.topAnchor constraintEqualToAnchor:bar.topAnchor],
        [shapes.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor],
        [shapes.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor],
        [desks.topAnchor constraintEqualToAnchor:shapes.bottomAnchor constant:8],
        [desks.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor],
        [desks.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor],
        [visL.topAnchor constraintEqualToAnchor:desks.bottomAnchor constant:10],
        [visL.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor],
        [_visible.centerYAnchor constraintEqualToAnchor:visL.centerYAnchor],
        [_visible.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor],
        [szL.topAnchor constraintEqualToAnchor:visL.bottomAnchor constant:10],
        [szL.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor],
        [_size.centerYAnchor constraintEqualToAnchor:szL.centerYAnchor],
        [_size.leadingAnchor constraintEqualToAnchor:szL.trailingAnchor constant:10],
        [_size.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor],
        [spL.topAnchor constraintEqualToAnchor:szL.bottomAnchor constant:10],
        [spL.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor],
        [_speed.centerYAnchor constraintEqualToAnchor:spL.centerYAnchor],
        [_speed.leadingAnchor constraintEqualToAnchor:spL.trailingAnchor constant:10],
        [_speed.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor],
        [sys.topAnchor constraintEqualToAnchor:spL.bottomAnchor constant:10],
        [sys.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor],
        [sys.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor],
        [sys.heightAnchor constraintEqualToConstant:42],
        [sys.bottomAnchor constraintEqualToAnchor:bar.bottomAnchor]
    ]];

    __weak PuckHome *wself = self;
    _connectObs = [NSNotificationCenter.defaultCenter addObserverForName:GCMouseDidConnectNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *n) {
        [wself bindMouse:n.object];
        [wself refreshDevice];
    }];
    _disconnectObs = [NSNotificationCenter.defaultCenter addObserverForName:GCMouseDidDisconnectNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *n) {
        [wself refreshDevice];
    }];
    [self markChips];
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
        [b.heightAnchor constraintEqualToConstant:30].active = YES;
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
- (void)viewDidAppear:(BOOL)a {
    [super viewDidAppear:a];
    _pos = CGPointMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2);
    [self placeCursor];
    for (GCMouse *m in GCMouse.mice) [self bindMouse:m];
    [self refreshDevice];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self placeCursor];
}
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
    CGFloat s = _accel;
    _pos.x += d.x * s;
    _pos.y += d.y * s;
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
    _cursor.center = _pos;
    [_cursor setNeedsDisplay];
    [self.view bringSubviewToFront:_cursor];
}
- (void)drip {
    if (!_shown) return;
    UIView *d = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 7, 7)];
    d.backgroundColor = [_accent colorWithAlphaComponent:0.32];
    d.layer.cornerRadius = 3.5;
    d.center = _pos;
    d.userInteractionEnabled = NO;
    [self.view insertSubview:d belowSubview:_cursor];
    [_trail addObject:d];
    while (_trail.count > 12) { [_trail.firstObject removeFromSuperview]; [_trail removeObjectAtIndex:0]; }
    [UIView animateWithDuration:0.32 animations:^{ d.alpha = 0; d.transform = CGAffineTransformMakeScale(0.2, 0.2); } completion:^(BOOL f) {
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
- (void)toggleVisible {
    _shown = _visible.on;
    _cursor.hidden = !_shown;
}
- (void)sizeChanged { _scale = _size.value; [self placeCursor]; }
- (void)speedChanged { _accel = _speed.value; }
- (void)pickShape:(UIButton *)b {
    _shape = (PuckShape)b.tag;
    _cursor.shape = _shape;
    [_cursor setNeedsDisplay];
    [self markChips];
}
- (void)pickDesk:(UIButton *)b {
    _desk = (PuckDesk)b.tag;
    _stage.desk = _desk;
    [self markChips];
}
- (void)systemPointer {
    BOOL ok = PuckTryAssistiveTouch(YES);
    if (!ok) PuckOpenAssistiveTouchSettings();
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

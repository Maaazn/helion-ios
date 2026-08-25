// Helion.m — original iOS host. QEMU is a separate GPL-2.0 binary in the bundle.
#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <spawn.h>
#import <signal.h>
#import <sys/stat.h>
#import <sys/wait.h>
#import <unistd.h>

extern char **environ;

@interface HelionStore : NSObject
+ (NSString *)root;
+ (NSString *)isoPath;
+ (NSString *)isoHint;
+ (BOOL)isoPresent;
+ (BOOL)installISOFromURL:(NSURL *)url error:(NSError **)error;
@end

@implementation HelionStore
+ (NSString *)root {
    NSString *docs = NSSearchPathForDirectoriesInDomains(
        NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *root = [docs stringByAppendingPathComponent:@"Helion"];
    [[NSFileManager defaultManager] createDirectoryAtPath:root
        withIntermediateDirectories:YES attributes:nil error:nil];
    return root;
}
+ (NSString *)isoPath {
    return [[self root] stringByAppendingPathComponent:@"guest.iso"];
}
+ (NSString *)isoHint {
    FILE *f = fopen([self isoPath].fileSystemRepresentation, "rb");
    if (!f) return @"none";
    char buf[32768];
    size_t n = fread(buf, 1, sizeof(buf), f);
    fclose(f);
    NSData *d = [NSData dataWithBytes:buf length:n];
    NSString *ascii = [[NSString alloc] initWithData:d encoding:NSISOLatin1StringEncoding] ?: @"";
    if ([ascii containsString:@"EFI"] && [ascii containsString:@"BOOT"])
        return @"uefi";
    if (n > 0x8001 && buf[0x8001] == 'C' && buf[0x8002] == 'D')
        return @"iso9660";
    return @"blob";
}
+ (BOOL)installISOFromURL:(NSURL *)url error:(NSError **)error {
    NSURL *dest = [NSURL fileURLWithPath:[self isoPath]];
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm removeItemAtURL:dest error:nil];
    BOOL acc = [url startAccessingSecurityScopedResource];
    BOOL ok = [fm linkItemAtURL:url toURL:dest error:error];
    if (!ok) {
        if (error) *error = nil;
        ok = [fm copyItemAtURL:url toURL:dest error:error];
    }
    if (acc) [url stopAccessingSecurityScopedResource];
    return ok;
}
@end

@interface HelionQEMU : NSObject
+ (instancetype)shared;
+ (NSString *)x86;
+ (NSString *)arm;
+ (BOOL)hasX86;
+ (BOOL)hasARM;
+ (NSString *)version;
- (void)startWithLog:(void (^)(NSString *))log done:(void (^)(NSString *))done;
- (void)stop;
@end

@implementation HelionQEMU {
    pid_t _pid;
}
+ (instancetype)shared {
    static HelionQEMU *g;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ g = [HelionQEMU new]; });
    return g;
}
+ (NSString *)x86 {
    return [[[NSBundle mainBundle] bundlePath]
        stringByAppendingPathComponent:@"qemu-system-x86_64"];
}
+ (NSString *)arm {
    return [[[NSBundle mainBundle] bundlePath]
        stringByAppendingPathComponent:@"qemu-system-aarch64"];
}
+ (BOOL)exists:(NSString *)p {
    struct stat st;
    return p && stat(p.fileSystemRepresentation, &st) == 0 && (st.st_mode & S_IXUSR);
}
+ (BOOL)hasX86 { return [self exists:[self x86]]; }
+ (BOOL)hasARM { return [self exists:[self arm]]; }
+ (NSString *)version {
    NSString *bin = [self hasX86] ? [self x86] : [self arm];
    if (![self exists:bin]) return @"qemu-system not in this IPA\n";
    int fds[2];
    if (pipe(fds) != 0) return @"pipe failed\n";
    posix_spawn_file_actions_t a;
    posix_spawn_file_actions_init(&a);
    posix_spawn_file_actions_adddup2(&a, fds[1], STDOUT_FILENO);
    posix_spawn_file_actions_adddup2(&a, fds[1], STDERR_FILENO);
    posix_spawn_file_actions_addclose(&a, fds[0]);
    posix_spawn_file_actions_addclose(&a, fds[1]);
    char *argv[] = { (char *)bin.fileSystemRepresentation, (char *)"-version", NULL };
    pid_t pid = 0;
    int rc = posix_spawn(&pid, bin.fileSystemRepresentation, &a, NULL, argv, environ);
    posix_spawn_file_actions_destroy(&a);
    close(fds[1]);
    if (rc) { close(fds[0]); return [NSString stringWithFormat:@"posix_spawn=%d\n", rc]; }
    NSMutableData *d = [NSMutableData data];
    char buf[512]; ssize_t n;
    while ((n = read(fds[0], buf, sizeof(buf))) > 0) [d appendBytes:buf length:(NSUInteger)n];
    close(fds[0]);
    int st = 0; waitpid(pid, &st, 0);
    NSString *o = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
    return o.length ? o : @"(no output)\n";
}
- (void)stop {
    if (_pid > 0) {
        kill(_pid, SIGTERM);
        usleep(150000);
        kill(_pid, SIGKILL);
        waitpid(_pid, NULL, WNOHANG);
        _pid = 0;
    }
}
- (void)startWithLog:(void (^)(NSString *))log done:(void (^)(NSString *))done {
    [self stop];
    BOOL x86 = [HelionQEMU hasX86];
    BOOL preferARM = [HelionQEMU hasARM] && [[HelionStore isoHint] isEqualToString:@"blob"];
    if (preferARM && [HelionQEMU hasARM])
        x86 = NO;
    if (!x86 && ![HelionQEMU hasARM])
        x86 = [HelionQEMU hasX86];
    NSString *bin = x86 ? [HelionQEMU x86] : [HelionQEMU arm];
    if (![HelionQEMU exists:bin]) { if (done) done(@"no qemu-system in IPA"); return; }
    NSMutableArray *args = [NSMutableArray arrayWithObject:bin];
    if (x86) {
        [args addObjectsFromArray:@[@"-machine", @"q35", @"-cpu", @"qemu64",
            @"-accel", @"tcg", @"-m", @"768", @"-smp", @"1",
            @"-nographic", @"-no-reboot", @"-monitor", @"none"]];
        NSString *fw = [[[NSBundle mainBundle] bundlePath]
            stringByAppendingPathComponent:@"OSX-KVM"];
        NSString *code = [fw stringByAppendingPathComponent:@"OVMF_CODE_4M.fd"];
        NSString *varsSrc = [fw stringByAppendingPathComponent:@"OVMF_VARS.fd"];
        NSString *work = [[HelionStore root] stringByAppendingPathComponent:@"run"];
        [[NSFileManager defaultManager] createDirectoryAtPath:work
            withIntermediateDirectories:YES attributes:nil error:nil];
        NSString *vars = [work stringByAppendingPathComponent:@"OVMF_VARS.fd"];
        if ([[NSFileManager defaultManager] fileExistsAtPath:varsSrc]) {
            [[NSFileManager defaultManager] removeItemAtPath:vars error:nil];
            [[NSFileManager defaultManager] copyItemAtPath:varsSrc toPath:vars error:nil];
        }
        if ([[NSFileManager defaultManager] fileExistsAtPath:code]) {
            [args addObject:@"-drive"];
            [args addObject:[NSString stringWithFormat:
                @"if=pflash,format=raw,readonly=on,file=%@", code]];
            [args addObject:@"-drive"];
            [args addObject:[NSString stringWithFormat:
                @"if=pflash,format=raw,file=%@", vars]];
        }
        NSString *oc = [fw stringByAppendingPathComponent:@"OpenCore.qcow2"];
        if ([[NSFileManager defaultManager] fileExistsAtPath:oc]) {
            [args addObject:@"-drive"];
            [args addObject:[NSString stringWithFormat:
                @"if=ide,format=qcow2,file=%@,index=0", oc]];
        }
    } else {
        [args addObjectsFromArray:@[@"-machine", @"virt", @"-cpu", @"max",
            @"-accel", @"tcg", @"-m", @"768", @"-nographic", @"-monitor", @"none"]];
    }
    if ([HelionStore isoPresent]) {
        [args addObject:@"-cdrom"];
        [args addObject:[HelionStore isoPath]];
    }
    if (log) log([args componentsJoinedByString:@" "]);
    int fds[2];
    if (pipe(fds) != 0) { if (done) done(@"pipe failed"); return; }
    posix_spawn_file_actions_t a;
    posix_spawn_file_actions_init(&a);
    posix_spawn_file_actions_adddup2(&a, fds[1], STDOUT_FILENO);
    posix_spawn_file_actions_adddup2(&a, fds[1], STDERR_FILENO);
    posix_spawn_file_actions_addclose(&a, fds[0]);
    posix_spawn_file_actions_addclose(&a, fds[1]);
    char **argv = calloc(args.count + 1, sizeof(char *));
    for (NSUInteger i = 0; i < args.count; i++)
        argv[i] = (char *)[args[i] fileSystemRepresentation];
    pid_t pid = 0;
    int rc = posix_spawn(&pid, bin.fileSystemRepresentation, &a, NULL, argv, environ);
    posix_spawn_file_actions_destroy(&a);
    close(fds[1]);
    free(argv);
    if (rc) { close(fds[0]); if (done) done([NSString stringWithFormat:@"posix_spawn=%d", rc]); return; }
    _pid = pid;
    int fd = fds[0];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        char buf[1024]; ssize_t n;
        while ((n = read(fd, buf, sizeof(buf) - 1)) > 0) {
            buf[n] = 0;
            NSString *c = [NSString stringWithUTF8String:buf];
            if (!c) c = [[NSString alloc] initWithBytes:buf length:(NSUInteger)n encoding:NSISOLatin1StringEncoding];
            if (log && c.length) {
                NSString *line = c;
                dispatch_async(dispatch_get_main_queue(), ^{ log(line); });
            }
        }
        int st = 0; waitpid(pid, &st, 0);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self->_pid == pid) self->_pid = 0;
            if (done) done([NSString stringWithFormat:@"exit %d", st]);
        });
    });
}
@end

@interface HelionRoot : UIViewController <UIDocumentPickerDelegate>
@end
@implementation HelionRoot {
    UITextView *_log;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithWhite:0.06 alpha:1];
    self.title = @"Helion";
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
        initWithTitle:@"Add ISO" style:UIBarButtonItemStylePlain
        target:self action:@selector(addISO)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithTitle:@"Start" style:UIBarButtonItemStyleDone
        target:self action:@selector(start)];
    UIBarButtonItem *stop = [[UIBarButtonItem alloc]
        initWithTitle:@"Stop" style:UIBarButtonItemStylePlain
        target:self action:@selector(stop)];
    self.navigationItem.rightBarButtonItems = @[ self.navigationItem.rightBarButtonItem, stop ];

    _log = [[UITextView alloc] init];
    _log.editable = NO;
    _log.backgroundColor = [UIColor colorWithWhite:0.04 alpha:1];
    _log.textColor = [UIColor colorWithRed:0.7 green:0.95 blue:0.75 alpha:1];
    _log.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    _log.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_log];
    [NSLayoutConstraint activateConstraints:@[
        [_log.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [_log.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_log.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_log.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
    [self banner];
}
- (void)banner {
    NSMutableString *s = [NSMutableString string];
    [s appendString:@"Helion\n\n"];
    [s appendFormat:@"qemu-system-x86_64: %@\n", [HelionQEMU hasX86] ? @"YES" : @"NO"];
    [s appendFormat:@"qemu-system-aarch64: %@\n", [HelionQEMU hasARM] ? @"YES" : @"NO"];
    [s appendFormat:@"ISO: %@\n\n", [HelionStore isoPresent] ? [HelionStore isoPath].lastPathComponent : @"none — Add ISO"];
    [s appendString:[HelionQEMU version]];
    [s appendString:@"\nTCG, 768 MB, serial. Attach StikDebug for JIT.\n"];
    _log.text = s;
}
- (void)append:(NSString *)t {
    if (!t.length) return;
    NSString *n = [(_log.text ?: @"") stringByAppendingString:t];
    if (n.length > 90000) n = [n substringFromIndex:n.length - 90000];
    _log.text = n;
    [_log scrollRangeToVisible:NSMakeRange(n.length - 1, 1)];
}
- (void)addISO {
    UTType *iso = [UTType typeWithFilenameExtension:@"iso"];
    NSArray *types = iso ? @[iso, UTTypeData] : @[UTTypeData];
    UIDocumentPickerViewController *p =
        [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:types];
    p.delegate = self;
    [self presentViewController:p animated:YES completion:nil];
}
- (void)documentPicker:(UIDocumentPickerViewController *)c
didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSError *err = nil;
    BOOL ok = [HelionStore installISOFromURL:urls.firstObject error:&err];
    [self append:ok ? @"\nISO saved as guest.iso\n" :
        [NSString stringWithFormat:@"\nISO failed: %@\n", err.localizedDescription]];
}
- (void)start {
    [self append:@"\n— start —\n"];
    __weak HelionRoot *me = self;
    [[HelionQEMU shared] startWithLog:^(NSString *line) {
        [me append:line];
    } done:^(NSString *st) {
        [me append:[NSString stringWithFormat:@"\n— %@ —\n", st]];
    }];
}
- (void)stop {
    [[HelionQEMU shared] stop];
    [self append:@"\n— stop —\n"];
}
@end

@interface HelionAppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end
@implementation HelionAppDelegate
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)opt {
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    HelionRoot *root = [HelionRoot new];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:root];
    nav.navigationBar.barStyle = UIBarStyleBlack;
    nav.navigationBar.translucent = NO;
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

#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <dlfcn.h>
#import <sys/sysctl.h>
#import <signal.h>
#import <ServiceManagement/ServiceManagement.h>
#import <sys/socket.h>
#import <sys/un.h>
#import <sys/file.h>
#import <fcntl.h>
#import <unistd.h>
#import <errno.h>

typedef int32_t (*SBMainConnectionFn)(void);
typedef void (*SBOverrideFn)(int32_t, CGDirectDisplayID, bool);

static NSString *SBControlPath(void) { return [NSString stringWithFormat:@"/tmp/smartbarhide-%u.sock", getuid()]; }
static int SBSendCommand(const char *command) {
    int fd = socket(AF_UNIX, SOCK_STREAM, 0); if (fd < 0) return 2;
    struct sockaddr_un address = {.sun_family = AF_UNIX}; strlcpy(address.sun_path, SBControlPath().fileSystemRepresentation, sizeof(address.sun_path));
    if (connect(fd, (struct sockaddr *)&address, sizeof(address)) != 0) { close(fd); fprintf(stderr, "SmartBarHide is not running.\n"); return 2; }
    uid_t uid = 0; gid_t gid = 0; if (getpeereid(fd, &uid, &gid) != 0 || uid != getuid()) { close(fd); return 2; }
    char line[64]; int length = snprintf(line, sizeof(line), "%s\n", command);
    if (write(fd, line, (size_t)length) != length) { close(fd); return 2; }
    shutdown(fd, SHUT_WR); char reply[512] = {0}; ssize_t count = read(fd, reply, sizeof(reply)-1); close(fd);
    if (count > 0) fputs(reply, stdout); return count > 0 ? 0 : 2;
}

@interface SBPrivateAPI : NSObject
@property(nonatomic, readonly) BOOL supported;
@property(nonatomic, readonly) NSString *reason;
- (BOOL)setVisible:(BOOL)visible display:(CGDirectDisplayID)display;
@end

@implementation SBPrivateAPI {
    void *_sky;
    SBMainConnectionFn _mainConnection;
    SBOverrideFn _override;
    int32_t _connection;
}
- (instancetype)init {
    if ((self = [super init])) {
        char build[128] = {0}; size_t size = sizeof(build);
        sysctlbyname("kern.osversion", build, &size, NULL, 0);
        size_t archSize = 0; sysctlbyname("hw.machine", NULL, &archSize, NULL, 0);
        char machine[64] = {0}; if (archSize > 0 && archSize < sizeof(machine)) sysctlbyname("hw.machine", machine, &archSize, NULL, 0);
        NSString *arch = [NSString stringWithUTF8String:machine] ?: @"unknown";
        if ((strcmp(build, "25G83") != 0 && strcmp(build, "26A428") != 0) || ![arch hasPrefix:@"arm64"]) {
            NSLog(@"Warning: Untested macOS version (found %s %s); continuing anyway.", arch.UTF8String, build);
        }
        _sky = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW | RTLD_LOCAL);
        _mainConnection = (SBMainConnectionFn)dlsym(_sky, "SLSMainConnectionID");
        _override = (SBOverrideFn)dlsym(_sky, "SLSSetMenuBarVisibilityOverrideOnDisplay");
        if (!_sky || !_mainConnection || !_override) { _reason = @"Required private SkyLight symbols are unavailable."; return self; }
        _connection = _mainConnection();
        if (!_connection) { _reason = @"SkyLight did not provide a main connection."; return self; }
        _supported = YES;
    }
    return self;
}
- (BOOL)setVisible:(BOOL)visible display:(CGDirectDisplayID)display {
    if (!_supported || !display) return NO;
    _override(_connection, display, visible);
    return YES;
}
- (void)dealloc { if (_sky) dlclose(_sky); }
@end

@interface SBTarget : NSObject
@property CGDirectDisplayID displayID;
@property(nonatomic, copy) NSString *name;
@property(nonatomic, copy) NSString *uuid;
@end
@implementation SBTarget @end

static NSArray<SBTarget *> *SBDisplays(void) {
    uint32_t count = 0; CGDirectDisplayID ids[32];
    if (CGGetOnlineDisplayList(32, ids, &count) != kCGErrorSuccess || count == 0 || count >= 32) return @[];
    NSMutableArray *result = [NSMutableArray array];
    for (uint32_t i = 0; i < count; i++) {
        CGDirectDisplayID did = ids[i]; NSScreen *screen = nil;
        for (NSScreen *candidate in NSScreen.screens)
            if ([candidate.deviceDescription[@"NSScreenNumber"] unsignedIntValue] == did) { screen = candidate; break; }
        if (!screen || !CGDisplayIsActive(did) || CGDisplayIsInMirrorSet(did)) continue;
        SBTarget *target = [SBTarget new]; target.displayID = did; target.name = screen.localizedName ?: @"Built-in display";
        CFUUIDRef uuid = CGDisplayCreateUUIDFromDisplayID(did);
        if (uuid) { target.uuid = CFBridgingRelease(CFUUIDCreateString(NULL, uuid)); CFRelease(uuid); }
        [result addObject:target];
    }
    return result;
}

@interface SBSettingsController : NSWindowController <NSWindowDelegate>
@property(nonatomic, copy) void (^closeHandler)(void);
@property(nonatomic, copy) void (^toggleHandler)(NSString *, BOOL);
@property(nonatomic, copy) void (^loginHandler)(BOOL);
- (void)updateDisplays:(NSArray<SBTarget *> *)displays values:(NSDictionary<NSString *, NSNumber *> *)values status:(NSString *)status;
- (void)updateLaunchAtLogin:(BOOL)enabled;
@end

@implementation SBSettingsController {
    NSStackView *_rows; NSTextField *_status; NSButton *_login;
}
- (instancetype)init {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 500, 340)
        styleMask:(NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable)
        backing:NSBackingStoreBuffered defer:NO];
    if ((self = [super initWithWindow:window])) {
        window.title = @"SmartBarHide Settings"; window.delegate = self; window.releasedWhenClosed = NO;
        NSView *content = window.contentView;
        NSTextField *title = [NSTextField labelWithString:@"SmartBarHide"]; title.font = [NSFont boldSystemFontOfSize:24];
        NSString *appVersion = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"Unknown";
        NSTextField *version = [NSTextField labelWithString:[@"Version " stringByAppendingString:appVersion]];
        version.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize]; version.textColor = NSColor.secondaryLabelColor;
        NSTextField *subtitle = [NSTextField labelWithString:@"Choose which detected displays keep their real menu bar visible."]; subtitle.textColor = NSColor.secondaryLabelColor;
        _status = [NSTextField labelWithString:@"Starting…"]; _status.textColor = NSColor.secondaryLabelColor;
        _rows = [NSStackView new]; _rows.orientation = NSUserInterfaceLayoutOrientationVertical; _rows.alignment = NSLayoutAttributeLeading; _rows.spacing = 10;
        _login = [NSButton checkboxWithTitle:@"Launch at login" target:self action:@selector(toggleLogin:)];
        NSButton *reset = [NSButton buttonWithTitle:@"Disable and Reset" target:self action:@selector(disable:)];
        NSButton *quit = [NSButton buttonWithTitle:@"Quit SmartBarHide" target:NSApp action:@selector(terminate:)];
        for (NSView *v in @[title, version, subtitle, _rows, _status, _login, reset, quit]) { v.translatesAutoresizingMaskIntoConstraints = NO; [content addSubview:v]; }
        [NSLayoutConstraint activateConstraints:@[
            [title.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:28], [title.topAnchor constraintEqualToAnchor:content.topAnchor constant:28],
            [version.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-28], [version.firstBaselineAnchor constraintEqualToAnchor:title.firstBaselineAnchor],
            [version.leadingAnchor constraintGreaterThanOrEqualToAnchor:title.trailingAnchor constant:16],
            [subtitle.leadingAnchor constraintEqualToAnchor:title.leadingAnchor], [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:6],
            [_rows.leadingAnchor constraintEqualToAnchor:title.leadingAnchor], [_rows.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-28], [_rows.topAnchor constraintEqualToAnchor:subtitle.bottomAnchor constant:28],
            [_status.leadingAnchor constraintEqualToAnchor:title.leadingAnchor], [_status.topAnchor constraintEqualToAnchor:_rows.bottomAnchor constant:15],
            [_login.leadingAnchor constraintEqualToAnchor:title.leadingAnchor], [_login.topAnchor constraintEqualToAnchor:_status.bottomAnchor constant:12],
            [reset.leadingAnchor constraintEqualToAnchor:title.leadingAnchor], [reset.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-24],
            [quit.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-28], [quit.centerYAnchor constraintEqualToAnchor:reset.centerYAnchor]
        ]];
    }
    return self;
}
- (void)toggle:(NSButton *)sender { if (self.toggleHandler) self.toggleHandler(sender.identifier, sender.state == NSControlStateValueOn); }
- (void)toggleLogin:(NSButton *)sender { if (self.loginHandler) self.loginHandler(sender.state == NSControlStateValueOn); }
- (void)disable:(id)sender { for (NSButton *button in _rows.arrangedSubviews) { button.state = NSControlStateValueOff; if (self.toggleHandler) self.toggleHandler(button.identifier, NO); } }
- (void)updateDisplays:(NSArray<SBTarget *> *)displays values:(NSDictionary<NSString *,NSNumber *> *)values status:(NSString *)status {
    for (NSView *view in [_rows.arrangedSubviews copy]) [_rows removeArrangedSubview:view], [view removeFromSuperview];
    for (SBTarget *display in displays) { NSButton *button = [NSButton checkboxWithTitle:display.name target:self action:@selector(toggle:)]; button.identifier = display.name; button.state = values[display.name].boolValue ? NSControlStateValueOn : NSControlStateValueOff; [_rows addArrangedSubview:button]; }
    _status.stringValue = status ?: @""; self.window.contentView.needsLayout = YES;
}
- (void)updateLaunchAtLogin:(BOOL)enabled { _login.state = enabled ? NSControlStateValueOn : NSControlStateValueOff; }
- (void)windowWillClose:(NSNotification *)n { if (_closeHandler) _closeHandler(); }
@end

@interface SBAppDelegate : NSObject <NSApplicationDelegate>
@property(nonatomic) SBPrivateAPI *api;
@property(nonatomic) NSArray<SBTarget *> *displays;
@property(nonatomic) SBSettingsController *settings;
@property(nonatomic) NSMutableDictionary<NSString *, NSNumber *> *desiredByName;
@property(nonatomic) NSMutableDictionary<NSString *, SBTarget *> *appliedByName;
@property(nonatomic) dispatch_source_t terminationSignal;
@property(nonatomic) BOOL screenRefreshScheduled;
@property(nonatomic, copy) NSString *loginMessage;
@property(nonatomic) int controlSocket;
@property(nonatomic) int lockFD;
@property(nonatomic) dispatch_source_t controlSource;
@end

@implementation SBAppDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)n {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    self.desiredByName = [NSMutableDictionary dictionaryWithDictionary:[[NSUserDefaults standardUserDefaults] dictionaryForKey:@"displaySettings"] ?: @{}];
    self.appliedByName = [NSMutableDictionary dictionary];
    self.lockFD = open([NSString stringWithFormat:@"/tmp/smartbarhide-%u.lock", getuid()].fileSystemRepresentation, O_CREAT|O_RDWR|O_CLOEXEC, 0600);
    if (self.lockFD < 0 || flock(self.lockFD, LOCK_EX|LOCK_NB) != 0) { [NSApp terminate:nil]; return; }
    self.controlSocket = socket(AF_UNIX, SOCK_STREAM, 0);
    struct sockaddr_un address = {.sun_family = AF_UNIX}; unlink(SBControlPath().fileSystemRepresentation); strlcpy(address.sun_path, SBControlPath().fileSystemRepresentation, sizeof(address.sun_path));
    if (self.controlSocket >= 0 && bind(self.controlSocket, (struct sockaddr *)&address, sizeof(address)) == 0 && listen(self.controlSocket, 8) == 0) {
        self.controlSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, self.controlSocket, 0, dispatch_get_main_queue());
        __weak typeof(self) weakSelf = self;
        dispatch_source_set_event_handler(self.controlSource, ^{ [weakSelf acceptCommands]; }); dispatch_resume(self.controlSource);
    }
    self.api = [SBPrivateAPI new];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(screenChanged:) name:NSApplicationDidChangeScreenParametersNotification object:nil];
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self selector:@selector(willSleep:) name:NSWorkspaceWillSleepNotification object:nil];
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self selector:@selector(didWake:) name:NSWorkspaceDidWakeNotification object:nil];
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self selector:@selector(wakeRefresh:) name:NSWorkspaceScreensDidWakeNotification object:nil];
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self selector:@selector(wakeRefresh:) name:NSWorkspaceSessionDidBecomeActiveNotification object:nil];
    signal(SIGTERM, SIG_IGN); signal(SIGINT, SIG_IGN);
    self.terminationSignal = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, SIGTERM, 0, dispatch_get_main_queue());
    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(self.terminationSignal, ^{ [weakSelf terminateNormally]; });
    dispatch_resume(self.terminationSignal);
    [self reconcile];
}
- (void)applicationWillBecomeActive:(NSNotification *)n { /* Explicit reopen is handled by applicationShouldHandleReopen. */ }
- (BOOL)applicationShouldHandleReopen:(NSApplication *)app hasVisibleWindows:(BOOL)flag { [self showSettings]; return YES; }
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender { return NO; }
- (void)showSettings {
    if (!self.settings) {
        self.settings = [SBSettingsController new]; __weak typeof(self) weakSelf = self;
        self.settings.closeHandler = ^{ [weakSelf hideSettings]; };
        self.settings.toggleHandler = ^(NSString *name, BOOL enabled) { [weakSelf setDisplay:name enabled:enabled]; };
        self.settings.loginHandler = ^(BOOL enabled) { [weakSelf setLaunchAtLogin:enabled]; };
    }
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    [self.settings showWindow:nil]; [self.settings.window center]; [NSApp activateIgnoringOtherApps:YES];
    [self updateSettings];
}
- (void)acceptCommands {
    int client = accept(self.controlSocket, NULL, NULL); if (client < 0) return;
    uid_t uid = 0; gid_t gid = 0; char command[128] = {0}; ssize_t count = 0;
    if (!getpeereid(client, &uid, &gid) && uid == getuid()) count = read(client, command, sizeof(command)-1);
    if (count > 0) {
        command[strcspn(command, "\r\n")] = 0; NSString *request = [NSString stringWithUTF8String:command] ?: @""; NSString *reply = @"ok\n";
        if ([request isEqualToString:@"settings"]) [self showSettings];
        else if ([request isEqualToString:@"enable"]) { for (SBTarget *display in self.displays) [self setDisplay:display.name enabled:YES]; }
        else if ([request isEqualToString:@"disable"]) { for (SBTarget *display in self.displays) [self setDisplay:display.name enabled:NO]; }
        else if ([request isEqualToString:@"quit"]) { [NSApp terminate:nil]; }
        else if ([request isEqualToString:@"status"]) reply = [NSString stringWithFormat:@"supported=%d displays=%lu socket=%@\n", self.api.supported, (unsigned long)self.displays.count, SBControlPath()];
        else reply = @"error unknown-command\n";
        (void)write(client, reply.UTF8String, [reply lengthOfBytesUsingEncoding:NSUTF8StringEncoding]);
    }
    close(client);
}
- (void)hideSettings { [self.settings.window orderOut:nil]; [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory]; }
- (void)updateSettings {
    NSString *status = self.api.supported ? (self.displays.count ? [NSString stringWithFormat:@"%lu active display%@ detected", (unsigned long)self.displays.count, self.displays.count == 1 ? @"" : @"s"] : @"Waiting for an active display") : self.api.reason;
    if (self.loginMessage.length) status = [status stringByAppendingFormat:@" %@", self.loginMessage];
    [self.settings updateDisplays:self.displays values:self.desiredByName status:status];
    SMAppServiceStatus loginStatus = SMAppService.mainAppService.status;
    [self.settings updateLaunchAtLogin:(loginStatus == SMAppServiceStatusEnabled || loginStatus == SMAppServiceStatusRequiresApproval)];
}
- (void)setLaunchAtLogin:(BOOL)enabled {
    NSError *error = nil; BOOL ok = enabled ? [SMAppService.mainAppService registerAndReturnError:&error] : [SMAppService.mainAppService unregisterAndReturnError:&error];
    self.loginMessage = ok ? @"" : [NSString stringWithFormat:@"Launch-at-login: %@", error.localizedDescription ?: @"request failed"];
    [self updateSettings];
}
- (void)setDisplay:(NSString *)name enabled:(BOOL)enabled { self.desiredByName[name] = @(enabled); [[NSUserDefaults standardUserDefaults] setObject:self.desiredByName forKey:@"displaySettings"]; [self reconcile]; [self updateSettings]; }
- (void)reconcile {
    self.displays = SBDisplays();
    NSMutableSet *liveNames = [NSMutableSet set];
    for (SBTarget *display in self.displays) {
        [liveNames addObject:display.name];
        if (!self.desiredByName[display.name]) self.desiredByName[display.name] = @(CGDisplayIsBuiltin(display.displayID));
    }
    for (NSString *name in [self.appliedByName.allKeys copy]) if (![liveNames containsObject:name] || !self.desiredByName[name].boolValue) {
        SBTarget *old = self.appliedByName[name]; if (old) [self.api setVisible:NO display:old.displayID]; [self.appliedByName removeObjectForKey:name];
    }
    for (SBTarget *display in self.displays) if (self.desiredByName[display.name].boolValue && !self.appliedByName[display.name] && self.api.supported) {
        if ([self.api setVisible:YES display:display.displayID]) self.appliedByName[display.name] = display;
    }
    [[NSUserDefaults standardUserDefaults] setObject:self.desiredByName forKey:@"displaySettings"];
    [self updateSettings];
}
- (void)screenChanged:(NSNotification *)n {
    // Display changes can invalidate these per-display overrides; screen and
    // session wake may do the same. Coalesce the event burst, discard the stale
    // applied cache, and reapply saved states to the fresh display list.
    if (self.screenRefreshScheduled) return;
    self.screenRefreshScheduled = YES;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        weakSelf.screenRefreshScheduled = NO;
        [weakSelf.appliedByName removeAllObjects];
        [weakSelf reconcile];
    });
}
- (void)willSleep:(NSNotification *)n { for (SBTarget *display in self.appliedByName.allValues) [self.api setVisible:NO display:display.displayID]; [self.appliedByName removeAllObjects]; }
- (void)didWake:(NSNotification *)n { [self screenChanged:n]; }
- (void)wakeRefresh:(NSNotification *)n { [self screenChanged:n]; }
- (void)terminateNormally { if (NSApp.isRunning) [NSApp terminate:nil]; }
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender { for (SBTarget *display in self.appliedByName.allValues) [self.api setVisible:NO display:display.displayID]; [self.appliedByName removeAllObjects]; return NSTerminateNow; }
- (void)dealloc { if (self.terminationSignal) dispatch_source_cancel(self.terminationSignal); if (self.controlSource) dispatch_source_cancel(self.controlSource); if (self.controlSocket >= 0) { close(self.controlSocket); unlink(SBControlPath().fileSystemRepresentation); } if (self.lockFD >= 0) close(self.lockFD); [[NSNotificationCenter defaultCenter] removeObserver:self]; [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:self]; }
@end

int main(int argc, const char **argv) {
    @autoreleasepool {
        if (argc > 1) {
            const char *command = NULL;
            if (!strcmp(argv[1], "--settings")) command = "settings";
            else if (!strcmp(argv[1], "--status")) command = "status";
            else if (!strcmp(argv[1], "--enable")) command = "enable";
            else if (!strcmp(argv[1], "--disable")) command = "disable";
            else if (!strcmp(argv[1], "--quit")) command = "quit";
            else { fprintf(stderr, "Usage: SmartBarHide [--settings|--status|--enable|--disable|--quit]\n"); return 2; }
            return SBSendCommand(command);
        }
        NSApplication *app = NSApplication.sharedApplication; SBAppDelegate *delegate = [SBAppDelegate new]; app.delegate = delegate;
        [app run];
    }
    return 0;
}

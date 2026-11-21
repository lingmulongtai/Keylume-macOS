#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>

// Resolve the macOS 26 class at runtime so older SDKs can build this target.
@protocol KeylumeGlassView
@property CGFloat cornerRadius;
@end

static NSView *mainMaterial(NSRect frame) {
    if (@available(macOS 26.0, *)) {
        Class glassClass = NSClassFromString(@"NSGlassEffectView");
        if (glassClass) {
            NSView<KeylumeGlassView> *glass = [[glassClass alloc] initWithFrame:frame];
            glass.cornerRadius = 0; // The window frame supplies the outer corners.
            return glass;
        }
    }
    NSVisualEffectView *effect = [[NSVisualEffectView alloc] initWithFrame:frame];
    effect.material = NSVisualEffectMaterialUnderWindowBackground;
    effect.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    return effect;
}

@interface KeylumeMaterialHost : NSView
- (void)updateMaterial;
@end

@implementation KeylumeMaterialHost {
    id _observer;
    BOOL _initialized;
    BOOL _reduced;
}

- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        __weak KeylumeMaterialHost *host = self;
        _observer = [NSWorkspace.sharedWorkspace.notificationCenter
            addObserverForName:NSWorkspaceAccessibilityDisplayOptionsDidChangeNotification
                        object:nil queue:NSOperationQueue.mainQueue
                    usingBlock:^(__unused NSNotification *note) { [host updateMaterial]; }];
    }
    return self;
}

- (void)dealloc {
    if (_observer) [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:_observer];
}

- (NSView *)hitTest:(NSPoint)point {
    return nil;
}

- (void)updateMaterial {
    NSWindow *window = self.window;
    BOOL reduced = NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceTransparency;
    if (!window || (_initialized && _reduced == reduced)) return;
    _initialized = YES;
    _reduced = reduced;
    [self.subviews.firstObject removeFromSuperview];

    window.opaque = reduced;
    window.backgroundColor = reduced ? NSColor.windowBackgroundColor : NSColor.clearColor;
    if (!reduced) {
        NSView *effect = mainMaterial(self.bounds);
        effect.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        [self addSubview:effect];
    }
}
@end

void keylume_install_main_material(WKWebView *webview) {
    NSView *parent = webview.superview;
    if (!parent || !webview.window) return;
    for (NSView *sibling in parent.subviews) {
        if ([sibling isKindOfClass:KeylumeMaterialHost.class]) return;
    }
    // Wry's configured background color disables the opaque WebKit page backing.
    webview.underPageBackgroundColor = NSColor.clearColor;
    KeylumeMaterialHost *host = [[KeylumeMaterialHost alloc] initWithFrame:parent.bounds];
    [parent addSubview:host positioned:NSWindowBelow relativeTo:webview];
    [host updateMaterial];
}

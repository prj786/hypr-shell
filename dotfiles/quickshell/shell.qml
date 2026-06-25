import Quickshell

// Quickshell entry point. Built incrementally.
//   - Bar:           top bar (Search… · window · workspaces · status · clock).
//   - Launcher:      centered fuzzy app launcher (Super+D).
//   - Notifications: native notification server + top-right toasts.
//   - QuickSettings: clock → calendar + Do Not Disturb + notifications.
ShellRoot {
    Notifications {}
    Bar {}
    Dock {}
    LauncherPanel {}
    AppStore {}
    Places {}
    TrayMenu {}
    Launcher {}
    QuickSettings {}
    Auth {}
    Clipboard {}
    ScreenshotPreview {}
    AppMenu {}
    Lock {}
    Caffeine {}
    Osd {}
    Overview {}
    Settings {}
    Splash {}
    Battery {}
}

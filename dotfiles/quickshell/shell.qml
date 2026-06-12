import Quickshell

// Quickshell entry point. macOS-style shell, built incrementally.
//   - Bar:           top bar (Search… · window · workspaces · status · clock).
//   - Spotlight:     centered fuzzy app launcher (Super+Space).
//   - Notifications: native notification server + top-right toasts.
//   - ControlCenter: clock → calendar + Do Not Disturb + notifications.
ShellRoot {
    Notifications {}
    Bar {}
    Dock {}
    LauncherPanel {}
    AppStore {}
    Spotlight {}
    ControlCenter {}
    Auth {}
    Clipboard {}
    ScreenshotPreview {}
    AppMenu {}
    Lock {}
    Caffeine {}
    Osd {}
    Overview {}
    Settings {}
}

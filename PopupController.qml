pragma Singleton

// PopupController.qml
// Centralized mutex for "only one popup at a time" + a kill switch
// fired when the user focuses an app window.
//
// Usage from a popup:
//   - On open: PopupController.open(self, () => { /* close me */ })
//   - On any close path: PopupController.closed(self)
//
// Usage from outside (shell.qml on Compositor.windowFocused):
//   - PopupController.closeAll()
//
// Identity is the popup object reference, not a string id, so multiple
// instances of the same popup type (one per monitor) don't collide.
//
// All actual closing happens inside Qt.callLater() so we never tear down
// popup state during event delivery (gotcha #30: avoids PopupAnchor SIGSEGV
// in Quickshell 0.2.1).

import QtQuick
import Quickshell

Singleton {
    id: root

    // The popup currently considered "open" (or null). Read by anything
    // that wants to know if a popup is up (e.g. for diagnostics).
    property QtObject activePopup: null

    // Closer for activePopup. We keep it as a property rather than a
    // map because there's only ever one active popup.
    property var activeCloser: null

    // Whether activePopup opted out of closeAll() (see open()'s `sticky`
    // param). Still closed by the mutex itself (opening a second popup
    // always closes the first, sticky or not) — only exempt from the
    // compositor's "focused another window" kill switch.
    property bool activeSticky: false

    // Open a new popup. Closes any previous via Qt.callLater.
    //
    // `sticky`: when true, closeAll() leaves this popup open. For
    // work-session widgets (notes, pomodoro, alarms) that you keep open
    // while glancing at or working in another window — with
    // input:follow_mouse (focus-follows-mouse), that "glance" fires the
    // same windowFocused signal a deliberate click would, so the default
    // (non-sticky) behaviour closed them just from the cursor drifting
    // over another window. Quick-glance popups (volume, media, clipboard)
    // default to non-sticky, where closing on any focus change is the
    // wanted behaviour.
    function open(popup, closer, sticky) {
        if (root.activePopup === popup) {
            // Re-opening the same popup; just refresh closer.
            root.activeCloser = closer;
            root.activeSticky = !!sticky;
            return;
        }
        if (root.activePopup) {
            const prev = root.activeCloser;
            if (prev) Qt.callLater(prev);
        }
        root.activePopup  = popup;
        root.activeCloser = closer;
        root.activeSticky = !!sticky;
    }

    // The popup itself reports it has finished closing.
    function closed(popup) {
        if (root.activePopup === popup) {
            root.activePopup  = null;
            root.activeCloser = null;
            root.activeSticky = false;
        }
    }

    // External "close whatever's open" — used by the compositor focus listener.
    function closeAll() {
        if (!root.activePopup) return;
        if (root.activeSticky) return;
        const closer = root.activeCloser;
        root.activePopup  = null;
        root.activeCloser = null;
        if (closer) Qt.callLater(closer);
    }
}

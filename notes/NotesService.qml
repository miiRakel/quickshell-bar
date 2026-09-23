pragma Singleton

// NotesService.qml
// Quick-capture notes: toggle a small text box from anywhere, jot
// something down, see what you've written before.
//
// Public surface used by NotesPopup + shell.qml IpcHandler:
//   notes: array<{ id, text, ts }>  (newest first)
//   popupOpen: bool                 (drives the popup's visible binding)
//   openPopup() / closePopup() / togglePopup()
//   addNote(text)                   (no-ops on empty/whitespace-only text)
//   removeNote(id)

import QtQuick
import Quickshell
import Quickshell.Io
import qs

Singleton {
    id: root

    property var notes: []
    property bool popupOpen: false

    // ---- Popup control ----

    function openPopup() {
        PopupController.open(root, () => root.popupOpen = false);
        root.popupOpen = true;
    }

    function closePopup() {
        root.popupOpen = false;
        PopupController.closed(root);
    }

    function togglePopup() {
        if (root.popupOpen) closePopup();
        else                openPopup();
    }

    // ---- Notes ----

    function addNote(text) {
        const trimmed = (text || "").trim();
        if (!trimmed) return;
        const entry = {
            id: Date.now().toString(36) + Math.random().toString(36).slice(2, 6),
            text: trimmed,
            ts: Date.now()
        };
        root.notes = [entry, ...root.notes];
        _save();
    }

    function removeNote(id) {
        root.notes = root.notes.filter(n => n.id !== id);
        _save();
    }

    // Quote a string for safe inclusion in a single-quoted bash arg.
    function _q(s) {
        return "'" + String(s).replace(/'/g, "'\\''") + "'";
    }

    function copyNote(text) {
        copyProc.command = ["sh", "-c", "printf '%s' " + _q(text) + " | wl-copy"];
        copyProc.running = true;
    }

    Process {
        id: copyProc
        running: false
    }

    // ---- Persistence ----

    FileView {
        id: notesFile
        path: Quickshell.statePath("notes.json")
        watchChanges: false
        printErrors: true
        onLoaded: {
            try {
                const t = notesFile.text();
                const parsed = (t && t.length > 0) ? JSON.parse(t) : [];
                root.notes = Array.isArray(parsed) ? parsed : [];
            } catch (e) {
                console.warn("[NotesService] notes parse error:", e);
                root.notes = [];
            }
        }
        onLoadFailed: function(err) {
            // No existing file is the normal case on first run. Start empty.
            root.notes = [];
        }
    }

    function _save() {
        try {
            notesFile.setText(JSON.stringify(root.notes));
        } catch (e) {
            console.warn("[NotesService] notes save error:", e);
        }
    }
}

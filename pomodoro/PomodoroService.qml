pragma Singleton

// PomodoroService.qml
// Classic work/break interval timer. Auto-advances through phases
// (work → short break → ... → long break after N work sessions) and
// plays a sound + notification at every transition.
//
// A separate module from alarms/notes on purpose — same reasoning as
// alarms: its own service, its own storage file, removable on its own.
//
// Public surface used by PomodoroPopup + shell.qml IpcHandler:
//   phase: "idle" | "work" | "shortBreak" | "longBreak"
//   running: bool
//   remainingSeconds: int
//   completedWorkSessions: int   (resets to 0 after each long break)
//   workMinutes / shortBreakMinutes / longBreakMinutes / sessionsUntilLongBreak
//   popupOpen: bool
//   openPopup() / closePopup() / togglePopup()
//   start() / pause() / reset() / skip()
//   setDurations(work, shortBreak, longBreak, sessionsUntilLongBreak)

import QtQuick
import Quickshell
import Quickshell.Io
import qs

Singleton {
    id: root

    property string phase: "idle"
    property bool running: false
    property int remainingSeconds: 0
    property int completedWorkSessions: 0

    property int workMinutes: 25
    property int shortBreakMinutes: 5
    property int longBreakMinutes: 15
    property int sessionsUntilLongBreak: 4

    property bool popupOpen: false

    // ---- Popup control ----

    function openPopup() {
        // sticky: true — see NotesService.openPopup() for why.
        PopupController.open(root, () => root.popupOpen = false, true);
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

    // ---- Controls ----

    function start() {
        if (root.phase === "idle") {
            root.phase = "work";
            root.remainingSeconds = root.workMinutes * 60;
        }
        root.running = true;
    }

    function pause() {
        root.running = false;
    }

    function reset() {
        root.running = false;
        root.phase = "idle";
        root.completedWorkSessions = 0;
        root.remainingSeconds = 0;
    }

    // Manually jump to the next phase without waiting the clock out.
    function skip() {
        _advance();
    }

    function setDurations(work, shortBreak, longBreak, sessions) {
        root.workMinutes = work;
        root.shortBreakMinutes = shortBreak;
        root.longBreakMinutes = longBreak;
        root.sessionsUntilLongBreak = sessions;
        _save();
    }

    // ---- Phase transitions ----

    function _advance() {
        if (root.phase === "work") {
            root.completedWorkSessions += 1;
            if (root.completedWorkSessions >= root.sessionsUntilLongBreak) {
                root.completedWorkSessions = 0;
                root.phase = "longBreak";
                root.remainingSeconds = root.longBreakMinutes * 60;
            } else {
                root.phase = "shortBreak";
                root.remainingSeconds = root.shortBreakMinutes * 60;
            }
        } else {
            // Any break (short or long) rolls back into work.
            root.phase = "work";
            root.remainingSeconds = root.workMinutes * 60;
        }
        _notifyPhaseChange();
    }

    function _notifyPhaseChange() {
        soundPlayer.running = true;
        const label = root.phase === "work" ? "Work" :
                      root.phase === "shortBreak" ? "Short break" : "Long break";
        notifyProc.command = ["notify-send", "-u", "normal", "-a", "quickshell-bar",
            "Pomodoro", label + " — go"];
        notifyProc.running = true;
    }

    Timer {
        id: tickTimer
        interval: 1000
        repeat: true
        running: root.running
        onTriggered: {
            if (root.remainingSeconds > 0) {
                root.remainingSeconds -= 1;
            } else {
                root._advance();
            }
        }
    }

    Process {
        id: soundPlayer
        running: false
        command: ["canberra-gtk-play", "-i", "complete", "-d", "quickshell-bar pomodoro"]
        stderr: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                if (line && line.length > 0)
                    console.warn("[PomodoroService] canberra-gtk-play:", line.trim());
            }
        }
    }

    Process {
        id: notifyProc
        running: false
    }

    // ---- Persistence ---- (durations/settings only — session progress is
    // deliberately NOT persisted; restarting the shell mid-pomodoro just
    // resets to idle rather than resurrecting a stale countdown).

    FileView {
        id: settingsFile
        path: Quickshell.statePath("pomodoro.json")
        watchChanges: false
        printErrors: true
        onLoaded: {
            try {
                const t = settingsFile.text();
                const parsed = (t && t.length > 0) ? JSON.parse(t) : {};
                if (parsed.workMinutes) root.workMinutes = parsed.workMinutes;
                if (parsed.shortBreakMinutes) root.shortBreakMinutes = parsed.shortBreakMinutes;
                if (parsed.longBreakMinutes) root.longBreakMinutes = parsed.longBreakMinutes;
                if (parsed.sessionsUntilLongBreak) root.sessionsUntilLongBreak = parsed.sessionsUntilLongBreak;
            } catch (e) {
                console.warn("[PomodoroService] settings parse error:", e);
            }
        }
        onLoadFailed: function(err) {}
    }

    function _save() {
        try {
            settingsFile.setText(JSON.stringify({
                workMinutes: root.workMinutes,
                shortBreakMinutes: root.shortBreakMinutes,
                longBreakMinutes: root.longBreakMinutes,
                sessionsUntilLongBreak: root.sessionsUntilLongBreak
            }));
        } catch (e) {
            console.warn("[PomodoroService] settings save error:", e);
        }
    }
}

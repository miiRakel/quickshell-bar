pragma Singleton

// AlarmService.qml
// Recurring alarms — pick times + weekdays, get a sound + notification +
// an unmissable on-screen ringing card when one fires.
//
// Deliberately its own module (not part of notes/): a separate singleton
// with its own storage file means it can be removed without touching
// notes state if something here breaks.
//
// Public surface used by AlarmPopup/AlarmRinging + shell.qml IpcHandler:
//   alarms: array<{ id, hour, minute, days, label, enabled }>
//     days: array of JS Date.getDay() values (0=Sun..6=Sat) this alarm fires on
//   popupOpen: bool
//   ringingAlarm: the alarm object currently going off, or null
//   openPopup() / closePopup() / togglePopup()
//   addAlarm(hour, minute, days, label)
//   updateAlarm(id, fields)          (fields: partial {hour,minute,days,label,enabled})
//   removeAlarm(id)
//   dismissRinging()
//   snoozeRinging(minutes)

import QtQuick
import Quickshell
import Quickshell.Io
import qs

Singleton {
    id: root

    property var alarms: []
    property bool popupOpen: false
    property var ringingAlarm: null

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

    // ---- Alarms ----

    function addAlarm(hour, minute, days, label) {
        const entry = {
            id: Date.now().toString(36) + Math.random().toString(36).slice(2, 6),
            hour: hour, minute: minute,
            days: Array.isArray(days) ? days.slice() : [],
            label: (label || "").trim(),
            enabled: true
        };
        root.alarms = [...root.alarms, entry].sort((a, b) =>
            (a.hour * 60 + a.minute) - (b.hour * 60 + b.minute));
        _save();
    }

    function updateAlarm(id, fields) {
        root.alarms = root.alarms.map(a => a.id === id ? Object.assign({}, a, fields) : a);
        _save();
    }

    function removeAlarm(id) {
        root.alarms = root.alarms.filter(a => a.id !== id);
        _save();
        if (root.ringingAlarm && root.ringingAlarm.id === id)
            root.ringingAlarm = null;
    }

    // ---- Ringing ----

    function dismissRinging() {
        if (!root.ringingAlarm) return;
        _firedToday[_fireKey(root.ringingAlarm)] = true;
        root.ringingAlarm = null;
    }

    function snoozeRinging(minutes) {
        if (!root.ringingAlarm) return;
        const snoozed = root.ringingAlarm;
        _firedToday[_fireKey(snoozed)] = true;
        root.ringingAlarm = null;
        snoozeTimer.targetId = snoozed.id;
        snoozeTimer.targetLabel = snoozed.label;
        snoozeTimer.interval = minutes * 60 * 1000;
        snoozeTimer.restart();
    }

    Timer {
        id: snoozeTimer
        property string targetId: ""
        property string targetLabel: ""
        repeat: false
        onTriggered: root._fire({ id: targetId, label: targetLabel, snoozed: true })
    }

    // ---- Background check ----
    //
    // Plain Date comparison on a repeating Timer, NOT SystemClock — this
    // codebase's own gotcha #64 notes SystemClock doesn't recover cleanly
    // from suspend. A 20s poll comparing wall-clock Date against each
    // alarm's schedule is suspend-safe: it just checks "what time is it
    // really, right now" on every tick, so a resume after sleep behaves
    // exactly like a normal tick a bit later than expected.
    //
    // `_firedToday` keys are "<alarmId>-<YYYY-MM-DD>" so each alarm can
    // only fire once per calendar day; a small grace window (below) covers
    // the case where the exact minute was missed (tick granularity, brief
    // suspend) without re-firing something from hours/days ago.
    property var _firedToday: ({})

    function _fireKey(alarm) {
        const d = new Date();
        const day = d.getFullYear() + "-" + (d.getMonth() + 1) + "-" + d.getDate();
        return alarm.id + "-" + day;
    }

    function _fire(alarm) {
        root.ringingAlarm = alarm;
        soundPlayer.running = true;
        notifyProc.command = ["notify-send", "-u", "critical", "-a", "quickshell-bar",
            "Alarm" + (alarm.snoozed ? " (snoozed)" : ""), alarm.label || "Time's up"];
        notifyProc.running = true;
    }

    Timer {
        id: checkTimer
        interval: 20000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: {
            if (root.ringingAlarm) return; // one at a time — don't stack fires
            const now = new Date();
            const nowMinutes = now.getHours() * 60 + now.getMinutes();
            for (const alarm of root.alarms) {
                if (!alarm.enabled) continue;
                if (!alarm.days.includes(now.getDay())) continue;
                const targetMinutes = alarm.hour * 60 + alarm.minute;
                // Grace window: fire if we're at or up to 2 minutes past the
                // target (covers the 20s poll granularity and brief
                // suspends) but never for something long past.
                if (nowMinutes < targetMinutes || nowMinutes > targetMinutes + 2) continue;
                const key = root._fireKey(alarm);
                if (root._firedToday[key]) continue;
                root._firedToday[key] = true;
                root._fire(alarm);
                break; // one fire per tick keeps things simple
            }
        }
    }

    Process {
        id: soundPlayer
        running: false
        command: ["canberra-gtk-play", "-i", "alarm-clock-elapsed", "-d", "quickshell-bar alarm"]
        stderr: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                if (line && line.length > 0)
                    console.warn("[AlarmService] canberra-gtk-play:", line.trim());
            }
        }
    }

    Process {
        id: notifyProc
        running: false
    }

    // ---- Persistence ----

    FileView {
        id: alarmsFile
        path: Quickshell.statePath("alarms.json")
        watchChanges: false
        printErrors: true
        onLoaded: {
            try {
                const t = alarmsFile.text();
                const parsed = (t && t.length > 0) ? JSON.parse(t) : [];
                root.alarms = Array.isArray(parsed) ? parsed : [];
            } catch (e) {
                console.warn("[AlarmService] alarms parse error:", e);
                root.alarms = [];
            }
        }
        onLoadFailed: function(err) {
            root.alarms = [];
        }
    }

    function _save() {
        try {
            alarmsFile.setText(JSON.stringify(root.alarms));
        } catch (e) {
            console.warn("[AlarmService] alarms save error:", e);
        }
    }
}

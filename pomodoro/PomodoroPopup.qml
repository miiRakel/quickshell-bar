// PomodoroPopup.qml
// Work/break interval timer UI. Triggered from the stopwatch button in
// NotesPopup, or via IPC (`qs ipc call pomodoro open/close/toggle`). One
// panel per monitor; only the focused-monitor's panel is visible.

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import qs
import qs.notes             // for NotesService singleton (back button hand-off)

PanelWindow {
    id: panel
    WlrLayershell.namespace: "quickshell-popup"

    required property var modelData
    required property string focusedOutput

    screen: modelData

    readonly property bool isFocusedScreen:
        modelData && modelData.name === focusedOutput
    readonly property bool wantOpen:
        !!(PomodoroService && PomodoroService.popupOpen) && isFocusedScreen
    visible: wantOpen || hideHold.running
    Timer { id: hideHold; interval: 180; repeat: false }
    onWantOpenChanged: {
        if (wantOpen) hideHold.stop();
        else          hideHold.restart();
    }

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    // Same side-rail convention as Notes/Alarms — the back button lives
    // outside the card, not overlapping content.
    readonly property int cardWidth: 300
    implicitWidth: cardWidth + 24 + 36
    implicitHeight: 360 + 24

    Connections {
        target: PomodoroService
        function onPopupOpenChanged() {
            if (PomodoroService.popupOpen)
                Qt.callLater(() => bgCard.forceActiveFocus());
        }
    }

    function _phaseLabel() {
        switch (PomodoroService.phase) {
        case "work":       return "Work";
        case "shortBreak":  return "Short break";
        case "longBreak":   return "Long break";
        default:            return "Ready";
        }
    }

    function _phaseTotalSeconds() {
        switch (PomodoroService.phase) {
        case "shortBreak": return PomodoroService.shortBreakMinutes * 60;
        case "longBreak":  return PomodoroService.longBreakMinutes * 60;
        default:           return PomodoroService.workMinutes * 60;
        }
    }

    function _fmtTime(totalSeconds) {
        const m = Math.floor(totalSeconds / 60);
        const s = totalSeconds % 60;
        return String(m).padStart(2, "0") + ":" + String(s).padStart(2, "0");
    }

    Rectangle {
        id: bgCard
        anchors {
            left: parent.left
            top: parent.top
            bottom: parent.bottom
            margins: 12
        }
        width: panel.cardWidth
        color: Qt.alpha(Theme.bg, 0.85)
        border.color: Theme.border
        border.width: 1
        radius: Theme.radius

        focus: true
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) {
                PomodoroService.closePopup();
                event.accepted = true;
            } else if (event.key === Qt.Key_Space) {
                if (PomodoroService.running) PomodoroService.pause();
                else                          PomodoroService.start();
                event.accepted = true;
            }
        }

        opacity: panel.wantOpen ? 1.0 : 0.0
        Behavior on opacity {
            NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
        }
        transform: Translate {
            y: panel.wantOpen ? 0 : 4
            Behavior on y {
                NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
            }
        }

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Qt.rgba(0, 0, 0, 0.25)
            shadowVerticalOffset: 4
            shadowHorizontalOffset: 0
            shadowBlur: 0.6
        }

        Column {
            anchors {
                fill: parent
                margins: 16
            }
            spacing: 14

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Pomodoro"
                color: Theme.text
                font.family: Theme.fontMono
                font.pixelSize: Theme.fontSizeLarge
                font.weight: Font.Bold
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: panel._phaseLabel()
                color: PomodoroService.phase === "work" ? Theme.accent : Theme.textDim
                font.family: Theme.fontMono
                font.pixelSize: Theme.fontSizeNormal
                font.weight: Font.Bold
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: panel._fmtTime(PomodoroService.remainingSeconds)
                color: Theme.text
                font.family: Theme.fontMono
                font.pixelSize: 44
                font.weight: Font.Bold
            }

            ProgressBar {
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - 32
                trackHeight: 6
                value: PomodoroService.phase === "idle" ? 0 :
                    1 - (PomodoroService.remainingSeconds / Math.max(1, panel._phaseTotalSeconds()))
            }

            // Session dots — filled ones are work sessions completed since
            // the last long break.
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 6
                Repeater {
                    model: PomodoroService.sessionsUntilLongBreak
                    delegate: Rectangle {
                        required property int index
                        width: 10
                        height: 10
                        radius: 5
                        color: index < PomodoroService.completedWorkSessions ? Theme.accent : Theme.surfaceHi
                    }
                }
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 8

                Rectangle {
                    width: 92
                    height: 34
                    radius: Theme.radiusSmall
                    color: startMa.containsMouse ? Theme.accent : Theme.surface
                    border.color: Theme.border
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }

                    Text {
                        anchors.centerIn: parent
                        text: PomodoroService.running ? "Pause" : "Start"
                        color: startMa.containsMouse ? Theme.accentText : Theme.text
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.fontSizeNormal
                        font.weight: Font.Bold
                    }

                    MouseArea {
                        id: startMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: PomodoroService.running ? PomodoroService.pause() : PomodoroService.start()
                    }
                }

                Rectangle {
                    width: 70
                    height: 34
                    radius: Theme.radiusSmall
                    color: skipMa.containsMouse ? Theme.surfaceHi : Theme.surface
                    border.color: Theme.border
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }

                    Text {
                        anchors.centerIn: parent
                        text: "Skip"
                        color: Theme.text
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.fontSizeNormal
                    }

                    MouseArea {
                        id: skipMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: PomodoroService.skip()
                    }
                }

                Rectangle {
                    width: 70
                    height: 34
                    radius: Theme.radiusSmall
                    color: resetMa.containsMouse ? Theme.surfaceHi : Theme.surface
                    border.color: Theme.border
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }

                    Text {
                        anchors.centerIn: parent
                        text: "Reset"
                        color: Theme.text
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.fontSizeNormal
                    }

                    MouseArea {
                        id: resetMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: PomodoroService.reset()
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: 1
                color: Theme.border
            }

            // ---- Durations (minutes) ----
            Column {
                width: parent.width
                spacing: 6

                Text {
                    text: "Durations (minutes)"
                    color: Theme.textDim
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.fontSizeBadge
                }

                Row {
                    spacing: 6
                    DurationField {
                        label: "Work"
                        value: PomodoroService.workMinutes
                        onCommitted: v => PomodoroService.setDurations(v, PomodoroService.shortBreakMinutes, PomodoroService.longBreakMinutes, PomodoroService.sessionsUntilLongBreak)
                    }
                    DurationField {
                        label: "Short"
                        value: PomodoroService.shortBreakMinutes
                        onCommitted: v => PomodoroService.setDurations(PomodoroService.workMinutes, v, PomodoroService.longBreakMinutes, PomodoroService.sessionsUntilLongBreak)
                    }
                    DurationField {
                        label: "Long"
                        value: PomodoroService.longBreakMinutes
                        onCommitted: v => PomodoroService.setDurations(PomodoroService.workMinutes, PomodoroService.shortBreakMinutes, v, PomodoroService.sessionsUntilLongBreak)
                    }
                }
            }
        }
    }

    // Back to notes — mirrors the alarm popup's back button exactly.
    Rectangle {
        id: backBtn
        anchors {
            left: bgCard.right
            top: bgCard.top
            leftMargin: 8
        }
        width: 24
        height: 24
        radius: Theme.radiusSmall
        color: backMa.containsMouse ? Theme.surfaceHi : Qt.alpha(Theme.bg, 0.85)
        border.color: Theme.border
        border.width: 1
        opacity: panel.wantOpen ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: Theme.animFast } }

        Text {
            anchors.centerIn: parent
            // Font Awesome 7 Solid:  arrow-left
            text: ""
            color: backMa.containsMouse ? Theme.text : Theme.textDim
            font.family: Theme.fontIcon
            font.styleName: "Solid"
            font.pixelSize: 12
            renderType: Text.NativeRendering
            Behavior on color { ColorAnimation { duration: Theme.animFast } }
        }

        MouseArea {
            id: backMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                PomodoroService.closePopup();
                NotesService.openPopup();
            }
        }
    }
}

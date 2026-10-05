// AlarmRinging.qml
// The actual "it's going off" card — shows on top of everything the
// instant AlarmService.ringingAlarm is set, independent of whether the
// Alarms list popup is open. Not part of the PopupController mutex on
// purpose: an alarm firing shouldn't get silently swallowed because some
// other popup happened to be open.

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import qs

PanelWindow {
    id: panel
    WlrLayershell.namespace: "quickshell-popup"

    required property var modelData
    required property string focusedOutput

    screen: modelData

    readonly property bool isFocusedScreen:
        modelData && modelData.name === focusedOutput
    readonly property bool wantOpen:
        !!(AlarmService && AlarmService.ringingAlarm) && isFocusedScreen
    visible: wantOpen || hideHold.running
    Timer { id: hideHold; interval: 180; repeat: false }
    // Keys only attaches to Items — PanelWindow itself isn't one. Give the
    // card focus the instant it becomes visible so Esc/Enter dismiss works
    // without the user needing to click first.
    onWantOpenChanged: {
        if (wantOpen) {
            hideHold.stop();
            Qt.callLater(() => card.forceActiveFocus());
        } else {
            hideHold.restart();
        }
    }

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    implicitWidth: 300 + 24
    implicitHeight: 160 + 24

    Rectangle {
        id: card
        anchors.fill: parent
        anchors.margins: 12
        color: Theme.bg
        border.color: Theme.error
        border.width: 2
        radius: Theme.radius

        focus: true
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                AlarmService.dismissRinging();
                event.accepted = true;
            }
        }

        opacity: panel.wantOpen ? 1.0 : 0.0
        Behavior on opacity {
            NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
        }

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Qt.rgba(0, 0, 0, 0.35)
            shadowVerticalOffset: 4
            shadowHorizontalOffset: 0
            shadowBlur: 0.6
        }

        Column {
            anchors.centerIn: parent
            spacing: 10

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                // Font Awesome 7 Solid:  bell
                text: ""
                color: Theme.error
                font.family: Theme.fontIcon
                font.styleName: "Solid"
                font.pixelSize: 22
                renderType: Text.NativeRendering
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: AlarmService.ringingAlarm ? (AlarmService.ringingAlarm.label || "Alarm") : ""
                color: Theme.text
                font.family: Theme.fontMono
                font.pixelSize: Theme.fontSizeLarge
                font.weight: Font.Bold
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 8

                Rectangle {
                    width: 96
                    height: 32
                    radius: Theme.radiusSmall
                    color: snoozeMa.containsMouse ? Theme.surfaceHi : Theme.surface
                    border.color: Theme.border
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }

                    Text {
                        anchors.centerIn: parent
                        text: "Snooze 5m"
                        color: Theme.text
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.fontSizeSmall
                    }

                    MouseArea {
                        id: snoozeMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: AlarmService.snoozeRinging(5)
                    }
                }

                Rectangle {
                    width: 96
                    height: 32
                    radius: Theme.radiusSmall
                    color: dismissMa.containsMouse ? Theme.accent : Theme.surface
                    border.color: Theme.border
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }

                    Text {
                        anchors.centerIn: parent
                        text: "Dismiss"
                        color: dismissMa.containsMouse ? Theme.accentText : Theme.text
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Font.Bold
                    }

                    MouseArea {
                        id: dismissMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: AlarmService.dismissRinging()
                    }
                }
            }
        }
    }
}

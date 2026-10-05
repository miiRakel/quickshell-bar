// AlarmPopup.qml
// Recurring alarms: set a time, pick weekdays, optional label. Triggered
// from the small clock button in NotesPopup, or via IPC
// (`qs ipc call alarms open/close/toggle`). One panel per monitor; only
// the focused-monitor's panel is visible.

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
        !!(AlarmService && AlarmService.popupOpen) && isFocusedScreen
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

    // The extra +36 on the width is a side rail to the right of the card,
    // matching NotesPopup — holds the back-to-notes button outside the
    // card's content instead of overlapping it.
    readonly property int cardWidth: 320
    implicitWidth: cardWidth + 24 + 36
    implicitHeight: 420 + 24

    // Keys only attaches to Items — PanelWindow itself isn't one, so
    // keyboard handling lives on bgCard below. Give it focus whenever the
    // popup opens.
    Connections {
        target: AlarmService
        function onPopupOpenChanged() {
            if (AlarmService.popupOpen)
                Qt.callLater(() => bgCard.forceActiveFocus());
        }
    }

    // Mo=1 .. Su=0, matching JS Date.getDay(); display order starts Monday.
    readonly property var _dayLabels: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
    readonly property var _dayValues: [1, 2, 3, 4, 5, 6, 0]

    // ---- New-alarm draft state ----
    property string draftTime: ""
    property var draftDays: []
    property string draftLabel: ""

    function toggleDraftDay(v) {
        const i = draftDays.indexOf(v);
        draftDays = i >= 0 ? draftDays.filter(x => x !== v) : draftDays.concat([v]);
    }

    function submitDraft() {
        const m = /^([0-2]?\d):([0-5]\d)$/.exec(draftTime.trim());
        if (!m) return;
        const hour = parseInt(m[1], 10);
        if (hour > 23) return;
        AlarmService.addAlarm(hour, parseInt(m[2], 10), draftDays, draftLabel);
        draftTime = "";
        draftDays = [];
        draftLabel = "";
        timeInput.forceActiveFocus();
    }

    function _fmt(alarm) {
        return String(alarm.hour).padStart(2, "0") + ":" + String(alarm.minute).padStart(2, "0");
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
        color: Qt.alpha(Theme.bg, 0.6)
        border.color: Theme.border
        border.width: 1
        radius: Theme.radius

        focus: true
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) {
                AlarmService.closePopup();
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
                margins: 12
            }
            spacing: 8

            Text {
                text: "Alarms"
                color: Theme.text
                font.family: Theme.fontMono
                font.pixelSize: Theme.fontSizeLarge
                font.weight: Font.Bold
            }

            // ---- New-alarm form ----
            Column {
                width: parent.width
                spacing: 6

                Row {
                    width: parent.width
                    spacing: 8

                    Rectangle {
                        id: timeBox
                        width: 70
                        height: 32
                        radius: Theme.radiusSmall
                        color: Theme.surface
                        border.color: timeInput.activeFocus ? Theme.text : Theme.border
                        border.width: 1
                        Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

                        TextInput {
                            id: timeInput
                            anchors.fill: parent
                            anchors.margins: 6
                            verticalAlignment: TextInput.AlignVCenter
                            horizontalAlignment: TextInput.AlignHCenter
                            text: panel.draftTime
                            onTextChanged: panel.draftTime = text
                            color: Theme.text
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.fontSizeNormal
                            maximumLength: 5
                            Keys.onReturnPressed: panel.submitDraft()
                            Keys.onEnterPressed: panel.submitDraft()

                            Text {
                                anchors.fill: parent
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: Text.AlignHCenter
                                visible: !timeInput.text && !timeInput.activeFocus
                                text: "07:30"
                                color: Theme.textMuted
                                font: timeInput.font
                            }
                        }
                    }

                    Rectangle {
                        id: labelBox
                        width: parent.width - timeBox.width - addBtn.width - parent.spacing * 2
                        height: 32
                        radius: Theme.radiusSmall
                        color: Theme.surface
                        border.color: labelInput.activeFocus ? Theme.text : Theme.border
                        border.width: 1
                        Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

                        TextInput {
                            id: labelInput
                            anchors.fill: parent
                            anchors.margins: 8
                            verticalAlignment: TextInput.AlignVCenter
                            text: panel.draftLabel
                            onTextChanged: panel.draftLabel = text
                            color: Theme.text
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.fontSizeNormal
                            clip: true
                            Keys.onReturnPressed: panel.submitDraft()
                            Keys.onEnterPressed: panel.submitDraft()

                            Text {
                                anchors.fill: parent
                                verticalAlignment: Text.AlignVCenter
                                visible: !labelInput.text && !labelInput.activeFocus
                                text: "Label (optional)"
                                color: Theme.textMuted
                                font: labelInput.font
                            }
                        }
                    }

                    Rectangle {
                        id: addBtn
                        width: 32
                        height: 32
                        radius: Theme.radiusSmall
                        color: addMa.containsMouse ? Theme.surfaceHi : Theme.surface
                        border.color: Theme.border
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: Theme.animFast } }

                        Text {
                            anchors.centerIn: parent
                            // Font Awesome 7 Solid:  plus
                            text: ""
                            color: Theme.text
                            font.family: Theme.fontIcon
                            font.styleName: "Solid"
                            font.pixelSize: 12
                            renderType: Text.NativeRendering
                        }

                        MouseArea {
                            id: addMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: panel.submitDraft()
                        }
                    }
                }

                // Day-of-week toggle pills for the draft.
                Row {
                    spacing: 4
                    Repeater {
                        model: panel._dayLabels
                        delegate: Rectangle {
                            id: dayPill
                            required property string modelData
                            required property int index
                            readonly property int dayValue: panel._dayValues[index]
                            readonly property bool selected: panel.draftDays.includes(dayValue)
                            width: 32
                            height: 24
                            radius: Theme.radiusSmall
                            color: selected ? Theme.accent : Theme.surface
                            border.color: Theme.border
                            border.width: selected ? 0 : 1

                            Text {
                                anchors.centerIn: parent
                                text: dayPill.modelData
                                color: dayPill.selected ? Theme.accentText : Theme.textDim
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.fontSizeBadge
                                font.weight: dayPill.selected ? Font.Bold : Font.Normal
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: panel.toggleDraftDay(dayPill.dayValue)
                            }
                        }
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: 1
                color: Theme.border
            }

            // ---- Alarm list ----
            ListView {
                id: listView
                width: parent.width
                height: parent.height - y
                clip: true
                spacing: 4
                model: ScriptModel {
                    values: AlarmService.alarms
                    objectProp: "id"
                }
                interactive: true
                boundsBehavior: Flickable.StopAtBounds

                delegate: Rectangle {
                    id: row
                    required property var modelData
                    width: ListView.view.width
                    height: 44
                    radius: Theme.radiusSmall
                    color: rowMa.containsMouse ? Theme.surface : "transparent"
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }
                    opacity: row.modelData.enabled ? 1.0 : 0.45

                    Row {
                        anchors {
                            fill: parent
                            leftMargin: 8
                            rightMargin: 8
                        }
                        spacing: 10

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: panel._fmt(row.modelData)
                            color: Theme.text
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.fontSizeLarge
                            font.weight: Font.Bold
                            width: 56
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 56 - enableBtn.width - delBtn.width - parent.spacing * 3
                            spacing: 1

                            Text {
                                width: parent.width
                                elide: Text.ElideRight
                                text: row.modelData.label || "Alarm"
                                color: Theme.text
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.fontSizeNormal
                            }
                            Text {
                                text: row.modelData.days.length === 0
                                    ? "Once"
                                    : row.modelData.days.length === 7
                                        ? "Every day"
                                        : panel._dayValues
                                            .map((v, i) => row.modelData.days.includes(v) ? panel._dayLabels[i] : null)
                                            .filter(x => x)
                                            .join(" ")
                                color: Theme.textDim
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.fontSizeBadge
                            }
                        }

                        Rectangle {
                            id: enableBtn
                            anchors.verticalCenter: parent.verticalCenter
                            width: 36
                            height: 20
                            radius: 10
                            color: row.modelData.enabled ? Theme.accent : Theme.surfaceHi

                            Rectangle {
                                width: 14
                                height: 14
                                radius: 7
                                anchors.verticalCenter: parent.verticalCenter
                                x: row.modelData.enabled ? parent.width - width - 3 : 3
                                color: row.modelData.enabled ? Theme.accentText : Theme.textDim
                                Behavior on x { NumberAnimation { duration: Theme.animFast } }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: AlarmService.updateAlarm(row.modelData.id, { enabled: !row.modelData.enabled })
                            }
                        }

                        Rectangle {
                            id: delBtn
                            anchors.verticalCenter: parent.verticalCenter
                            width: 24
                            height: 24
                            radius: Theme.radiusSmall
                            color: delMa.containsMouse ? Theme.bg : "transparent"
                            border.color: Theme.border
                            border.width: delMa.containsMouse ? 1 : 0
                            opacity: delMa.containsMouse ? 1.0 : (rowMa.containsMouse ? 0.6 : 0.0)
                            Behavior on opacity { NumberAnimation { duration: Theme.animFast } }

                            Text {
                                anchors.centerIn: parent
                                // Font Awesome 7 Solid:  trash-can
                                text: ""
                                color: Theme.text
                                font.family: Theme.fontIcon
                                font.styleName: "Solid"
                                font.pixelSize: 11
                                renderType: Text.NativeRendering
                            }

                            MouseArea {
                                id: delMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: AlarmService.removeAlarm(row.modelData.id)
                            }
                        }
                    }

                    MouseArea {
                        id: rowMa
                        anchors.fill: parent
                        hoverEnabled: true
                        z: -1
                    }
                }

                Item {
                    anchors.centerIn: parent
                    visible: listView.count === 0
                    width: parent.width
                    height: 60
                    Text {
                        anchors.centerIn: parent
                        text: "No alarms yet"
                        color: Theme.textMuted
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.fontSizeNormal
                    }
                }
            }
        }
    }

    // Back to notes — same rail position as the clock button in
    // NotesPopup, just swapped for a back arrow. Closing here and opening
    // there is a plain hand-off; PopupController's mutex means only one of
    // the two is ever actually visible anyway.
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
        color: backMa.containsMouse ? Theme.surfaceHi : Qt.alpha(Theme.bg, 0.6)
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
                AlarmService.closePopup();
                NotesService.openPopup();
            }
        }
    }
}

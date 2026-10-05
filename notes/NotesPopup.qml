// NotesPopup.qml
// Quick-capture notes popup. Triggered via the qs-IPC handler in
// shell.qml (bind it to a compositor keybind; see examples/). One panel
// per monitor; only the focused-monitor's panel is visible.

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import qs
import qs.alarms
import qs.pomodoro

PanelWindow {
    id: panel
    WlrLayershell.namespace: "quickshell-popup"

    required property var modelData
    required property string focusedOutput

    screen: modelData

    readonly property bool isFocusedScreen:
        modelData && modelData.name === focusedOutput
    readonly property bool wantOpen:
        !!(NotesService && NotesService.popupOpen) && isFocusedScreen
    // Stay mapped briefly during fade-out so the animation can play.
    visible: wantOpen || hideHold.running
    Timer { id: hideHold; interval: 180; repeat: false }
    onWantOpenChanged: {
        if (wantOpen) hideHold.stop();
        else          hideHold.restart();
    }

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    // Layer-shell: stay above normal windows + grab keyboard so the note
    // field receives input.
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    // No anchors → wlroots horizontally and vertically centers a
    // free-floating layer surface. Surface is +24 px in each axis so the
    // drop shadow has padding to render in. The extra +36 on the width is
    // a side rail to the right of the card itself, for the alarm-clock
    // launcher button — living outside the card instead of overlapping its
    // content.
    readonly property int cardWidth: 420
    implicitWidth: cardWidth + 24 + 36
    implicitHeight: 440 + 24

    // Refocus the input whenever the popup opens. The draft text is left
    // as-is across toggles on purpose — closing with Escape shouldn't
    // throw away what you were mid-typing.
    Connections {
        target: NotesService
        function onPopupOpenChanged() {
            if (NotesService.popupOpen)
                Qt.callLater(() => noteInput.forceActiveFocus());
        }
    }

    // Non-empty while editing an existing note — Enter then updates that
    // note in place instead of creating a new one.
    property string editingId: ""

    function startEdit(id, text) {
        panel.editingId = id;
        noteInput.text = text;
        noteInput.cursorPosition = text.length;
        noteInput.forceActiveFocus();
    }

    // Backdrop blur behind the card (Hyprland ext-background-effect-v1).

    Rectangle {
        id: bgCard
        anchors {
            left: parent.left
            top: parent.top
            bottom: parent.bottom
            margins: 12
        }
        width: panel.cardWidth
        // Higher alpha than Clipboard's identical card (0.35): notes are
        // usually short, leaving a lot of empty card area, and at 0.35 the
        // near-black Theme.bg tint is nearly invisible over a dark desktop —
        // the popup looked like it had holes in it. 0.6 stays translucent
        // enough for the Hyprland blur layer rule to still read as glassy.
        color: Qt.alpha(Theme.bg, 0.6)
        border.color: Theme.border
        border.width: 1
        radius: Theme.radius

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

            // ---- Quick-capture input ----
            Rectangle {
                id: inputBox
                width: parent.width
                height: 84
                radius: Theme.radiusSmall
                color: Theme.surface
                border.color: noteInput.activeFocus ? Theme.text : Theme.border
                border.width: 1
                Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

                Flickable {
                    id: inputFlick
                    anchors {
                        fill: parent
                        margins: 10
                    }
                    clip: true
                    contentWidth: width
                    contentHeight: Math.max(height, noteInput.implicitHeight)
                    boundsBehavior: Flickable.StopAtBounds

                    TextEdit {
                        id: noteInput
                        width: inputFlick.width
                        wrapMode: TextEdit.Wrap
                        color: Theme.text
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.fontSizeNormal
                        selectByMouse: true

                        // TextEdit never scrolls itself — without this, typing
                        // past the visible height just clips the cursor out of
                        // view instead of following it.
                        onCursorRectangleChanged: {
                            if (cursorRectangle.y < inputFlick.contentY)
                                inputFlick.contentY = cursorRectangle.y;
                            else if (cursorRectangle.y + cursorRectangle.height > inputFlick.contentY + inputFlick.height)
                                inputFlick.contentY = cursorRectangle.y + cursorRectangle.height - inputFlick.height;
                        }

                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Escape) {
                                NotesService.closePopup();
                                event.accepted = true;
                            } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                                    && !(event.modifiers & Qt.ShiftModifier)) {
                                if (panel.editingId) {
                                    NotesService.updateNote(panel.editingId, noteInput.text);
                                    panel.editingId = "";
                                } else {
                                    NotesService.addNote(noteInput.text);
                                }
                                noteInput.text = "";
                                inputFlick.contentY = 0;
                                event.accepted = true;
                            }
                            // Shift+Enter falls through to TextEdit's own newline.
                        }

                        Text {
                            anchors.fill: parent
                            visible: !noteInput.text && !noteInput.activeFocus
                            text: "Quick note… Enter to save, Shift+Enter for a new line"
                            color: Theme.textMuted
                            font: noteInput.font
                        }
                    }
                }
            }

            // ---- Saved notes ----
            ListView {
                id: listView
                width: parent.width
                height: parent.height - inputBox.height - parent.spacing
                clip: true
                spacing: 4
                model: ScriptModel {
                    values: NotesService.notes
                    objectProp: "id"
                }
                interactive: true
                boundsBehavior: Flickable.StopAtBounds

                delegate: Rectangle {
                    id: row
                    required property var modelData
                    // Per-row expand/collapse — long notes start clamped to
                    // a few lines; click anywhere on the row (except the
                    // delete button) to see the rest.
                    property bool expanded: false
                    width: ListView.view.width
                    height: bodyCol.implicitHeight + 16
                    radius: Theme.radiusSmall
                    readonly property bool isEditing: panel.editingId === row.modelData.id
                    color: isEditing
                        ? Theme.surfaceHi
                        : (rowMa.containsMouse ? Theme.surface : "transparent")
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }

                    Column {
                        id: bodyCol
                        anchors {
                            top: parent.top
                            left: parent.left
                            right: parent.right
                            leftMargin: 8
                            rightMargin: 8
                            topMargin: 6
                        }
                        spacing: 2

                        Row {
                            width: parent.width
                            spacing: 10

                            Text {
                                id: bodyText
                                width: parent.width - editBtn.width - copyBtn.width - delBtn.width - parent.spacing * 3
                                text: row.modelData.text
                                wrapMode: Text.Wrap
                                maximumLineCount: row.expanded ? 0 : 4
                                elide: row.expanded ? Text.ElideNone : Text.ElideRight
                                color: Theme.text
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.fontSizeNormal
                            }

                            // Hover-revealed edit button — loads the note
                            // back into the input box; Enter saves over it.
                            Rectangle {
                                id: editBtn
                                anchors.top: parent.top
                                width: 24
                                height: 24
                                radius: Theme.radiusSmall
                                color: editMa.containsMouse ? Theme.bg : "transparent"
                                border.color: Theme.border
                                border.width: editMa.containsMouse ? 1 : 0
                                opacity: editMa.containsMouse
                                    ? 1.0
                                    : (rowMa.containsMouse ? 0.6 : 0.0)
                                Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
                                Behavior on color { ColorAnimation { duration: Theme.animFast } }

                                Text {
                                    anchors.centerIn: parent
                                    // Font Awesome 7 Solid:  pen-to-square
                                    text: ""
                                    color: Theme.text
                                    font.family: Theme.fontIcon
                                    font.styleName: "Solid"
                                    font.pixelSize: 11
                                    renderType: Text.NativeRendering
                                }

                                MouseArea {
                                    id: editMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: panel.startEdit(row.modelData.id, row.modelData.text)
                                }
                            }

                            // Hover-revealed copy button — copies the full
                            // note text (never clamped) to the clipboard.
                            // Swaps to a "Kopierad" label for a beat after
                            // a click so the click actually registered.
                            Rectangle {
                                id: copyBtn
                                anchors.top: parent.top
                                property bool justCopied: false
                                width: justCopied ? copyLabel.implicitWidth + 16 : 24
                                height: 24
                                radius: Theme.radiusSmall
                                color: justCopied
                                    ? Theme.surfaceHi
                                    : (copyMa.containsMouse ? Theme.bg : "transparent")
                                border.color: Theme.border
                                border.width: (justCopied || copyMa.containsMouse) ? 1 : 0
                                opacity: justCopied
                                    ? 1.0
                                    : (copyMa.containsMouse ? 1.0 : (rowMa.containsMouse ? 0.6 : 0.0))
                                Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
                                Behavior on color { ColorAnimation { duration: Theme.animFast } }
                                Behavior on width { NumberAnimation { duration: Theme.animFast } }

                                Timer {
                                    id: copiedTimer
                                    interval: 1200
                                    onTriggered: copyBtn.justCopied = false
                                }

                                Text {
                                    anchors.centerIn: parent
                                    visible: !copyBtn.justCopied
                                    // Font Awesome 7 Solid:  copy
                                    text: ""
                                    color: Theme.text
                                    font.family: Theme.fontIcon
                                    font.styleName: "Solid"
                                    font.pixelSize: 11
                                    renderType: Text.NativeRendering
                                }

                                Text {
                                    id: copyLabel
                                    anchors.centerIn: parent
                                    visible: copyBtn.justCopied
                                    text: "Kopierad"
                                    color: Theme.text
                                    font.family: Theme.fontMono
                                    font.pixelSize: Theme.fontSizeBadge
                                }

                                MouseArea {
                                    id: copyMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        NotesService.copyNote(row.modelData.text);
                                        copyBtn.justCopied = true;
                                        copiedTimer.restart();
                                    }
                                }
                            }

                            // Hover-revealed delete button.
                            Rectangle {
                                id: delBtn
                                anchors.top: parent.top
                                width: 24
                                height: 24
                                radius: Theme.radiusSmall
                                color: delMa.containsMouse ? Theme.bg : "transparent"
                                border.color: Theme.border
                                border.width: delMa.containsMouse ? 1 : 0
                                opacity: delMa.containsMouse
                                    ? 1.0
                                    : (rowMa.containsMouse ? 0.6 : 0.0)
                                Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
                                Behavior on color { ColorAnimation { duration: Theme.animFast } }

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
                                    onClicked: {
                                        if (row.isEditing) {
                                            panel.editingId = "";
                                            noteInput.text = "";
                                        }
                                        NotesService.removeNote(row.modelData.id);
                                    }
                                }
                            }
                        }

                        // Only shown while collapsed AND the clamp actually
                        // cut something off (short notes never show this).
                        Text {
                            visible: !row.expanded && bodyText.truncated
                            text: "Click to expand"
                            color: Theme.textMuted
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.fontSizeBadge
                        }
                    }

                    MouseArea {
                        id: rowMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        z: -1
                        onClicked: row.expanded = !row.expanded
                    }
                }

                // Empty state
                Item {
                    anchors.centerIn: parent
                    visible: listView.count === 0
                    width: parent.width
                    height: 60
                    Text {
                        anchors.centerIn: parent
                        text: "No notes yet"
                        color: Theme.textMuted
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.fontSizeNormal
                    }
                }
            }
        }
    }

    // Opens the Alarms popup. Lives in the rail OUTSIDE the card (not
    // overlapping its content), and is a separate module/service entirely —
    // this is just a launcher button, so it can be ripped out independently
    // without touching notes state if something breaks.
    Rectangle {
        id: alarmBtn
        anchors {
            left: bgCard.right
            top: bgCard.top
            leftMargin: 8
        }
        width: 24
        height: 24
        radius: Theme.radiusSmall
        color: alarmMa.containsMouse ? Theme.surfaceHi : Qt.alpha(Theme.bg, 0.85)
        border.color: Theme.border
        border.width: 1
        opacity: panel.wantOpen ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: Theme.animFast } }

        Text {
            anchors.centerIn: parent
            // Font Awesome 7 Solid:  clock
            text: ""
            color: alarmMa.containsMouse ? Theme.text : Theme.textDim
            font.family: Theme.fontIcon
            font.styleName: "Solid"
            font.pixelSize: 12
            renderType: Text.NativeRendering
            Behavior on color { ColorAnimation { duration: Theme.animFast } }
        }

        MouseArea {
            id: alarmMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: AlarmService.openPopup()
        }
    }

    // Opens the Pomodoro popup. Same rail, stacked below the alarm button.
    Rectangle {
        id: pomodoroBtn
        anchors {
            left: bgCard.right
            top: alarmBtn.bottom
            leftMargin: 8
            topMargin: 8
        }
        width: 24
        height: 24
        radius: Theme.radiusSmall
        color: pomodoroMa.containsMouse ? Theme.surfaceHi : Qt.alpha(Theme.bg, 0.85)
        border.color: Theme.border
        border.width: 1
        opacity: panel.wantOpen ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: Theme.animFast } }

        Text {
            anchors.centerIn: parent
            // Font Awesome 7 Solid:  stopwatch
            text: ""
            color: pomodoroMa.containsMouse ? Theme.text : Theme.textDim
            font.family: Theme.fontIcon
            font.styleName: "Solid"
            font.pixelSize: 12
            renderType: Text.NativeRendering
            Behavior on color { ColorAnimation { duration: Theme.animFast } }
        }

        MouseArea {
            id: pomodoroMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: PomodoroService.openPopup()
        }
    }
}

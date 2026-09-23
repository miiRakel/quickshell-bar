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
    // drop shadow has padding to render in.
    implicitWidth: 420 + 24
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

    // Backdrop blur behind the card (Hyprland ext-background-effect-v1).

    Rectangle {
        id: bgCard
        anchors.fill: parent
        anchors.margins: 12
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

                TextEdit {
                    id: noteInput
                    anchors {
                        fill: parent
                        margins: 10
                    }
                    wrapMode: TextEdit.Wrap
                    clip: true
                    color: Theme.text
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.fontSizeNormal
                    selectByMouse: true

                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Escape) {
                            NotesService.closePopup();
                            event.accepted = true;
                        } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                                && !(event.modifiers & Qt.ShiftModifier)) {
                            NotesService.addNote(noteInput.text);
                            noteInput.text = "";
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

            // ---- Saved notes ----
            ListView {
                id: listView
                width: parent.width
                height: parent.height - inputBox.height - footer.height - parent.spacing * 2
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
                    color: rowMa.containsMouse ? Theme.surface : "transparent"
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
                                width: parent.width - copyBtn.width - delBtn.width - parent.spacing * 2
                                text: row.modelData.text
                                wrapMode: Text.Wrap
                                maximumLineCount: row.expanded ? 0 : 4
                                elide: row.expanded ? Text.ElideNone : Text.ElideRight
                                color: Theme.text
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.fontSizeNormal
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
                                    onClicked: NotesService.removeNote(row.modelData.id)
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

            // ---- Footer hint ----
            Text {
                id: footer
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: "Esc to close · Enter to save · click a note to expand · copy/trash on hover"
                color: Theme.textMuted
                font.family: Theme.fontMono
                font.pixelSize: Theme.fontSizeSmall
            }
        }
    }
}

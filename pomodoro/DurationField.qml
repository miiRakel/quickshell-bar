// DurationField.qml
// Small labeled minute-count input used three times in PomodoroPopup's
// settings row (work/short break/long break). Commits on Enter or when
// focus leaves the field.

import QtQuick
import qs

Column {
    id: root

    property string label: ""
    property int value: 0
    signal committed(int v)

    spacing: 3

    Text {
        text: root.label
        color: Theme.textMuted
        font.family: Theme.fontMono
        font.pixelSize: Theme.fontSizeBadge
    }

    Rectangle {
        width: 60
        height: 28
        radius: Theme.radiusSmall
        color: Theme.surface
        border.color: input.activeFocus ? Theme.text : Theme.border
        border.width: 1
        Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

        TextInput {
            id: input
            anchors.fill: parent
            anchors.margins: 6
            horizontalAlignment: TextInput.AlignHCenter
            verticalAlignment: TextInput.AlignVCenter
            text: root.value.toString()
            validator: IntValidator { bottom: 1; top: 180 }
            color: Theme.text
            font.family: Theme.fontMono
            font.pixelSize: Theme.fontSizeNormal
            selectByMouse: true

            function _commit() {
                const v = parseInt(text, 10);
                if (!isNaN(v) && v > 0) root.committed(v);
                else text = root.value.toString();
            }

            Keys.onReturnPressed: { _commit(); focus = false; }
            Keys.onEnterPressed: { _commit(); focus = false; }
            onActiveFocusChanged: if (!activeFocus) _commit()

            // Reflect external changes (e.g. loaded from disk) when the
            // field isn't mid-edit.
            Connections {
                target: root
                function onValueChanged() {
                    if (!input.activeFocus) input.text = root.value.toString();
                }
            }
        }
    }
}

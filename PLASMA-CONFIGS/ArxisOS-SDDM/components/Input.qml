import QtQuick
import QtQuick.Controls

TextField {
    placeholderTextColor: config.color
    palette.text: config.color
    font.pointSize: config.fontSize
    font.family: config.font
    height: 40
    background: Rectangle {
        color: "#4c566a"
        radius: 20
        implicitHeight: 40
        implicitWidth: parent.width
        opacity: 0.5
    }
}

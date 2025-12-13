import QtQuick
import QtQuick.Controls
import org.kde.kirigami as Kirigami

Button {
    id: keyboardButton

    property int currentIndex: -1

    text: i18nd("plasma_lookandfeel_org.kde.lookandfeel", "Keyboard Layout: %1", keyboard.layouts[currentIndex] ? keyboard.layouts[currentIndex].shortName : "")
    font.pointSize: config.fontSize

    visible: keyboard.layouts.length > 1

    Component.onCompleted: currentIndex = Qt.binding(function() {return keyboard.currentLayout});

    onClicked: keyboardMenu.open()

    Menu {
        id: keyboardMenu
        y: keyboardButton.height

        Repeater {
            model: keyboard.layouts
            MenuItem {
                text: modelData.longName
                onTriggered: {
                    keyboard.currentLayout = index
                    keyboardButton.currentIndex = index
                }
            }
        }
    }
}

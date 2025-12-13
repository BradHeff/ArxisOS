import QtQuick 2.15
import SddmComponents 2.0

Rectangle {
    id: root
    width: 1920
    height: 1080
    color: "#1a1a2e"

    Image {
        anchors.fill: parent
        source: "background.png"
        fillMode: Image.PreserveAspectCrop
    }

    Image {
        id: logo
        source: "logo.png"
        width: 128
        height: 128
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: parent.height * 0.15
    }

    Text {
        text: "ArxisOS"
        color: "#ffffff"
        font.pixelSize: 36
        font.bold: true
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: logo.bottom
        anchors.topMargin: 20
    }

    Column {
        anchors.centerIn: parent
        spacing: 10

        TextBox {
            id: username
            width: 300
            height: 40
            text: userModel.lastUser
            font.pixelSize: 14
            KeyNavigation.tab: password
        }

        PasswordBox {
            id: password
            width: 300
            height: 40
            font.pixelSize: 14
            KeyNavigation.tab: loginButton
            onTextChanged: if (text != "") errorMessage.text = ""
        }

        Button {
            id: loginButton
            width: 300
            height: 40
            text: "Login"
            onClicked: sddm.login(username.text, password.text, sessionModel.lastIndex)
        }

        Text {
            id: errorMessage
            color: "#ff6b6b"
            font.pixelSize: 12
            anchors.horizontalCenter: parent.horizontalCenter
        }
    }

    Connections {
        target: sddm
        onLoginFailed: errorMessage.text = "Login failed"
    }
}

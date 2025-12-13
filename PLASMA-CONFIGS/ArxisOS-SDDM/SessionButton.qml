/*
 *   Copyright 2016 David Edmundson <davidedmundson@kde.org>
 *   Modified 2024 for ArxisOS - Plasma 6 compatibility
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU Library General Public License as
 *   published by the Free Software Foundation; either version 2 or
 *   (at your option) any later version.
 *
 *   This program is distributed in the hope that it will be useful,
 *   but WITHOUT ANY WARRANTY; without even the implied warranty of
 *   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *   GNU General Public License for more details
 *
 *   You should have received a copy of the GNU Library General Public
 *   License along with this program; if not, write to the
 *   Free Software Foundation, Inc.,
 *   51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
 */

import QtQuick
import QtQuick.Controls
import org.kde.kirigami as Kirigami

Button {
    id: root
    property int currentIndex: -1

    visible: sessionModel.count > 1

    text: i18nd("plasma_lookandfeel_org.kde.lookandfeel", "Desktop Session: %1", sessionModel.data(sessionModel.index(currentIndex, 0), Qt.DisplayRole) || "")

    font.pointSize: config.fontSize

    Component.onCompleted: {
        currentIndex = sessionModel.lastIndex
    }

    onClicked: sessionMenu.open()

    Menu {
        id: sessionMenu
        y: root.height

        Repeater {
            model: sessionModel
            MenuItem {
                text: model.name
                onTriggered: {
                    root.currentIndex = model.index
                }
            }
        }
    }
}

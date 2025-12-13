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
import QtQuick.Layouts
import QtQuick.Controls
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.kirigami as Kirigami

ColumnLayout {
    readonly property bool softwareRendering: GraphicsInfo.api === GraphicsInfo.Software

    Label {
        text: Qt.formatTime(timeSource.data["Local"]["DateTime"])
        color: config.highlight_color
        style: softwareRendering ? Text.Outline : Text.Normal
        styleColor: softwareRendering ? Kirigami.Theme.backgroundColor : "transparent" //no outline, doesn't matter
        font.pointSize: 16
        Layout.alignment: Qt.AlignHCenter
        font.family: config.font

    }
    Label {
        text: Qt.formatDateTime(new Date(), "'The day is' dddd MMMM d yyyy")
        color: config.highlight_color
        style: softwareRendering ? Text.Outline : Text.Normal
        styleColor: softwareRendering ? Kirigami.Theme.backgroundColor : "transparent" //no outline, doesn't matter
        font.pointSize: 16
        Layout.alignment: Qt.AlignHCenter
        font.family: config.font

    }
    Plasma5Support.DataSource {
        id: timeSource
        engine: "time"
        connectedSources: ["Local"]
        interval: 1000
    }
}

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    layerNamespacePlugin: "hyprsubs"

    // Last state from the hyprsubs plugin (`hyprctl hyprsubs -j` shape), null until known.
    property var subsState: null

    // Groups to draw: the ones with windows, plus the current one.
    readonly property var shownGroups: {
        if (!subsState)
            return [];
        const current = subsState.current ? subsState.current.group : -1;
        return subsState.groups.filter(g => g.windows > 0 || g.group === current);
    }

    // Hidden (not an empty pill) while the hyprsubs plugin isn't answering.
    _visibilityOverride: true
    _visibilityOverrideValue: subsState !== null

    function applyState(json) {
        try {
            const parsed = JSON.parse(json);
            if (parsed && Array.isArray(parsed.groups))
                subsState = parsed;
        } catch (e) {
            console.warn("hyprsubs widget: bad state:", e);
        }
    }

    // Initial state; after that the plugin pushes every change as a `hyprsubs>>{json}` event.
    Process {
        id: initialQuery
        command: ["hyprctl", "hyprsubs", "-j"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: root.applyState(text)
        }
    }

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name === "hyprsubs")
                root.applyState(event.data);
            else if (event.name === "configreloaded")
                initialQuery.running = true;
        }
    }

    horizontalBarPill: Component {
        Row {
            id: groupRow

            readonly property real pillHeight: Math.round(root.widgetThickness * 0.5)
            readonly property real dotSize: Math.max(4, Math.round(pillHeight * 0.4))
            readonly property real dotGap: Math.max(3, Math.round(dotSize * 0.6))

            spacing: Theme.spacingS

            Repeater {
                model: root.shownGroups

                delegate: Rectangle {
                    id: groupPill

                    required property var modelData

                    readonly property bool isCurrent: root.subsState?.current?.group === modelData.group
                    readonly property int currentSub: isCurrent ? root.subsState.current.sub : -1
                    readonly property color dotColor: isCurrent ? Theme.primaryText : Theme.surfaceText

                    anchors.verticalCenter: parent.verticalCenter
                    height: groupRow.pillHeight
                    width: Math.max(groupRow.pillHeight * 1.4, dots.implicitWidth + (groupRow.pillHeight - groupRow.dotSize) * 1.5)
                    radius: Math.min(Theme.cornerRadius, height / 2)
                    color: isCurrent ? Theme.primary : pillMouse.containsMouse ? Theme.withAlpha(Theme.surfaceText, 0.45) : Theme.surfaceTextAlpha

                    Behavior on width {
                        NumberAnimation {
                            duration: Theme.shortDuration
                            easing.type: Theme.standardEasing
                        }
                    }

                    Behavior on color {
                        ColorAnimation {
                            duration: Theme.shortDuration
                            easing.type: Theme.standardEasing
                        }
                    }

                    Row {
                        id: dots
                        anchors.centerIn: parent
                        spacing: groupRow.dotGap

                        Repeater {
                            model: groupPill.modelData.subs

                            delegate: Rectangle {
                                required property int modelData

                                readonly property bool isCurrentSub: modelData === groupPill.currentSub

                                width: groupRow.dotSize
                                height: groupRow.dotSize
                                radius: width / 2
                                color: isCurrentSub ? groupPill.dotColor : "transparent"
                                border.width: isCurrentSub ? 0 : Math.max(1, Math.round(groupRow.dotSize / 5))
                                border.color: Theme.withAlpha(groupPill.dotColor, groupPill.isCurrent ? 0.9 : 0.75)
                            }
                        }
                    }

                    MouseArea {
                        id: pillMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Hyprland.dispatch(`hyprsubs:group ${groupPill.modelData.group}`)
                    }
                }
            }

            DankIcon {
                visible: root.subsState?.row_mode ?? false
                anchors.verticalCenter: parent.verticalCenter
                name: "table_rows"
                size: root.iconSize
                color: rowModeMouse.containsMouse ? Theme.withAlpha(Theme.primary, 0.7) : Theme.primary

                MouseArea {
                    id: rowModeMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Hyprland.dispatch("hyprsubs:rowmode off")
                }
            }
        }
    }
}

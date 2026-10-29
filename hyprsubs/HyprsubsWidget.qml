import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    layerNamespacePlugin: "hyprsubs"

    // Last state from the hyprsubs plugin (`hyprctl hyprsubs -j` shape), null until known.
    property var subsState: null

    // Groups to draw: the ones with windows, plus the current one, as pills. Every empty group
    // number left of the last pill is a small dot (a 4-finger swipe stops there).
    readonly property var shownGroups: {
        if (!subsState)
            return [];
        const current = subsState.current ? subsState.current.group : -1;
        const pills = subsState.groups.filter(g => g.windows > 0 || g.group === current);
        const last = pills.reduce((max, g) => Math.max(max, g.group), 0);

        const items = [];
        for (let n = 1; n <= last; n++)
            items.push(pills.find(g => g.group === n) ?? {
                "group": n,
                "subs": [],
                "gap": true
            });
        return items;
    }

    // Hidden (not an empty pill) while the hyprsubs plugin isn't answering.
    _visibilityOverride: true
    _visibilityOverrideValue: subsState !== null

    // Lua configs dispatch Lua (hl.plugin.hyprsubs.<action>(arg)), hyprlang configs hyprsubs:<action> arg.
    function dispatch(action, arg) {
        if (HyprlandService.luaConfigActive)
            Hyprland.dispatch(`hl.plugin.hyprsubs.${action}(${JSON.stringify(arg)})`);
        else
            Hyprland.dispatch(`hyprsubs:${action} ${arg}`);
    }

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
            readonly property real gapSize: Math.max(3, Math.round(dotSize * 0.6))
            // space between pills, and the tighter space on either side of an empty-group dot
            readonly property real pillSpacing: Theme.spacingS
            readonly property real gapSpacing: Math.max(2, Math.round(Theme.spacingS / 2))

            spacing: 0

            Repeater {
                model: root.shownGroups

                delegate: Item {
                    id: slot

                    required property var modelData
                    required property int index

                    readonly property real leadingSpace: index === 0 ? 0 : modelData.gap === true || root.shownGroups[index - 1]?.gap ? groupRow.gapSpacing : groupRow.pillSpacing

                    anchors.verticalCenter: parent.verticalCenter
                    width: leadingSpace + groupPill.width
                    height: groupRow.pillHeight

                    Rectangle {
                        id: groupPill

                        readonly property var modelData: slot.modelData
                        readonly property bool isGap: modelData.gap === true
                        readonly property bool isCurrent: root.subsState?.current?.group === modelData.group
                        readonly property int currentSub: isCurrent ? root.subsState.current.sub : -1
                        readonly property color dotColor: isCurrent ? Theme.primaryText : Theme.surfaceText

                        x: slot.leadingSpace
                        anchors.verticalCenter: parent.verticalCenter
                        height: isGap ? groupRow.gapSize : groupRow.pillHeight
                        width: isGap ? groupRow.gapSize : Math.max(groupRow.pillHeight * 1.4, dots.implicitWidth + (groupRow.pillHeight - groupRow.dotSize) * 1.5)
                        radius: isGap ? width / 2 : Math.min(Theme.cornerRadius, height / 2)
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
                            onClicked: root.dispatch("group", groupPill.modelData.group)
                        }
                    }
                }
            }

            // keeps the pill spacing in front of the row mode icon
            Item {
                visible: rowModeIcon.visible
                width: groupRow.pillSpacing
                height: 1
            }

            DankIcon {
                id: rowModeIcon
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
                    onClicked: root.dispatch("rowmode", "off")
                }
            }
        }
    }
}

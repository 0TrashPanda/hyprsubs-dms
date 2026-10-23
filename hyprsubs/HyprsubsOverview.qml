import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Hyprland
import qs.Common
import qs.Services
import qs.Widgets

// Grid overview of all groups (columns) and subs (stacked, sub 1 at the bottom).
// `dms ipc call hyprsubs toggle` opens / closes it; arrows move, Enter or click jumps, Esc closes.
Item {
    id: root

    property var pluginService: null
    property string pluginId: "hyprsubs"

    property bool open: false

    // plugin setting: group.sub number on empty subs instead of a + icon
    property bool emptyNumbers: pluginService ? pluginService.loadPluginData(pluginId, "emptySlotNumbers", true) : true

    // plugin setting: key that closes the hovered window ("" = off)
    property string closeKey: pluginService ? pluginService.loadPluginData(pluginId, "closeKey", "q") : "q"

    // plugin setting: what the close key does on a window that already refused to close
    // ("jump" to it, "kill" it, or "none")
    property string closeAgain: pluginService ? pluginService.loadPluginData(pluginId, "closeAgain", "jump") : "jump"

    // windows that were asked to close and are still there, by address
    property var pendingClose: ({})

    // address of the window under the cursor
    property string hoveredAddress: ""

    Connections {
        target: root.pluginService

        function onPluginDataChanged(changedPluginId) {
            if (changedPluginId === root.pluginId)
                root.emptyNumbers = root.pluginService.loadPluginData(root.pluginId, "emptySlotNumbers", true);
                root.closeKey = root.pluginService.loadPluginData(root.pluginId, "closeKey", "q");
                root.closeAgain = root.pluginService.loadPluginData(root.pluginId, "closeAgain", "jump");
        }
    }

    // Last state from the hyprsubs plugin (`hyprctl hyprsubs -j` shape), null until known.
    property var subsState: null

    // Selection: group number and index into that group's (ascending) subs.
    property int selGroup: 1
    property int selIdx: 0

    readonly property int minGroups: 10
    readonly property real emptyWeight: 0.2
    readonly property real screenMargin: 12
    readonly property real panelPadding: 10
    readonly property real gap: 6

    readonly property var targetScreen: {
        const name = Hyprland.focusedMonitor?.name;
        return Quickshell.screens.find(s => s.name === name) ?? Quickshell.screens[0] ?? null;
    }

    // One entry per column: 1..max(10, highest used group).
    readonly property var columns: {
        const byGroup = {};
        let maxGroup = minGroups;
        for (const g of (subsState?.groups ?? [])) {
            byGroup[g.group] = g;
            maxGroup = Math.max(maxGroup, g.group);
        }
        const current = subsState?.current?.group ?? -1;
        const out = [];
        for (let n = 1; n <= maxGroup; ++n) {
            const g = byGroup[n];
            const used = !!g && g.windows > 0;
            out.push({
                group: n,
                subs: g ? g.subs : [],
                occupied: used || n === current
            });
        }
        return out;
    }

    function dispatch(action, arg) {
        if (HyprlandService.luaConfigActive)
            Hyprland.dispatch(`hl.plugin.hyprsubs.${action}(${JSON.stringify(arg)})`);
        else
            Hyprland.dispatch(`hyprsubs:${action} ${arg}`);
    }

    // DMS's HyprlandService.closeWindow passes a bare selector, which Lua configs treat as "close the
    // active window"; the table form targets the given window.
    function closeWindow(address) {
        closeRefresh.address = address;
        closeRefresh.restart();

        const selector = address.startsWith("0x") ? `address:${address}` : `address:0x${address}`;
        if (HyprlandService.luaConfigActive)
            Hyprland.dispatch(`hl.dsp.window.close({ window = "${selector}" })`);
        else
            Hyprland.dispatch(`closewindow ${selector}`);
    }

    function toplevelFor(address) {
        return (Hyprland.toplevels?.values ?? []).find(t => t.lastIpcObject?.address === address) ?? null;
    }

    // Close key / middle-click: ask the window to close; if it already refused once, do what the
    // "closeAgain" setting says.
    function closeOrEscalate(address) {
        if (!pendingClose[address]) {
            closeWindow(address);
            return;
        }

        if (closeAgain === "jump") {
            closeOverview();
            HyprlandService.focusWindow(address);
        } else if (closeAgain === "kill") {
            killWindow(address);
            const next = Object.assign({}, pendingClose);
            delete next[address];
            pendingClose = next;
        }
    }

    function killWindow(address) {
        const selector = address.startsWith("0x") ? `address:${address}` : `address:0x${address}`;
        if (HyprlandService.luaConfigActive) {
            Hyprland.dispatch(`hl.dsp.window.kill({ window = "${selector}" })`);
        } else {
            const pid = toplevelFor(address)?.lastIpcObject?.pid;
            if (pid)
                Quickshell.execDetached(["kill", "-9", String(pid)]);
        }
    }

    // The window may refuse to close (a confirm dialog, an unsaved-changes prompt): once it had time
    // to answer, re-read the window list and restart the thumbnail's capture so it shows what it
    // looks like now instead of a stale frame.
    signal recapture(string address)

    Timer {
        id: closeRefresh
        property string address: ""
        interval: 350
        onTriggered: {
            Hyprland.refreshToplevels();
            root.recapture(address);
            pendingCheck.address = address;
            pendingCheck.restart();
        }
    }

    // after the refresh: still there means it refused (or is waiting on a prompt)
    Timer {
        id: pendingCheck
        property string address: ""
        interval: 400
        onTriggered: {
            if (!root.toplevelFor(address))
                return;
            const next = Object.assign({}, root.pendingClose);
            next[address] = true;
            root.pendingClose = next;
        }
    }

    function applyState(json) {
        try {
            const parsed = JSON.parse(json);
            if (parsed && Array.isArray(parsed.groups))
                subsState = parsed;
        } catch (e) {
            console.warn("hyprsubs overview: bad state:", e);
        }
    }

    function wsId(group, sub) {
        return (sub - 1) * 100 + group;
    }

    function colFor(group) {
        return columns[group - 1] ?? null;
    }

    function openOverview() {
        Hyprland.refreshToplevels();
        Hyprland.refreshWorkspaces();
        Hyprland.refreshMonitors();

        const cur = subsState?.current;
        if (cur) {
            selGroup = cur.group;
            const col = colFor(cur.group);
            selIdx = slotForSub(col, cur.sub);
        }
        open = true;
    }

    function closeOverview() {
        hoveredAddress = "";
        pendingClose = ({});
        open = false;
    }

    function commit() {
        const col = colFor(selGroup);
        const sub = subForSlot(col, selIdx);
        closeOverview();
        HyprlandService.focusWorkspace(wsId(selGroup, sub));
    }

    function moveGroup(dir) {
        const n = Math.max(1, Math.min(columns.length, selGroup + dir));
        selGroup = n;
        const col = colFor(n);
        // land on the same row, clamped
        selIdx = Math.max(0, Math.min(selIdx, slotCount(col) - 1));
    }

    // Slots in a column, bottom to top. A column in use shows every sub number from 1 up to one
    // above its top sub (the gaps and the new one are empty); an unused column just lists its subs.
    function slotCount(col) {
        if (!col || col.subs.length === 0)
            return 1;
        if (col.occupied)
            return col.subs[col.subs.length - 1] + 1;
        return col.subs.length;
    }

    function subForSlot(col, idx) {
        if (!col || col.subs.length === 0)
            return 1;
        return col.occupied ? idx + 1 : col.subs[idx];
    }

    function slotForSub(col, sub) {
        if (!col || col.subs.length === 0)
            return 0;
        return col.occupied ? sub - 1 : Math.max(0, col.subs.indexOf(sub));
    }

    function moveSub(dir) {
        selIdx = Math.max(0, Math.min(slotCount(colFor(selGroup)) - 1, selIdx + dir));
    }

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

    IpcHandler {
        target: "hyprsubs"

        function toggle(): string {
            if (root.open)
                root.closeOverview();
            else
                root.openOverview();
            return root.open ? "OVERVIEW_OPEN" : "OVERVIEW_CLOSED";
        }

        function open(): string {
            root.openOverview();
            return "OVERVIEW_OPEN";
        }

        function close(): string {
            root.closeOverview();
            return "OVERVIEW_CLOSED";
        }
    }

    Loader {
        active: root.open && root.targetScreen !== null

        sourceComponent: PanelWindow {
            id: panel

            screen: root.targetScreen
            color: "transparent"

            WlrLayershell.namespace: "dms:hyprsubs-overview"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.exclusiveZone: -1
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

            anchors {
                top: true
                left: true
                right: true
                bottom: true
            }

            readonly property var monitor: Hyprland.monitorFor(screen)
            readonly property real monX: monitor?.lastIpcObject?.x ?? 0
            readonly property real monY: monitor?.lastIpcObject?.y ?? 0
            readonly property real aspect: screen.height / screen.width

            readonly property var cols: root.columns
            readonly property int usedCount: cols.filter(c => c.occupied).length
            readonly property int emptyCount: cols.length - usedCount
            readonly property int rows: Math.max(1, cols.reduce((m, c) => Math.max(m, root.slotCount(c)), 1))

            // Columns in use keep the screen's shape, as large as width and height allow. Width the
            // rows don't leave room for goes to the empty columns instead, up to a full column.
            readonly property real availW: width - 2 * (root.screenMargin + root.panelPadding)
            readonly property real availH: height - 2 * (root.screenMargin + root.panelPadding)
            readonly property real gaps: (cols.length - 1) * root.gap
            readonly property real unitByWidth: (availW - gaps) / (usedCount + emptyCount * root.emptyWeight)
            readonly property real unitByHeight: (availH - (rows - 1) * root.gap) / (rows * aspect)
            readonly property real unit: Math.max(40, Math.min(unitByWidth, unitByHeight, 520))
            readonly property real emptyW: emptyCount > 0 ? Math.min(unit, Math.max(unit * root.emptyWeight, (availW - gaps - usedCount * unit) / emptyCount)) : 0

            readonly property real cellH: unit * aspect
            readonly property real gridWidth: usedCount * unit + emptyCount * emptyW + gaps
            readonly property real gridHeight: rows * cellH + (rows - 1) * root.gap

            // Every slot as a rect inside the grid; sub 1 of each column sits at the bottom.
            readonly property var cells: {
                const out = [];
                let x = 0;
                for (const c of cols) {
                    const w = c.occupied ? unit : emptyW;
                    const n = root.slotCount(c);
                    for (let i = 0; i < n; ++i) {
                        const sub = root.subForSlot(c, i);
                        out.push({
                            group: c.group,
                            sub: sub,
                            idx: i,
                            ws: root.wsId(c.group, sub),
                            exists: c.subs.includes(sub),
                            occupied: c.occupied,
                            x: x,
                            y: gridHeight - (i + 1) * cellH - i * root.gap,
                            w: w,
                            h: cellH
                        });
                    }
                    x += w + root.gap;
                }
                return out;
            }

            readonly property var cellByWs: {
                const m = {};
                for (const c of cells) {
                    if (c.exists)
                        m[c.ws] = c;
                }
                return m;
            }

            // slot under a dragged window, or null
            property var dropCell: null

            Rectangle {
                anchors.fill: parent
                color: "black"
                opacity: 0.5

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.closeOverview()
                }
            }

            FocusScope {
                anchors.fill: parent
                focus: true
                Component.onCompleted: forceActiveFocus()

                Keys.onEscapePressed: root.closeOverview()
                Keys.onPressed: event => {
                    if (root.closeKey !== "" && event.text.toLowerCase() === root.closeKey.toLowerCase()) {
                        if (root.hoveredAddress !== "") {
                            root.closeOrEscalate(root.hoveredAddress);
                        }
                    } else if (event.key === Qt.Key_Left)
                        root.moveGroup(-1);
                    else if (event.key === Qt.Key_Right)
                        root.moveGroup(1);
                    else if (event.key === Qt.Key_Up)
                        root.moveSub(1);
                    else if (event.key === Qt.Key_Down)
                        root.moveSub(-1);
                    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                        root.commit();
                    else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9)
                        root.selGroup = event.key - Qt.Key_0;
                    else if (event.key === Qt.Key_0)
                        root.selGroup = 10;
                    else
                        return;
                    event.accepted = true;
                }
            }

            Rectangle {
                id: background
                anchors.centerIn: parent
                width: panel.gridWidth + 2 * root.panelPadding
                height: panel.gridHeight + 2 * root.panelPadding
                radius: Theme.cornerRadius
                color: Theme.surfaceContainer

                ElevationShadow {
                    anchors.fill: parent
                    z: -1
                    level: Theme.elevationLevel2
                    fallbackOffset: 4
                    targetRadius: Theme.cornerRadius
                    targetColor: Theme.surfaceContainer
                    shadowOpacity: Theme.elevationLevel2 && Theme.elevationLevel2.alpha !== undefined ? Theme.elevationLevel2.alpha : 0.25
                    shadowEnabled: Theme.elevationEnabled
                }

                // swallow clicks on the panel itself so they don't close the overview
                MouseArea {
                    anchors.fill: parent
                }

                Item {
                    id: grid
                    x: root.panelPadding
                    y: root.panelPadding
                    width: panel.gridWidth
                    height: panel.gridHeight

                    // slots
                    Repeater {
                        model: panel.cells

                        delegate: Rectangle {
                            id: cell

                            required property var modelData

                            readonly property bool isCurrent: root.subsState?.current?.workspace === modelData.ws
                            readonly property bool isSelected: root.selGroup === modelData.group && root.selIdx === modelData.idx
                            readonly property bool isDropTarget: panel.dropCell?.ws === modelData.ws

                            x: modelData.x
                            y: modelData.y
                            width: modelData.w
                            height: modelData.h
                            radius: Theme.cornerRadius
                            color: isDropTarget ? Qt.lighter(Theme.surfaceContainer, 1.25) : modelData.exists ? Theme.surfaceContainer : Theme.withAlpha(Theme.surfaceContainer, 0.3)
                            border.width: 2
                            border.color: isDropTarget ? Theme.surfaceVariant : isSelected ? Theme.primary : isCurrent ? Theme.withAlpha(Theme.primary, 0.55) : Theme.withAlpha(Theme.primary, 0)

                            Behavior on border.color {
                                ColorAnimation {
                                    duration: Theme.shortDuration
                                }
                            }

                            // group.sub, or just the group on a first sub / narrow column
                            StyledText {
                                anchors.centerIn: parent
                                visible: modelData.exists || !modelData.occupied || root.emptyNumbers
                                text: modelData.occupied ? `${modelData.group}.${modelData.sub}` : modelData.group
                                font.pixelSize: Math.max(12, Math.min(parent.width * 0.4, parent.height * 0.5))
                                font.weight: Font.DemiBold
                                color: Theme.withAlpha(Theme.surfaceText, modelData.exists ? 0.2 : 0.1)
                            }

                            DankIcon {
                                anchors.centerIn: parent
                                visible: !modelData.exists && modelData.occupied && !root.emptyNumbers
                                name: "add"
                                size: Math.max(16, Math.min(parent.width, parent.height) * 0.3)
                                color: Theme.withAlpha(Theme.surfaceText, 0.25)
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onEntered: {
                                    root.selGroup = cell.modelData.group;
                                    root.selIdx = cell.modelData.idx;
                                }
                                onClicked: {
                                    root.selGroup = cell.modelData.group;
                                    root.selIdx = cell.modelData.idx;
                                    root.commit();
                                }
                            }
                        }
                    }

                    // windows, above the slots so a drag crosses them
                    Repeater {
                        model: Hyprland.toplevels

                        delegate: Item {
                            id: win

                            required property var modelData

                            readonly property var info: modelData.lastIpcObject
                            readonly property var slot: panel.cellByWs[info?.workspace?.id ?? -1] ?? null
                            readonly property real s: slot ? slot.w / panel.screen.width : 0
                            readonly property real offX: slot ? (slot.w - panel.screen.width * s) / 2 : 0
                            readonly property real offY: slot ? (slot.h - panel.screen.height * s) / 2 : 0
                            readonly property real rawX: offX + ((info?.at?.[0] ?? 0) - panel.monX) * s
                            readonly property real rawY: offY + ((info?.at?.[1] ?? 0) - panel.monY) * s
                            readonly property real rawW: (info?.size?.[0] ?? 0) * s
                            readonly property real rawH: (info?.size?.[1] ?? 0) * s
                            readonly property real clipL: Math.max(0, rawX)
                            readonly property real clipT: Math.max(0, rawY)
                            readonly property real clipR: Math.min(slot?.w ?? 0, rawX + rawW)
                            readonly property real clipB: Math.min(slot?.h ?? 0, rawY + rawH)

                            readonly property real initX: (slot?.x ?? 0) + clipL
                            readonly property real initY: (slot?.y ?? 0) + clipT
                            property bool dragging: false
                            property bool hovered: false
                            property bool capturing: true

                            Connections {
                                target: root

                                function onRecapture(address) {
                                    if (address !== (win.info?.address ?? ""))
                                        return;
                                    win.capturing = false;
                                    Qt.callLater(() => win.capturing = true);
                                }
                            }

                            readonly property var entry: DesktopEntries.heuristicLookup(Paths.moddedAppId(info?.class ?? ""))
                            readonly property string iconPath: Paths.getAppIcon(info?.class ?? "", entry) || Quickshell.iconPath("application-x-executable", "image-missing")

                            visible: slot !== null && (info?.mapped ?? true) && clipR > clipL && clipB > clipT
                            width: Math.max(0, clipR - clipL)
                            height: Math.max(0, clipB - clipT)
                            z: dragging ? 10 : 1

                            Component.onCompleted: {
                                x = initX;
                                y = initY;
                            }
                            onInitXChanged: if (!dragging) x = initX
                            onInitYChanged: if (!dragging) y = initY

                            ClippingRectangle {
                                anchors.fill: parent
                                radius: Theme.cornerRadius
                                color: "transparent"

                                ScreencopyView {
                                    anchors.fill: parent
                                    captureSource: win.visible && win.capturing ? win.modelData.wayland : null
                                    live: true

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: Theme.cornerRadius
                                        color: dragArea.pressed ? Theme.withAlpha(Theme.surfaceContainerHigh, 0.5) : win.hovered ? Theme.withAlpha(Theme.surfaceVariant, 0.3) : Theme.withAlpha(Theme.surfaceContainer, 0.1)
                                        border.color: Theme.withAlpha(Theme.outline, 0.3)
                                        border.width: 1
                                    }

                                    Image {
                                        anchors.centerIn: parent
                                        readonly property real sz: Math.min(win.width, win.height) * 0.3
                                        width: sz
                                        height: sz
                                        sourceSize: Qt.size(sz, sz)
                                        source: win.iconPath
                                    }
                                }
                            }

                            // asked to close and still open
                            Rectangle {
                                visible: root.pendingClose[win.info?.address ?? ""] === true
                                anchors.top: parent.top
                                anchors.right: parent.right
                                anchors.margins: 4
                                width: Math.max(18, Math.min(parent.width, parent.height) * 0.22)
                                height: width
                                radius: width / 2
                                color: Theme.primary

                                DankIcon {
                                    anchors.centerIn: parent
                                    name: "hourglass_top"
                                    size: parent.width * 0.65
                                    color: Theme.primaryText
                                }
                            }

                            MouseArea {
                                id: dragArea
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                                drag.target: win
                                onEntered: {
                                    win.hovered = true;
                                    root.hoveredAddress = win.info?.address ?? "";
                                }
                                onExited: {
                                    win.hovered = false;
                                    if (root.hoveredAddress === (win.info?.address ?? ""))
                                        root.hoveredAddress = "";
                                }

                                // slot under the cursor while dragging
                                function updateDrop(mouse) {
                                    const p = dragArea.mapToItem(grid, mouse.x, mouse.y);
                                    panel.dropCell = panel.cells.find(c => p.x >= c.x && p.x <= c.x + c.w && p.y >= c.y && p.y <= c.y + c.h) ?? null;
                                }

                                onPressed: mouse => {
                                    if (mouse.button === Qt.LeftButton)
                                        win.dragging = true;
                                }

                                onPositionChanged: mouse => {
                                    if (win.dragging)
                                        updateDrop(mouse);
                                }

                                onReleased: {
                                    const target = panel.dropCell;
                                    const from = win.info?.workspace?.id;
                                    win.dragging = false;
                                    panel.dropCell = null;

                                    if (target && target.ws !== from)
                                        HyprlandService.moveToWorkspace(target.ws, win.info?.address, false);

                                    // snap back; the refreshed state moves it to its new slot
                                    win.x = win.initX;
                                    win.y = win.initY;
                                    Qt.callLater(() => {
                                        Hyprland.refreshToplevels();
                                        Hyprland.refreshWorkspaces();
                                    });
                                }

                                onClicked: event => {
                                    const address = win.info?.address;
                                    if (!address)
                                        return;
                                    if (event.button === Qt.LeftButton) {
                                        root.closeOverview();
                                        HyprlandService.focusWindow(address);
                                    } else if (event.button === Qt.MiddleButton) {
                                        root.closeOrEscalate(address);
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

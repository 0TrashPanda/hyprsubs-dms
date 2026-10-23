import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "hyprsubs"

    StyledText {
        text: "Super+Tab overview"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    ToggleSetting {
        settingKey: "emptySlotNumbers"
        label: "Number empty subs"
        description: "Show the group.sub number on empty subs instead of a + icon"
        defaultValue: true
    }

    StringSetting {
        settingKey: "closeKey"
        label: "Close window key"
        description: "Press this key in the overview to close the window under the cursor. Leave empty to disable."
        placeholder: "q"
        defaultValue: "q"
    }

    SelectionSetting {
        settingKey: "closeAgain"
        label: "Close key on a window that didn't close"
        description: "A window that is still open after the close key shows an hourglass (it is probably asking something). Pressing the key on it again does this."
        options: [
            {label: "Jump to the window", value: "jump"},
            {label: "Force-kill the window", value: "kill"},
            {label: "Do nothing", value: "none"}
        ]
        defaultValue: "jump"
    }
}

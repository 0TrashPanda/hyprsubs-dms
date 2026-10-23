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
}

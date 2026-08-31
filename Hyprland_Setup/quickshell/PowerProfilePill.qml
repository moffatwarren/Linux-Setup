import Quickshell
import Quickshell.Services.UPower
import QtQuick

// waybar: "power-profiles-daemon" -- icon per profile, click cycles.
Pill {
    id: root

    readonly property int profile: PowerProfiles.profile

    // Icons are private-use nerd font codepoints copied from waybar's
    // format-icons, written as \u escapes so they survive editing.
    label: {
        switch (profile) {
        case PowerProfile.Performance: return "\uf0e7";
        case PowerProfile.Balanced:    return "\uf24e";
        case PowerProfile.PowerSaver:  return "\uf06c";
        default:                       return "\uf0e7";
        }
    }
    labelColor: profile === PowerProfile.Performance ? Theme.peach
              : profile === PowerProfile.PowerSaver ? Theme.green
              : Theme.text

    // Cycle saver -> balanced -> performance, skipping performance where unsupported.
    onClicked: {
        if (profile === PowerProfile.PowerSaver) PowerProfiles.profile = PowerProfile.Balanced;
        else if (profile === PowerProfile.Balanced && PowerProfiles.hasPerformanceProfile) PowerProfiles.profile = PowerProfile.Performance;
        else PowerProfiles.profile = PowerProfile.PowerSaver;
    }
}

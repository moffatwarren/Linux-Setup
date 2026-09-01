import QtQuick 2.0
import "../utils/ConfigManager.js" as ConfigManager

Rectangle {
    id: root
    clip: true
    antialiasing: true
    
    property alias passwordInput: passwordInput
    property alias passwordText: passwordInput.text
    property bool enabled: true
    property bool fadeInComplete: true
    property int fadeInDuration: 300
    property real elementOpacity: 1.0
    property bool hasError: false
    property bool showPasswordButton: config.boolValue("showPasswordButton") || false
    property bool passwordVisible: false
    
    // Config properties
    width: config.intValue("passwordFieldWidth") || 250
    height: config.intValue("passwordFieldHeight") || 35
    color: config.stringValue("passwordFieldBackground") || '#333333'
    radius: config.intValue("passwordFieldRadius") || 16
    border.color: root.hasError
        ? ConfigManager.colorOr(config, "loginErrorColor", '#ff3117')
        : (root.enabled
            ? ConfigManager.colorOr(config, "passwordFieldBorderActive", '#aaaaaa')
            : ConfigManager.colorOr(config, "passwordFieldBorder", '#888888'))
    border.width: root.hasError
        ? ConfigManager.intOr(config, "loginErrorBorderWidth", 4)
        : (root.enabled
            ? ConfigManager.intOr(config, "passwordFieldBorderWidthActive", 2)
            : ConfigManager.intOr(config, "passwordFieldBorderWidth", 1))
    property int animationDuration: config.intValue("animationDuration") || 200
    property int sideMargin: config.intValue("passwordFieldMargin") || 20
    
    signal loginRequested()
    
    opacity: (root.fadeInComplete ? 1 : 0) * root.elementOpacity
    
    Behavior on opacity {
        NumberAnimation { duration: root.fadeInDuration; easing.type: Easing.OutCubic }
    }
    
    Behavior on border.width {
        NumberAnimation { duration: root.animationDuration; easing.type: Easing.OutCubic }
    }
    
    Behavior on border.color {
        ColorAnimation { duration: root.animationDuration; easing.type: Easing.OutCubic }
    }
    
    // Shake animation on error
    property real shakeOffset: 0
    
    onHasErrorChanged: {
        if (hasError && (config.boolValue("loginErrorShake") !== false)) {
            shakeAnimation.start()
            // Reset error after animation duration (5 * 50ms = 250ms)
            errorResetTimer.start()
        } else {
            shakeOffset = 0
            errorResetTimer.stop()
        }
    }
    
    SequentialAnimation {
        id: shakeAnimation
        PropertyAnimation {
            target: root
            property: "shakeOffset"
            from: 0
            to: -10
            duration: 50
        }
        PropertyAnimation {
            target: root
            property: "shakeOffset"
            from: -10
            to: 10
            duration: 50
        }
        PropertyAnimation {
            target: root
            property: "shakeOffset"
            from: 10
            to: -10
            duration: 50
        }
        PropertyAnimation {
            target: root
            property: "shakeOffset"
            from: -10
            to: 10
            duration: 50
        }
        PropertyAnimation {
            target: root
            property: "shakeOffset"
            from: 10
            to: 0
            duration: 50
        }
    }
    
    Timer {
        id: errorResetTimer
        interval: 250 // Total animation duration (5 * 50ms)
        onTriggered: {
            if (root.hasError) {
                root.hasError = false
            }
        }
    }
    
    transform: Translate {
        x: root.shakeOffset
    }
    
    // Subtle glow when focused. Was a hardcoded '#cccccc', which no config key
    // could reach -- set passwordFieldGlow=none to drop it entirely.
    property color glowColor: ConfigManager.colorOr(config, "passwordFieldGlow", '#cccccc')
    property bool showGlow: root.glowColor.a > 0

    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        color: "transparent"
        border.color: root.glowColor
        border.width: (root.enabled && root.showGlow) ? 1 : 0
        opacity: (root.enabled && root.showGlow) ? 0.3 : 0
        antialiasing: true
        
        Behavior on opacity {
            NumberAnimation { duration: root.animationDuration; easing.type: Easing.OutCubic }
        }
        
        Behavior on border.width {
            NumberAnimation { duration: root.animationDuration; easing.type: Easing.OutCubic }
        }
    }
    
    Item {
        anchors.fill: parent
        anchors.leftMargin: root.sideMargin
        anchors.rightMargin: root.sideMargin
        clip: true
        
        TextInput {
            id: passwordInput
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: parent.height
            color: config.stringValue("textColor") || "#c4c4c4"
            echoMode: root.passwordVisible ? TextInput.Normal : TextInput.Password
            verticalAlignment: TextInput.AlignVCenter
            horizontalAlignment: TextInput.AlignHCenter
            font.pixelSize: config.intValue("passwordFieldFontSize") || 16
            font.family: config.stringValue("fontFamily") || "JetBrains Mono Nerd Font"
            font.letterSpacing: config.intValue("passwordFieldLetterSpacing") || 2
            passwordCharacter: {
                var maskChar = config.stringValue("passwordCharacter")
                return (maskChar && maskChar !== "") ? maskChar : "●"
            }
            selectByMouse: false
            selectionColor: "transparent"
            enabled: root.enabled
            
            cursorDelegate: Rectangle {
                color: "transparent"
            }
            
            Keys.onPressed: {
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    root.loginRequested()
                    event.accepted = true
                } else if (event.key === Qt.Key_Up || event.key === Qt.Key_Down) {
                    // Forward Up/Down to parent
                    event.accepted = false
                }
            }
        }

        // Placeholder. TextInput has no placeholderText (that is TextField, from
        // Controls, which this theme does not import), so it is a plain Text laid
        // over the input and hidden as soon as anything is typed.
        Text {
            anchors.fill: parent
            visible: passwordInput.text.length === 0
            text: config.stringValue("passwordPlaceholder")
            color: ConfigManager.colorOr(config, "passwordPlaceholderColor",
                                         config.stringValue("textColor") || "#c4c4c4")
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            font.pixelSize: config.intValue("passwordFieldFontSize") || 16
            font.family: config.stringValue("fontFamily") || "JetBrains Mono Nerd Font"
        }
        
        // Show/Hide password button
        MouseArea {
            id: showPasswordButtonArea
            visible: root.showPasswordButton
            width: root.showPasswordButton ? 24 : 0
            height: 24
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.rightMargin: 5
            
            onClicked: {
                root.passwordVisible = !root.passwordVisible
            }
            
            Text {
                anchors.centerIn: parent
                text: root.passwordVisible ? "👁️" : "👁️‍🗨️"
                color: config.stringValue("textColor") || "#c4c4c4"
                font.pixelSize: 16
                font.family: config.stringValue("fontFamily") || "JetBrains Mono Nerd Font"
            }
        }
    }
}


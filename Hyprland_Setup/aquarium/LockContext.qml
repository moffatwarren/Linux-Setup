import QtQuick
import Quickshell
import Quickshell.Services.Pam

// What every monitor's lock surface shares: one password, one check in progress and
// one idle state, so the box reads the same on every screen whichever has the keyboard.
Scope {
    id: root

    signal unlocked()

    // hyprlock's own PAM service: the same check the machine's lock has always used,
    // including pam_faillock, so this lock is exactly as strict and no stricter.
    property string pamConfig: "hyprlock"
    property string pamConfigDirectory: "/etc/pam.d"

    property string password: ""
    property bool checking: false
    property string failure: ""

    // Whether the clock and password box are showing. Idle leaves just the tank.
    property bool awake: true

    // A message PAM sent during this attempt, such as faillock's "account is locked".
    // It says more than the generic failure does, so it wins when there is one.
    property string pamNote: ""

    function poke() {
        awake = true;
        idle.restart();
    }

    function submit() {
        if (checking || password === "")
            return;
        checking = true;
        failure = "";
        pamNote = "";
        if (!pam.start())
            finish("Could not start the password check");
    }

    function finish(reason) {
        checking = false;
        password = "";
        failure = pamNote || reason;
        poke();
    }

    onPasswordChanged: if (password !== "") failure = ""

    Timer {
        id: idle
        interval: 10000
        running: true
        onTriggered: {
            if (root.checking) {
                restart();
                return;
            }
            // A half-typed password is not left sitting there for whoever comes along.
            root.password = "";
            root.failure = "";
            root.awake = false;
        }
    }

    PamContext {
        id: pam

        config: root.pamConfig
        configDirectory: root.pamConfigDirectory

        onPamMessage: {
            if (responseRequired)
                respond(root.password);
            else if (message !== "")
                root.pamNote = message;
        }

        onCompleted: result => {
            if (result === PamResult.Success) {
                root.checking = false;
                root.password = "";
                root.unlocked();
            } else if (result === PamResult.MaxTries) {
                root.finish("Too many attempts");
            } else if (result === PamResult.Failed) {
                root.finish("Wrong password");
            } else {
                root.finish("The password check failed");
            }
        }

        onError: error => root.finish("The password check failed")
    }
}

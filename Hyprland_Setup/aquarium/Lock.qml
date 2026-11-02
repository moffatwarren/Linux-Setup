import QtQuick
import Quickshell
import Quickshell.Wayland

// The session lock. It locks as soon as it exists and quits once unlocked, so one run
// of the process is one lock. WlSessionLock makes a surface per screen by itself, and
// keeps that true as monitors come and go.
Scope {
    id: root

    readonly property alias context: ctx
    property alias pamConfig: ctx.pamConfig
    property alias pamConfigDirectory: ctx.pamConfigDirectory

    // Touched once the compositor confirms the lock, which is what lock.sh waits on
    // before it will let the machine suspend.
    readonly property string readyPath: Quickshell.env("AQUARIUM_LOCK_READY") || ""

    // Quickshell reloads a config when its files change. A deploy over a locked session
    // should not be able to swap the lock screen out from under it.
    Component.onCompleted: Quickshell.watchFiles = false

    // Quits from here as well as from onLockStateChanged, because releasing a lock does
    // not emit lockStateChanged (measured on 0.3.2: `secure` goes false and the surfaces
    // go, and that handler never runs), so waiting on it leaves the process behind.
    function unlock() {
        lock.locked = false;
        quitLater.start();
    }

    LockContext {
        id: ctx
        onUnlocked: root.unlock()
    }

    WlSessionLock {
        id: lock

        locked: true

        onSecureStateChanged: {
            console.info("aquarium-lock: secure =", secure);
            if (secure && root.readyPath !== "")
                Quickshell.execDetached(["touch", root.readyPath]);
        }

        // For the compositor refusing the lock, for instance because another locker
        // holds it: there is nothing left for this process to do.
        onLockStateChanged: {
            console.info("aquarium-lock: locked =", locked);
            if (!locked)
                quitLater.start();
        }

        WlSessionLockSurface {
            id: surface

            color: "black"

            LockSurface {
                anchors.fill: parent
                context: ctx
            }

            onScreenChanged: if (screen) console.info("aquarium-lock: surface on", screen.name)
            Component.onDestruction: console.info("aquarium-lock: surface gone")
        }
    }

    // Leaves time for the unlock to reach the compositor. A client that exits while
    // still holding the lock leaves the session locked with nothing to type into.
    Timer {
        id: quitLater
        interval: 300
        onTriggered: Qt.quit()
    }
}

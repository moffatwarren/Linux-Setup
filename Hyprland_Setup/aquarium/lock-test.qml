// The lock with a safety net, for testing. Run it through lock-test.sh, not directly.
// It unlocks itself after AQUARIUM_TEST_SECONDS whatever else happens. The PAM override
// and the IPC below exist only in this file, so that the unlock paths can be exercised
// in a throwaway compositor without a real password; the real lock has neither.
import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root

    readonly property int seconds: parseInt(Quickshell.env("AQUARIUM_TEST_SECONDS")) || 60

    Lock {
        id: lock
        pamConfig: Quickshell.env("AQUARIUM_TEST_PAM") || "hyprlock"
        pamConfigDirectory: Quickshell.env("AQUARIUM_TEST_PAM_DIR") || "/etc/pam.d"
    }

    Timer {
        interval: root.seconds * 1000
        running: true
        onTriggered: {
            console.info("aquarium-lock: test timer expired, unlocking");
            lock.unlock();
        }
    }

    IpcHandler {
        target: "locktest"

        function attempt(text: string): void {
            lock.context.password = text;
            lock.context.submit();
        }

        // The visitors' first visits are a minute or two away; these bring one in now.
        function shark(): void {
            lock.ocean.summonShark();
        }

        function diver(): void {
            lock.ocean.summonDiver();
        }

        function state(): string {
            const c = lock.context;
            return "awake=" + c.awake + " checking=" + c.checking + " typed=" + c.password.length + " failure=" + c.failure;
        }
    }
}

pragma Singleton

import Quickshell

// One drop-down on screen at a time, across every bar.
//
// There is one Bar per monitor, so there is one copy of every menu per monitor,
// and nothing in QML stops two of them being open at once. This is the single
// place that decides which one is up -- MenuPopup claims on the way open and
// releases on the way closed, and Pill.qml reads `current` to know whether a
// hover should hand off to another module's menu or do nothing at all.
//
// It is a singleton for the reason NotificationService and AudioService are:
// every bar has to agree, and the answer is one value.
Singleton {
    id: root

    // The MenuPopup currently on screen, or null. Never assign this from
    // outside -- claim() and release() are the whole interface.
    property var current: null

    // Called by MenuPopup when it opens. The outgoing menu is closed through
    // requestClose() rather than by assigning `open`, because a menu whose
    // `open` is a binding (NotificationMenu's follows
    // NotificationService.menuMonitor) would have that binding destroyed by
    // an assignment and would then never open again.
    function claim(menu) {
        if (root.current && root.current !== menu) root.current.requestClose();
        root.current = menu;
    }

    // Guarded: a menu that was already replaced by claim() still reports its
    // own close afterwards, and must not clear the incoming menu's claim.
    function release(menu) {
        if (root.current === menu) root.current = null;
    }
}

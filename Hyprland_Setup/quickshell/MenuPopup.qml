import Quickshell
import Quickshell.Hyprland
import QtQuick

// The frame every bar drop-down wears: a panel hanging off the bottom edge of
// the bar slab, in the slab's own colour, with the join between them invisible.
//
// This is to the thirteen module menus what OverlayPanel.qml is to the four
// full-screen overlays. Before it, every one of them repeated the same four-line
// anchor block and the same six-line Rectangle, so "make the popups look
// attached" was a thirteen-file edit and the values had already drifted (popup
// radius 12, slab radius 8, toast radius 14).
//
// Consumers supply only their body, which lands inside the frame.
PopupWindow {
    id: root

    // The bar module this hangs from. Its position is read out of the bar
    // window rather than used as the anchor directly -- see anchorRect.
    property Item anchorItem: null
    property bool open: false

    // A hover panel sets this false. It must never hold the keyboard for as
    // long as the pointer happens to cross the pill, and it has no Escape to
    // answer because it is dismissed by moving away.
    property bool grabsFocus: true

    // False for a popup that must not take part in the one-at-a-time
    // arbitration -- RecorderPill's hover panel, which is a readout rather
    // than a menu.
    property bool managed: true

    // False for a menu whose `open` is a binding rather than its own state, so
    // this file never assigns to it (NotificationMenu). Such a menu handles
    // dismissed() itself and overrides requestClose().
    property bool closeOnDismiss: true

    default property alias content: frame.data
    // The frame itself, for a consumer that has to hand keyboard focus back to
    // it -- WifiMenu's password field takes focus while it is up.
    readonly property alias panel: frame

    // Escape, or a click anywhere outside. The base closes unless the consumer
    // has taken that over; a consumer handler runs in addition to this one --
    // a derived signal handler does not replace the base's.
    signal dismissed()
    onDismissed: if (root.closeOnDismiss) root.open = false;

    // Asked by MenuService to get out of the way for another menu. A function,
    // not a signal, precisely because a function CAN be overridden where a
    // signal handler cannot.
    function requestClose() { root.open = false; }

    readonly property var barWindow: anchorItem ? anchorItem.QsWindow.window : null

    // Bumped on the way open, so a module that moved while the menu was shut
    // (a pill to its left changing width) is re-measured before it is shown.
    property int reanchor: 0
    onOpenChanged: {
        if (root.open) root.reanchor++;
        if (!root.managed) return;
        if (root.open) MenuService.claim(root);
        else MenuService.release(root);
    }

    // The module's rect in bar-window coordinates.
    //
    // QsWindow.itemRect() is a *constant* method: it registers no dependency of
    // its own, so a plain binding on it runs once -- before the item is in a
    // window, when it errors and yields 0x0 -- and keeps that answer for ever.
    // Verified: both test popups fell to the clamp floor until `deps` was added.
    readonly property rect anchorRect: {
        if (!root.anchorItem || !root.barWindow) return Qt.rect(0, 0, 0, 0);
        const deps = [root.anchorItem.x, root.anchorItem.y, root.anchorItem.width,
                      root.anchorItem.height, root.barWindow.width, root.reanchor];
        return root.anchorItem.QsWindow.itemRect(root.anchorItem);
    }

    // Anchored to the BAR, not to the module. Two things follow, and neither is
    // available from anchor.item:
    //
    //  - the y is the slab's own bottom edge, so the gap is exactly zero. Off
    //    the pill it was `margins.top: 6` measured from a 22px pill centred in a
    //    30px bar -- a line that read "6" and produced 2.
    //  - the x can be clamped to the slab. Left to the compositor, a menu wider
    //    than its module slides to the SCREEN edge and overhangs the bar's 5px
    //    inset, which is the one placement that cannot look attached to it.
    //
    // Gravity centres the popup on the anchor rect, so a rect of the popup's own
    // width pins x instead of centring it. Verified against 0.3.1.
    anchor.window: barWindow
    // One pixel INTO the bar, not flush against it. Measured at the join with
    // the popup placed at exactly barWindow.height: the bar's last row is
    // screen y31, the popup's first row y33, and y32 is a full-width row of
    // wallpaper -- the surface lands a pixel below the edge it was given. A
    // one-pixel overlap cannot show, because both surfaces are Theme.base
    // there and this popup's top border is erased below; a one-pixel gap is
    // the seam this whole component exists to remove.
    anchor.rect.y: root.barWindow ? root.barWindow.height - Theme.borderWidth : 0
    anchor.rect.height: 0
    anchor.rect.width: root.width
    anchor.rect.x: {
        if (!root.barWindow) return 0;
        const centred = root.anchorRect.x + root.anchorRect.width / 2 - root.width / 2;
        // Stop short of the rounded ends: a square top corner meeting the slab's
        // rounded one leaves a sliver of wallpaper in the join.
        const lo = Theme.barRadius;
        const hi = root.barWindow.width - root.width - Theme.barRadius;
        return Math.round(Math.max(lo, Math.min(hi, centred)));
    }
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom

    color: "transparent"
    visible: root.open
    grabFocus: root.grabsFocus && root.open

    // The BAR is in this list as well as the popup, and that is load-bearing
    // twice over. Hyprland's focus grab constrains pointer focus to the grabbed
    // surfaces, so with only [root] the bar receives no hover events at all
    // while a menu is open and the hand-off in Pill.qml could never fire. It
    // also means clicking a different module switches menus rather than
    // dismissing this one and reopening that one.
    HyprlandFocusGrab {
        windows: root.barWindow ? [root, root.barWindow] : [root]
        active: root.grabsFocus && root.open
        onCleared: root.dismissed()
    }

    Rectangle {
        id: frame
        anchors.fill: parent
        focus: root.grabsFocus
        Keys.onEscapePressed: root.dismissed()

        color: Theme.base
        radius: Theme.popupRadius
        // The two corners that are no longer corners: this edge is continuous
        // with the slab above it.
        topLeftRadius: 0
        topRightRadius: 0
        border.width: Theme.borderWidth
        border.color: Theme.surface1

        // Erase the border along the top edge. The bar has no border of its own,
        // so a surface1 line across the join is exactly the seam this component
        // exists to remove.
        Rectangle {
            anchors { left: parent.left; right: parent.right; top: parent.top }
            height: Theme.borderWidth
            color: Theme.base
            z: 1
        }

        // Emerge from under the bar. A Translate rather than y or a margin: it
        // does not touch layout, and the popup surface clips the overhang.
        //
        // Only the opening direction animates -- `visible: open` unmaps the
        // surface the instant the menu closes, so there is nothing left to
        // animate out. That is deliberate, not an oversight.
        transform: Translate {
            y: root.open ? 0 : -8
            Behavior on y { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
        }
        opacity: root.open ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
    }
}

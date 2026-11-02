// The real lock. Run by hypr/scripts/lock.sh, not directly: that script is what makes
// sure only one runs, and what brings in hyprlock if this one fails.
import Quickshell

Scope {
    Lock {}
}

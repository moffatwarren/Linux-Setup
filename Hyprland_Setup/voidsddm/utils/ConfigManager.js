.pragma library

/**
 * Configuration manager utilities
 */

/**
 * Get element opacity with validation
 */
function getElementOpacity(config) {
    var opacity = config.stringValue("elementOpacity")
    if (opacity === "") return 1.0
    var num = parseFloat(opacity)
    return (num >= 0.0 && num <= 1.0) ? num : 1.0
}


/**
 * Read an int that is allowed to be 0.
 *
 * sddm's config.intValue() returns 0 for a key that is absent, and every call
 * site here used `config.intValue(k) || fallback` -- so 0 is indistinguishable
 * from unset and a `passwordFieldBorderWidth=0` silently became the fallback.
 * stringValue() does distinguish the two: "" means the key is not in the conf.
 */
function intOr(config, key, fallback) {
    var raw = config.stringValue(key)
    if (raw === "" || raw === undefined) return fallback
    var num = parseInt(raw, 10)
    return isNaN(num) ? fallback : num
}

/**
 * Read a colour. An absent or empty key falls back, matching how the rest of
 * this theme reads its config; an explicit "none"/"transparent" draws nothing,
 * which is how the conf turns the field's focus ring off without a boolean.
 */
function colorOr(config, key, fallback) {
    var raw = config.stringValue(key)
    if (raw === undefined) return fallback
    if (raw === "") return fallback
    if (raw === "none" || raw === "transparent") return "transparent"
    return raw
}

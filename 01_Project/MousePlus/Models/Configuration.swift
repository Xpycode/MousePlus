import Foundation

/// Full configuration for the ring menu.
struct Configuration: Codable {
    /// Inner band — symbol-only quick actions (no labels rendered).
    var inner: [RingMenuItem]
    /// Middle band — labeled items; each direct or expandable.
    /// Inner and middle are INDEPENDENT action sets that share only spoke geometry
    /// (not parent/child). See IMPLEMENTATION_PLAN §2.3.
    var middle: [RingMenuItem]
    var triggers: TriggersConfig
    var appearance: AppearanceConfig
    var behavior: BehaviorConfig
    var hudCustomization: HUDCustomization

    /// Temporary source-compat bridge (T3): pre-split code still reads `config.items`.
    /// Maps to `middle`, the band that absorbs old flat `items` on migration.
    /// Remove once RingViewModel is rewritten in T4 to consume `inner`/`middle` directly.
    var items: [RingMenuItem] {
        get { middle }
        set { middle = newValue }
    }

    init(
        inner: [RingMenuItem] = RingMenuItem.sampleInnerItems,
        middle: [RingMenuItem] = RingMenuItem.sampleItems,
        triggers: TriggersConfig = .default,
        appearance: AppearanceConfig = .default,
        behavior: BehaviorConfig = .default,
        hudCustomization: HUDCustomization = .default
    ) {
        self.inner = inner
        self.middle = middle
        self.triggers = triggers
        self.appearance = appearance
        self.behavior = behavior
        self.hudCustomization = hudCustomization
    }

    private enum CodingKeys: String, CodingKey {
        case inner, middle, triggers, appearance, behavior, hudCustomization
        case items    // legacy, pre-split; flat array migrated into `middle`
        case hotkey   // legacy, pre-2026-04-29; migrated into `triggers.keyboard`
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        // Item-set migration:
        //   New format → `inner` + `middle` keys read directly.
        //   Old format → only a flat `items` array; it lands in `middle`, `inner` defaults.
        if c.contains(.middle) || c.contains(.inner) {
            middle = try c.decodeIfPresent([RingMenuItem].self, forKey: .middle) ?? RingMenuItem.sampleItems
            inner = try c.decodeIfPresent([RingMenuItem].self, forKey: .inner) ?? []
        } else if let legacyItems = try c.decodeIfPresent([RingMenuItem].self, forKey: .items) {
            middle = legacyItems
            inner = []
        } else {
            inner = RingMenuItem.sampleInnerItems
            middle = RingMenuItem.sampleItems
        }

        appearance = try c.decodeIfPresent(AppearanceConfig.self, forKey: .appearance) ?? .default
        behavior = try c.decodeIfPresent(BehaviorConfig.self, forKey: .behavior) ?? .default
        hudCustomization = (try? c.decode(HUDCustomization.self, forKey: .hudCustomization)) ?? .default

        if let t = try c.decodeIfPresent(TriggersConfig.self, forKey: .triggers) {
            triggers = t
        } else if let legacy = try c.decodeIfPresent(LegacyHotkeyConfig.self, forKey: .hotkey) {
            triggers = TriggersConfig(
                keyboard: .keyboard(keyCode: legacy.keyCode, modifiers: legacy.modifiers, mode: .holdRelease)
            )
        } else {
            triggers = .default
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        // Canonical new keys.
        try c.encode(inner, forKey: .inner)
        try c.encode(middle, forKey: .middle)
        try c.encode(triggers, forKey: .triggers)
        try c.encode(appearance, forKey: .appearance)
        try c.encode(behavior, forKey: .behavior)
        try c.encode(hudCustomization, forKey: .hudCustomization)
    }
}

/// How a trigger binding interprets press/release events.
enum TriggerMode: String, Codable, Sendable {
    case holdRelease   // press → show ring; release → select hovered slice
    case tapToggle     // tap → show ring; ring stays open until user clicks a slice or taps trigger again
}

/// One trigger source binding — keyboard, mouse button, or unset.
enum TriggerBinding: Codable, Equatable, Sendable {
    case none
    case keyboard(keyCode: UInt16, modifiers: UInt, mode: TriggerMode)
    case mouseButton(buttonNumber: Int, mode: TriggerMode)

    var isActive: Bool {
        if case .none = self { return false }
        return true
    }
}

/// Trigger slots — the ring's keyboard + mouse-button triggers, plus a global
/// "open Settings" hotkey — each independently configurable.
struct TriggersConfig: Codable, Sendable, Equatable {
    var keyboard: TriggerBinding
    var mouseButton: TriggerBinding

    /// Global shortcut that opens Settings/Preferences from anywhere. Unlike the ring
    /// triggers (which ship **unbound** and are set via onboarding / the Triggers tab),
    /// this ships **bound** to ⌥⌘, so a menu-bar-only app is always reachable even when
    /// the status-item icon fails to render (the M1 Max mystery) — it's the fallback
    /// way into Settings once the "Identify Input" auto-open was removed.
    var openSettings: TriggerBinding

    init(
        keyboard: TriggerBinding = .none,
        mouseButton: TriggerBinding = .none,
        openSettings: TriggerBinding = TriggersConfig.defaultOpenSettings
    ) {
        self.keyboard = keyboard
        self.mouseButton = mouseButton
        self.openSettings = openSettings
    }

    /// Decode-tolerant. `TriggersConfig` previously relied on synthesized `Codable`,
    /// which would throw `keyNotFound` on the new `openSettings` key — making every
    /// existing `config.json` (no such key) fail to decode and take the whole
    /// configuration down with it. Each field is `decodeIfPresent`-ed with a default
    /// instead, so old configs still load AND existing users inherit the ⌥⌘, hotkey.
    private enum CodingKeys: String, CodingKey { case keyboard, mouseButton, openSettings }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        keyboard = try c.decodeIfPresent(TriggerBinding.self, forKey: .keyboard) ?? .none
        mouseButton = try c.decodeIfPresent(TriggerBinding.self, forKey: .mouseButton) ?? .none
        openSettings = try c.decodeIfPresent(TriggerBinding.self, forKey: .openSettings) ?? TriggersConfig.defaultOpenSettings
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(keyboard, forKey: .keyboard)
        try c.encode(mouseButton, forKey: .mouseButton)
        try c.encode(openSettings, forKey: .openSettings)
    }

    /// Out-of-the-box global Settings hotkey: ⌥⌘, (comma = keyCode 43). Mode is
    /// irrelevant — the monitor reacts only to key-down.
    static let defaultOpenSettings: TriggerBinding = .keyboard(
        keyCode: 43,                       // comma
        modifiers: (1 << 19) | (1 << 20),  // ⌥ option (1<<19) | ⌘ command (1<<20)
        mode: .holdRelease
    )

    /// Ring triggers ship **unbound** (set via onboarding / the Triggers tab); the
    /// Settings hotkey ships bound. A saved `config.json` always overrides all of this
    /// at load, so this governs only a fresh install / a config missing these keys.
    ///
    /// (The ring triggers previously hard-coded an F5 + middle-click test pair; removed
    /// 2026-05-31 once the Triggers tab + onboarding became the intended binding path.)
    static let `default` = TriggersConfig()
}

/// Decode-only helper for pre-2026-04-29 config JSON (`hotkey: { keyCode, modifiers }`).
private struct LegacyHotkeyConfig: Codable {
    let keyCode: UInt16
    let modifiers: UInt
}

/// Visual appearance settings.
///
/// Band-edge radii (`deadZone`/`innerEdge`/`middleEdge`/`outerEdge` = r0…r3) drive
/// the concentric ring geometry (see `IMPLEMENTATION_PLAN.md` §2.1). Defaults match
/// the plan: r0=24, r1=78, r2=150, r3=224. Expose them to `RadialGeometry` via the
/// `bandRadii` bridge.
///
/// `init(from:)` is custom and `decodeIfPresent`s every field with its default, so
/// older config JSON (which lacks the new keys, or even all of them) decodes without
/// throwing. `ringRadius`/`itemSize` are legacy/no-longer-referenced fields kept only
/// so existing snapshots round-trip and to avoid churn; they have no effect on the ring.
struct AppearanceConfig: Codable, Equatable {
    // Legacy fields (unused by the concentric ring; retained for decode round-trip).
    var ringRadius: Double
    var itemSize: Double

    // Band-edge radii (r0…r3). See §2.1.
    var deadZone: Double      // r0
    var innerEdge: Double     // r1
    var middleEdge: Double    // r2
    var outerEdge: Double     // r3

    /// Opacity applied to wedges off the live branch when something is expanded (§2.3).
    var dimOpacity: Double
    /// Also keep the inner wedge aligned with the expanded middle wedge lit (§2.3).
    var keepSpokeLit: Bool

    var animationEnabled: Bool
    var animationDuration: Double

    init(
        ringRadius: Double = 120,
        itemSize: Double = 60,
        deadZone: Double = 24,
        innerEdge: Double = 78,
        middleEdge: Double = 150,
        outerEdge: Double = 224,
        dimOpacity: Double = 0.30,
        keepSpokeLit: Bool = false,
        animationEnabled: Bool = true,
        animationDuration: Double = 0.15
    ) {
        self.ringRadius = ringRadius
        self.itemSize = itemSize
        self.deadZone = deadZone
        self.innerEdge = innerEdge
        self.middleEdge = middleEdge
        self.outerEdge = outerEdge
        self.dimOpacity = dimOpacity
        self.keepSpokeLit = keepSpokeLit
        self.animationEnabled = animationEnabled
        self.animationDuration = animationDuration
    }

    private enum CodingKeys: String, CodingKey {
        case ringRadius, itemSize
        case deadZone, innerEdge, middleEdge, outerEdge
        case dimOpacity, keepSpokeLit
        case animationEnabled, animationDuration
    }

    /// Tolerant decode: every field falls back to its default if absent, so old
    /// (and partial) appearance dicts decode without throwing.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppearanceConfig.default
        ringRadius        = try c.decodeIfPresent(Double.self, forKey: .ringRadius) ?? d.ringRadius
        itemSize          = try c.decodeIfPresent(Double.self, forKey: .itemSize) ?? d.itemSize
        deadZone          = try c.decodeIfPresent(Double.self, forKey: .deadZone) ?? d.deadZone
        innerEdge         = try c.decodeIfPresent(Double.self, forKey: .innerEdge) ?? d.innerEdge
        middleEdge        = try c.decodeIfPresent(Double.self, forKey: .middleEdge) ?? d.middleEdge
        outerEdge         = try c.decodeIfPresent(Double.self, forKey: .outerEdge) ?? d.outerEdge
        dimOpacity        = try c.decodeIfPresent(Double.self, forKey: .dimOpacity) ?? d.dimOpacity
        keepSpokeLit      = try c.decodeIfPresent(Bool.self, forKey: .keepSpokeLit) ?? d.keepSpokeLit
        animationEnabled  = try c.decodeIfPresent(Bool.self, forKey: .animationEnabled) ?? d.animationEnabled
        animationDuration = try c.decodeIfPresent(Double.self, forKey: .animationDuration) ?? d.animationDuration
    }

    /// Bridge the four band-edge fields into `RadialGeometry`'s `BandRadii`
    /// (Double → CGFloat). Invariant expected by the geometry: r0 < r1 < r2 < r3.
    var bandRadii: BandRadii {
        BandRadii(
            r0: CGFloat(deadZone),
            r1: CGFloat(innerEdge),
            r2: CGFloat(middleEdge),
            r3: CGFloat(outerEdge)
        )
    }

    static let `default` = AppearanceConfig()
}

/// Interaction behavior settings.
/// `holdToActivate` / `tapToActivate` are legacy app-wide toggles; W4 obsoletes them
/// in favor of the per-binding `TriggerMode` carried inside each `TriggerBinding`.
struct BehaviorConfig: Codable, Equatable {
    var holdToActivate: Bool
    var tapToActivate: Bool
    var dismissOnClickOutside: Bool
    var dismissOnEscape: Bool

    static let `default` = BehaviorConfig(
        holdToActivate: true,
        tapToActivate: true,
        dismissOnClickOutside: true,
        dismissOnEscape: true
    )
}

/// Launch routing only; this policy never writes configuration or starts monitors.
/// Keep one instance for the process lifetime. Feed only completed loads into
/// `loaded`, and only successfully persisted bindings into guidance helpers.
struct TriggerOnboardingPolicy {
    enum LoadState: Equatable {
        case loading
        case loaded(TriggersConfig)
        case missingFile
        case failed
    }

    enum Status: Equatable {
        case waiting, permissionSetup, triggerSetup, configured, loadFailure
    }

    enum Action: Equatable {
        // For loadFailure, showSettings must select a pane exposing the existing
        // load error/recovery UI (Triggers), rather than silently opening General.
        case none, showPermissionSetup, showTriggerSetup, showSettings
    }

    struct Decision: Equatable {
        var status: Status
        var action: Action
    }

    struct RingBinding: Equatable {
        enum Slot: Equatable {
            case contextualKeyboard, mouseButton, globalHUD
        }

        var slot: Slot
        var binding: TriggerBinding
    }

    private var presentedPermission = false
    private var requestedContinuation = false
    private var resolvedLaunch = false

    /// `status` describes current inputs; `action` is a one-shot presentation.
    /// Once permission setup is presented (even if subsequently closed), only
    /// its explicit Continue action may transfer to Settings this launch.
    mutating func evaluate(
        configuration: LoadState,
        accessibilityGranted: Bool,
        continueFromPermission: Bool = false
    ) -> Decision {
        if continueFromPermission && presentedPermission && accessibilityGranted {
            requestedContinuation = true
        }

        let status: Status
        if !accessibilityGranted {
            status = .permissionSetup
        } else {
            switch configuration {
            case .loading: status = .waiting
            case .failed: status = .loadFailure
            case .missingFile: status = .triggerSetup
            case .loaded(let triggers):
                status = Self.hasRingBinding(in: triggers) ? .configured : .triggerSetup
            }
        }

        guard !resolvedLaunch else { return Decision(status: status, action: .none) }
        guard accessibilityGranted else {
            let action: Action = presentedPermission ? .none : .showPermissionSetup
            presentedPermission = true
            return Decision(status: status, action: action)
        }
        guard status != .waiting else { return Decision(status: status, action: .none) }
        guard !presentedPermission || requestedContinuation else {
            return Decision(status: status, action: .none)
        }

        // Even configured launches consume the latch: clearing the last binding
        // later in this session must not manufacture a new startup presentation.
        resolvedLaunch = true
        switch status {
        case .triggerSetup:
            return Decision(status: status, action: .showTriggerSetup)
        case .loadFailure:
            return Decision(status: status, action: .showSettings)
        case .configured:
            return Decision(status: status, action: requestedContinuation ? .showSettings : .none)
        case .waiting, .permissionSetup:
            return Decision(status: status, action: .none)
        }
    }

    /// Matches TriggerService's slot types and collision behavior. A binding
    /// means configured, not verified physical delivery or granted permission.
    static func eligibleRingBindings(in triggers: TriggersConfig) -> [RingBinding] {
        var bindings: [RingBinding] = []
        if case .keyboard = triggers.keyboard {
            bindings.append(RingBinding(slot: .contextualKeyboard, binding: triggers.keyboard))
        }
        if case .mouseButton = triggers.mouseButton {
            bindings.append(RingBinding(slot: .mouseButton, binding: triggers.mouseButton))
        }
        if case .keyboard = triggers.globalHUDShortcut,
           HUDTriggerRouting.collision(
               globalHUDShortcut: triggers.globalHUDShortcut,
               contextualKeyboard: triggers.keyboard
           ) == nil {
            bindings.append(RingBinding(slot: .globalHUD, binding: triggers.globalHUDShortcut))
        }
        return bindings
    }

    static func hasRingBinding(in triggers: TriggersConfig) -> Bool {
        !eligibleRingBindings(in: triggers).isEmpty
    }
}

// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MousePlus",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "MousePlus",
            path: "MousePlus",
            sources: [
                "Models/ActionType.swift",
                "Models/AppHUDProfile.swift",
                "Models/Configuration.swift",
                "Models/HIDDeviceSnapshot.swift",
                "Models/HUDColor.swift",
                "Models/HUDCustomization.swift",
                "Models/HUDInvocation.swift",
                "Models/HUDMotionConfiguration.swift",
                "Models/IconSource.swift",
                "Models/KeystrokePayload.swift",
                "Models/RingMenuItem.swift",
                "Models/SnapZone.swift",
                "Utilities/HUDColorResolver.swift",
                "Utilities/HUDMotionPolicy.swift",
                "Utilities/HUDTriggerRouting.swift",
                "Utilities/RadialGeometry.swift",
                "Services/InputTapRegistry.swift",
                "Services/KeyboardTriggerMonitor.swift",
                "Services/KeystrokeCaptureRecorder.swift",
                "Services/MouseButtonTriggerMonitor.swift",
                "Services/RuntimeTrustMonitor.swift",
                "Services/TriggerRecorderService.swift",
                "Services/TriggerService.swift",
            ]
        ),
        .testTarget(
            name: "MousePlusTests",
            dependencies: ["MousePlus"],
            path: "MousePlusTests",
            sources: [
                "ActionTypeCodingTests.swift",
                "HUDColorResolverTests.swift",
                "HUDCustomizationCodingTests.swift",
                "HUDMotionPolicyTests.swift",
                "InputTapRegistryTests.swift",
                "KeyboardTriggerMonitorTests.swift",
                "KeystrokeCaptureRecorderTests.swift",
                "KeystrokePayloadCodingTests.swift",
                "MouseButtonTriggerMonitorTests.swift",
                "RadialGeometryTests.swift",
                "RuntimeTrustMonitorTests.swift",
                "TriggerRecorderServiceTests.swift",
                "TriggerServiceTests.swift",
            ]
        ),
    ],
    swiftLanguageModes: [.v5]
)

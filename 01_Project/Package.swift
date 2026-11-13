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
                "Utilities/RadialGeometry.swift",
                "Services/MouseButtonTriggerMonitor.swift",
                "Services/TriggerRecorderService.swift",
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
                "KeystrokePayloadCodingTests.swift",
                "MouseButtonTriggerMonitorTests.swift",
                "RadialGeometryTests.swift",
            ]
        ),
    ],
    swiftLanguageModes: [.v5]
)

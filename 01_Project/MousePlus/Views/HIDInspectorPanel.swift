import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Side-panel companion to InputRecorderView. Exploratory tooling — surfaces
/// the IOHIDManager view of every connected HID input device, with live
/// element-fire highlighting so the user can press the silent MX Master
/// buttons and see exactly which (page, usage, cookie) fires.
struct HIDInspectorPanel: View {
    @Bindable var inspector: IOHIDDeviceInspector
    @State private var selectedDeviceID: HIDDeviceInfo.ID?
    @State private var showInputOnly = true
    @State private var sortByFires = true
    @State private var copyConfirmation: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            statusBar

            if inspector.devices.isEmpty {
                emptyState
            } else {
                devicePicker
                Divider()
                elementTable
                rawReportsSection
                Divider()
                actionsRow
            }
        }
        .padding(20)
        .frame(width: 520)
        // Lifecycle is owned by InputRecorderWindowController — calling start()
        // / stop() from .onAppear is brittle (SwiftUI may remount during layout
        // and disappear during a normal Bindable-driven body re-eval).
        .onChange(of: inspector.devices.map(\.id)) { _, ids in
            if selectedDeviceID == nil || !ids.contains(selectedDeviceID!) {
                selectedDeviceID = ids.first
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("HID Inspector")
                .font(.title2.bold())
            Text("Live IOHIDManager view. Press a button to highlight its element.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Toggle(
                "Match all HID devices (incl. vendor / HID++ interfaces)",
                isOn: Binding(
                    get: { inspector.matchAllDevices },
                    set: { inspector.setMatchAllDevices($0) }
                )
            )
            .toggleStyle(.switch)
            .controlSize(.mini)
            .font(.caption)
        }
    }

    @ViewBuilder
    private var statusBar: some View {
        switch inspector.status {
        case .idle:
            Label("Idle", systemImage: "circle")
                .foregroundStyle(.secondary)
        case .requestingAccess:
            Label("Requesting Input Monitoring…", systemImage: "lock.shield")
                .foregroundStyle(.secondary)
        case .denied:
            VStack(alignment: .leading, spacing: 6) {
                Label("Input Monitoring denied", systemImage: "exclamationmark.shield")
                    .foregroundStyle(.red)
                Button("Open Input Monitoring Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.link)
            }
        case .running:
            Label("Listening", systemImage: "dot.radiowaves.left.and.right")
                .foregroundStyle(.green)
        case .runningPartial(let msg):
            Label(msg, systemImage: "dot.radiowaves.left.and.right")
                .font(.caption)
                .foregroundStyle(.orange)
        case .error(let msg):
            Label(msg, systemImage: "xmark.octagon")
                .foregroundStyle(.red)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text("No matching HID devices yet")
                .font(.callout)
            Text("Plug a mouse / keyboard / receiver. The list updates live.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 60)
    }

    private var devicePicker: some View {
        Picker("Device", selection: $selectedDeviceID) {
            ForEach(inspector.devices) { device in
                let suffix = inspector.hasVendorPipe(device) ? "  [HID++ pipe]" : ""
                Text(device.displayName + suffix).tag(device.id as HIDDeviceInfo.ID?)
            }
        }
        .pickerStyle(.menu)
    }

    private var elementTable: some View {
        let elements = selectedDeviceID.flatMap { inspector.elementsByDevice[$0] } ?? []
        let counts = selectedDeviceID.flatMap { inspector.fireCountsByDevice[$0] } ?? [:]
        let filtered = showInputOnly
            ? elements.filter { $0.type.hasPrefix("input.") }
            : elements
        // When sortByFires is on, hottest-firing elements bubble to the top;
        // ties keep original descriptor order (stable sort). This keeps the
        // list itself stationary — no auto-scroll, no jumping during X/Y axis
        // streams. The user can still tell at a glance which element fired.
        let displayed: [HIDElementInfo] = sortByFires
            ? filtered.enumerated()
                .sorted { lhs, rhs in
                    let lc = counts[lhs.element.cookie] ?? 0
                    let rc = counts[rhs.element.cookie] ?? 0
                    if lc != rc { return lc > rc }
                    return lhs.offset < rhs.offset
                }
                .map(\.element)
            : filtered
        let lastFired = selectedDeviceID.flatMap { inspector.lastFireCookieByDevice[$0] }

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Text("Elements (\(displayed.count) of \(elements.count))")
                    .font(.caption.bold())
                Spacer()
                Toggle("Sort by fires", isOn: $sortByFires)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .font(.caption)
                Toggle("Input only", isOn: $showInputOnly)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .font(.caption)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(displayed) { element in
                        elementRow(
                            element,
                            isLastFired: element.cookie == lastFired,
                            fireCount: counts[element.cookie] ?? 0
                        )
                    }
                }
            }
            .frame(height: 200)
            .background(.quinary, in: .rect(cornerRadius: 8))
        }
    }

    @ViewBuilder
    private var rawReportsSection: some View {
        let reports = selectedDeviceID.flatMap { inspector.rawReportsByDevice[$0] } ?? []
        VStack(alignment: .leading, spacing: 4) {
            Text("Raw input reports (\(reports.count))")
                .font(.caption.bold())
            if reports.isEmpty {
                Text("No raw reports yet — vendor / HID++ buttons appear here when fired.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(reports) { report in
                            HStack(spacing: 8) {
                                Text(String(format: "id=%02X", report.reportID))
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 56, alignment: .leading)
                                Text(report.hex)
                                    .font(.system(.caption, design: .monospaced))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                        }
                    }
                }
                .frame(height: 90)
                .background(.quinary, in: .rect(cornerRadius: 8))
            }
        }
    }

    private func elementRow(_ element: HIDElementInfo, isLastFired: Bool, fireCount: Int) -> some View {
        HStack(spacing: 8) {
            Text(String(format: "0x%04X", element.usagePage))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)
            Text(String(format: "0x%04X", element.usage))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)
            Text(element.humanLabel)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("ck \(element.cookie)")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.tertiary)
            if fireCount > 0 {
                Text("×\(fireCount)")
                    .font(.system(.caption2, design: .monospaced).bold())
                    .foregroundStyle(.orange)
                    .frame(width: 36, alignment: .trailing)
            } else {
                Color.clear.frame(width: 36)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(isLastFired ? Color.accentColor.opacity(0.25) : Color.clear)
        .animation(.easeOut(duration: 0.4), value: isLastFired)
    }

    private var actionsRow: some View {
        HStack(spacing: 10) {
            Button("Clear fires") { inspector.clearFires() }
                .buttonStyle(.bordered)
                .controlSize(.small)
            Button("Copy snapshot JSON") { copySnapshot() }
                .buttonStyle(.bordered)
                .controlSize(.small)
            Button("Save snapshot…") { saveSnapshot() }
                .buttonStyle(.bordered)
                .controlSize(.small)
            Spacer()
            if let copyConfirmation {
                Text(copyConfirmation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
        }
    }

    // MARK: - Snapshot I/O

    private func currentSnapshotJSON() -> Data? {
        guard let id = selectedDeviceID,
              let device = inspector.devices.first(where: { $0.id == id }) else { return nil }
        let snapshot = inspector.snapshot(for: device)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(snapshot)
    }

    private func copySnapshot() {
        guard let data = currentSnapshotJSON(),
              let json = String(data: data, encoding: .utf8) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(json, forType: .string)
        flashConfirmation("Copied \(data.count) bytes")
    }

    private func saveSnapshot() {
        guard let data = currentSnapshotJSON(),
              let id = selectedDeviceID,
              let device = inspector.devices.first(where: { $0.id == id }) else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = defaultFileName(for: device)
        panel.title = "Save HID Snapshot"
        panel.message = "Pick a destination — e.g. docs/fixtures/ in the project."
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try data.write(to: url)
                flashConfirmation("Saved \(url.lastPathComponent)")
            } catch {
                flashConfirmation("Save failed: \(error.localizedDescription)")
            }
        }
    }

    private func defaultFileName(for device: HIDDeviceInfo) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let datePart = formatter.string(from: Date())
        let vidpid = String(format: "%04x-%04x", device.vendorID, device.productID)
        let usage = "\(device.primaryUsagePage)x\(device.primaryUsage)"
        return "hid-\(vidpid)-\(usage)-\(datePart).json"
    }

    private func flashConfirmation(_ message: String) {
        copyConfirmation = message
        Task {
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run {
                if copyConfirmation == message { copyConfirmation = nil }
            }
        }
    }
}

import SwiftUI

/// Admin flow after dropping a pin on the map: capture threat class + message before persisting.
struct AdminHazardPinComposeSheet: View {
    let pinType: PinType
    let onCancel: () -> Void
    let onCommit: (_ threatClassLabel: String, _ reasonMessage: String, _ mapLabel: String) -> Void

    @State private var threatClassSelection: String = ""
    @State private var dangerMessage: String = ""
    @State private var safeRouteTitle: String = ""
    @State private var safeRouteMessage: String = ""

    private var accent: Color {
        switch pinType {
        case .danger: return ProjectTheme.warning
        case .safeRoute: return ProjectTheme.signal
        }
    }

    private var headerTitle: String {
        switch pinType {
        case .danger: return "New danger zone"
        case .safeRoute: return "New safe route"
        }
    }

    private var canSubmitDanger: Bool {
        !threatClassSelection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !dangerMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canSubmitSafeRoute: Bool {
        !safeRouteTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !safeRouteMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canSubmit: Bool {
        switch pinType {
        case .danger: return canSubmitDanger
        case .safeRoute: return canSubmitSafeRoute
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 10) {
                        Image(systemName: pinType == .danger ? "exclamationmark.triangle.fill" : "figure.walk.diamond.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(accent)
                        Text(headerTitle)
                            .font(.system(size: 24, weight: .black, design: .rounded))
                            .foregroundStyle(ProjectTheme.textPrimary)
                    }

                    if pinType == .danger {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Threat class")
                                .font(.system(size: 12, weight: .heavy, design: .rounded))
                                .foregroundStyle(ProjectTheme.textSecondary)
                            Picker("Threat class", selection: $threatClassSelection) {
                                Text("Choose…").tag("")
                                ForEach(ThreatClassLabels.all, id: \.self) { name in
                                    Text(name).tag(name)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(ProjectTheme.textPrimary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(ProjectTheme.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(ProjectTheme.panelBorder, lineWidth: 1)
                        )

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Message")
                                .font(.system(size: 12, weight: .heavy, design: .rounded))
                                .foregroundStyle(ProjectTheme.textSecondary)
                            TextField("Describe the situation", text: $dangerMessage, axis: .vertical)
                                .lineLimit(3...8)
                                .textInputAutocapitalization(.sentences)
                                .foregroundStyle(ProjectTheme.textPrimary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(ProjectTheme.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(ProjectTheme.panelBorder, lineWidth: 1)
                        )
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Title")
                                .font(.system(size: 12, weight: .heavy, design: .rounded))
                                .foregroundStyle(ProjectTheme.textSecondary)
                            TextField("Short label for this route", text: $safeRouteTitle)
                                .textInputAutocapitalization(.words)
                                .foregroundStyle(ProjectTheme.textPrimary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(ProjectTheme.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(ProjectTheme.panelBorder, lineWidth: 1)
                        )

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Message")
                                .font(.system(size: 12, weight: .heavy, design: .rounded))
                                .foregroundStyle(ProjectTheme.textSecondary)
                            TextField("Why this route is safe / how to use it", text: $safeRouteMessage, axis: .vertical)
                                .lineLimit(3...8)
                                .textInputAutocapitalization(.sentences)
                                .foregroundStyle(ProjectTheme.textPrimary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(ProjectTheme.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(ProjectTheme.panelBorder, lineWidth: 1)
                        )
                    }
                }
                .padding(20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(red: 0.05, green: 0.07, blue: 0.09).ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        guard canSubmit else { return }
                        switch pinType {
                        case .danger:
                            let cls = threatClassSelection.trimmingCharacters(in: .whitespacesAndNewlines)
                            let msg = dangerMessage.trimmingCharacters(in: .whitespacesAndNewlines)
                            let mapLabel = "Danger — \(cls)"
                            onCommit(cls, msg, mapLabel)
                        case .safeRoute:
                            let title = safeRouteTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                            let msg = safeRouteMessage.trimmingCharacters(in: .whitespacesAndNewlines)
                            onCommit("", msg, title)
                        }
                    }
                    .disabled(!canSubmit)
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(22)
    }
}

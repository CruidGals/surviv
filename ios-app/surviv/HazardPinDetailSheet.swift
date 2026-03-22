import SwiftUI

/// Value copy for the detail UI so we can delete the backing ``HazardPin`` without holding a live model reference.
struct HazardPinDetailSnapshot: Sendable {
    let id: UUID
    let pinType: PinType
    let createdByUsername: String
    let threatClassLabel: String
    let reasonMessage: String

    init(pin: HazardPin) {
        id = pin.id
        pinType = pin.pinType
        createdByUsername = pin.createdByUsername
        threatClassLabel = pin.threatClassLabel
        reasonMessage = pin.reasonMessage
    }
}

/// Medium/large detent sheet showing who placed a hazard pin and why (matches settings/broadcast presentation).
struct HazardPinDetailSheet: View {
    let snapshot: HazardPinDetailSnapshot
    /// Removes the pin on this device and broadcasts to the mesh (by id; safe while this view is visible).
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    private var typeTitle: String {
        switch snapshot.pinType {
        case .danger: return "Danger zone"
        case .safeRoute: return "Safe route"
        }
    }

    private var accent: Color {
        switch snapshot.pinType {
        case .danger: return ProjectTheme.warning
        case .safeRoute: return ProjectTheme.signal
        }
    }

    private var creatorLine: String {
        let s = snapshot.createdByUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? "Unknown" : s
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 10) {
                        Image(systemName: snapshot.pinType == .danger ? "exclamationmark.triangle.fill" : "figure.walk.diamond.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(accent)
                        Text(typeTitle)
                            .font(.system(size: 24, weight: .black, design: .rounded))
                            .foregroundStyle(ProjectTheme.textPrimary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Created by")
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                            .foregroundStyle(ProjectTheme.textSecondary)
                        Text(creatorLine)
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundStyle(ProjectTheme.textPrimary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(ProjectTheme.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(ProjectTheme.panelBorder, lineWidth: 1)
                    )

                    if !snapshot.threatClassLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Threat class")
                                .font(.system(size: 12, weight: .heavy, design: .rounded))
                                .foregroundStyle(ProjectTheme.textSecondary)
                            Text(snapshot.threatClassLabel)
                                .font(.system(size: 15, weight: .medium, design: .rounded))
                                .foregroundStyle(ProjectTheme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(ProjectTheme.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(ProjectTheme.panelBorder, lineWidth: 1)
                        )
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Reason")
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                            .foregroundStyle(ProjectTheme.textSecondary)
                        Text(snapshot.reasonMessage.trimmingCharacters(in: .whitespacesAndNewlines))
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(ProjectTheme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(ProjectTheme.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(ProjectTheme.panelBorder, lineWidth: 1)
                    )
                }
                .padding(20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(red: 0.05, green: 0.07, blue: 0.09).ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button(role: .destructive) {
                            confirmDelete = true
                        } label: {
                            Label("Delete zone", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(ProjectTheme.textPrimary)
                    }
                }
            }
            .confirmationDialog(
                "Delete this zone?",
                isPresented: $confirmDelete,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    onDelete()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes it on all connected devices.")
            }
        }
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(22)
    }
}

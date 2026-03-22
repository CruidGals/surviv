import SwiftUI

/// Medium/large detent sheet showing who placed a hazard pin and why (matches settings/broadcast presentation).
struct HazardPinDetailSheet: View {
    let pin: HazardPin
    @Environment(\.dismiss) private var dismiss

    private var typeTitle: String {
        switch pin.pinType {
        case .danger: return "Danger zone"
        case .safeRoute: return "Safe route"
        }
    }

    private var accent: Color {
        switch pin.pinType {
        case .danger: return ProjectTheme.warning
        case .safeRoute: return ProjectTheme.signal
        }
    }

    private var creatorLine: String {
        let s = pin.createdByUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? "Unknown" : s
    }

    private var reasonLine: String {
        let s = pin.reasonMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? "No reason on file." : s
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 10) {
                        Image(systemName: pin.pinType == .danger ? "exclamationmark.triangle.fill" : "figure.walk.diamond.fill")
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

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Reason")
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                            .foregroundStyle(ProjectTheme.textSecondary)
                        Text(reasonLine)
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

                    if !pin.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Label")
                                .font(.system(size: 12, weight: .heavy, design: .rounded))
                                .foregroundStyle(ProjectTheme.textSecondary)
                            Text(pin.label)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(ProjectTheme.textSecondary)
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
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(22)
    }
}

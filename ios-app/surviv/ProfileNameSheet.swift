import SwiftUI

struct ProfileNameSheet: View {
    @Binding var storedName: String
    let title: String
    let subtitle: String
    let isRequired: Bool
    let doneButtonTitle: String
    let onComplete: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var draftName: String
    @State private var hasAttemptedSave = false

    init(
        storedName: Binding<String>,
        title: String,
        subtitle: String,
        isRequired: Bool = false,
        doneButtonTitle: String = "Save",
        onComplete: (() -> Void)? = nil
    ) {
        self._storedName = storedName
        self.title = title
        self.subtitle = subtitle
        self.isRequired = isRequired
        self.doneButtonTitle = doneButtonTitle
        self.onComplete = onComplete
        self._draftName = State(initialValue: storedName.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var normalizedName: String {
        draftName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isNameLengthValid: Bool {
        let count = normalizedName.count
        return count >= 2 && count <= 24
    }

    private var shouldShowValidationError: Bool {
        hasAttemptedSave && !isNameLengthValid
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(title)
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundStyle(SurvivTheme.textPrimary)

                Text(subtitle)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(SurvivTheme.textSecondary)

                VStack(alignment: .leading, spacing: 8) {
                    TextField("Your name", text: $draftName)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit(saveIfValid)
                        .foregroundStyle(SurvivTheme.textPrimary)
                        .padding(12)
                        .background(
                            Color.white.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )

                    HStack {
                        if shouldShowValidationError {
                            Text("Use 2 to 24 characters")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(SurvivTheme.danger)
                        } else {
                            Text("Visible to all network users")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(SurvivTheme.textSecondary)
                        }
                        Spacer()
                        Text("\(normalizedName.count)/24")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(SurvivTheme.textSecondary)
                    }
                }

                Spacer()

                Button(action: saveTapped) {
                    Text(doneButtonTitle)
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .background(
                    SurvivTheme.safe.opacity(isNameLengthValid ? 0.85 : 0.5),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .disabled(!isNameLengthValid)
                .opacity(isNameLengthValid ? 1.0 : 0.6)
            }
            .padding(20)
            .background(SurvivTheme.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !isRequired {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            dismiss()
                        }
                        .foregroundStyle(SurvivTheme.safe)
                    }
                }
            }
        }
        .interactiveDismissDisabled(isRequired)
    }

    private func saveTapped() {
        hasAttemptedSave = true
        saveIfValid()
    }

    private func saveIfValid() {
        guard isNameLengthValid else { return }
        storedName = normalizedName
        Haptics.success()
        onComplete?()
        dismiss()
    }
}

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

                Text(subtitle)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    TextField("Your name", text: $draftName)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit(saveIfValid)
                        .padding(12)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                    HStack {
                        if shouldShowValidationError {
                            Text("Use 2 to 24 characters")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(.red)
                        } else {
                            Text("This name appears on your mesh alerts")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(normalizedName.count)/24")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button(action: saveTapped) {
                    Text(doneButtonTitle)
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isNameLengthValid)
            }
            .padding(20)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !isRequired {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
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

#if os(iOS)
import AVECore
import SwiftUI

/// « Créer une image » (maquette 4) : description de 1 000 caractères au maximum, format et qualité. La demande est
/// explicite : une image n'est jamais créée par surprise.
struct CreateImageSheet: View {
    let onCreate: (String, ImageSize, ImageQuality) -> Void
    @State private var prompt = ""
    @State private var size: ImageSize = .square
    @State private var quality: ImageQuality = .hd
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    private var trimmed: String { prompt.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var tooLong: Bool { trimmed.count > MediaTaskRequest.promptMaxCharacters }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Un marché de Conakry au lever du soleil, couleurs chaudes…", text: $prompt, axis: .vertical)
                        .lineLimit(3...8)
                        .focused($focused)
                } footer: {
                    if tooLong {
                        Text(UserMessages.mediaError(code: "prompt_too_long")).foregroundStyle(.red)
                    } else {
                        Text(UserMessages.imageCreationHint)
                    }
                }
                Section("Format") {
                    Picker("Format", selection: $size) {
                        ForEach(ImageSize.allCases, id: \.self) { Text(MediaFormat.aspect($0)).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Picker("Qualité", selection: $quality) {
                        Text("1080p").tag(ImageQuality.hd)
                        Text("4K · plus long").tag(ImageQuality.uhd)
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("Créer une image")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Créer") {
                        onCreate(trimmed, size, quality)
                        dismiss()
                    }
                    .disabled(trimmed.isEmpty || tooLong)
                }
            }
            .onAppear { focused = true }
        }
    }
}

/// « Modifier la photo » (maquette 11) : la consigne et, pour une photo envoyée, la case d'accord des CGU.
struct EditImageSheet: View {
    let needsRights: Bool
    let onEdit: (String, Bool) -> Void
    @State private var instruction = ""
    @State private var rights = false
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    private var trimmed: String { instruction.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Lumière plus douce, fond flou", text: $instruction, axis: .vertical)
                        .lineLimit(2...6)
                        .focused($focused)
                }
                if needsRights {
                    Section { RightsToggle(isOn: $rights) } footer: { Text(UserMessages.fileForgotten) }
                }
            }
            .navigationTitle("Modifier la photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Modifier") {
                        onEdit(trimmed, rights)
                        dismiss()
                    }
                    .disabled(trimmed.isEmpty || (needsRights && !rights))
                }
            }
            .onAppear { focused = true }
        }
    }
}

/// Agrandir ou prolonger une photo envoyée : la même case d'accord, une seule fois par photo.
struct RightsSheet: View {
    let actionTitle: String
    let onConfirm: () -> Void
    @State private var rights = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section { RightsToggle(isOn: $rights) } footer: { Text(UserMessages.fileForgotten) }
            }
            .navigationTitle(actionTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Continuer") {
                        onConfirm()
                        dismiss()
                    }
                    .disabled(!rights)
                }
            }
        }
    }
}

/// Rien n'est acquis d'avance (CGU §2 : retoucher la photo d'une personne réelle exige son accord). Interrupteur du
/// système : le propriétaire exige les composants natifs d'iOS, et le HIG préfère l'interrupteur à la case sur iOS.
struct RightsToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(UserMessages.rightsConfirmation).font(.subheadline)
        }
    }
}

/// « Reformuler… » : le moteur exige une consigne (`instruction`).
struct RewriteSheet: View {
    let onRewrite: (String) -> Void
    @State private var instruction = ""
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    private var trimmed: String { instruction.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Plus simple, plus court, plus poli…", text: $instruction, axis: .vertical)
                        .lineLimit(2...6)
                        .focused($focused)
                } footer: {
                    Text("Le document reformulé est rendu sous forme de texte.")
                }
            }
            .navigationTitle("Reformuler")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Reformuler") {
                        onRewrite(trimmed)
                        dismiss()
                    }
                    .disabled(trimmed.isEmpty)
                }
            }
            .onAppear { focused = true }
        }
    }
}

/// « Signaler cette image » (maquette 9) : sept motifs dans l'ordre de priorité du moteur, une note facultative.
struct ReportSheet: View {
    let onReport: (ReportReason, String?) -> Void
    @State private var reason: ReportReason?
    @State private var note = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(ReportReason.allCases, id: \.self) { item in
                        Button { reason = item } label: {
                            HStack {
                                Text(UserMessages.reportReason(item)).foregroundStyle(.primary)
                                Spacer()
                                if reason == item { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
                            }
                            .contentShape(Rectangle())
                        }
                        .accessibilityAddTraits(reason == item ? .isSelected : [])
                    }
                } footer: {
                    Text(UserMessages.reportHidden)
                }
                Section {
                    TextField("Précisez si vous le souhaitez (facultatif)", text: $note, axis: .vertical)
                        .lineLimit(2...5)
                        .onChange(of: note) { _, new in
                            if new.count > MediaLimits.reportNoteMaxCharacters {
                                note = String(new.prefix(MediaLimits.reportNoteMaxCharacters))
                            }
                        }
                }
            }
            .navigationTitle("Signaler cette image")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Envoyer") {
                        if let reason { onReport(reason, note) }
                        dismiss()
                    }
                    .disabled(reason == nil)
                }
            }
        }
    }
}
#endif

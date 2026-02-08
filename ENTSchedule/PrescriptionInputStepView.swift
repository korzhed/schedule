import SwiftUI

struct PrescriptionInputStepView: View {

    @EnvironmentObject private var appState: AppState

    /// Колбэк, в который передаём распознанные лекарства
    let onNext: ([MedicationItem]) -> Void

    @State private var prescriptionText: String = ""
    @State private var parsedMedications: [MedicationItem] = []
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""

    // Голосовой ввод
    @StateObject private var speechRecognizer = SpeechRecognizer()
    @State private var hasSpeechPermission: Bool = true

    /// Состояния диктовки
    @State private var isRecordingFromMic: Bool = false

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {

                HStack(alignment: .firstTextBaseline) {
                    Text("Текст назначения")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)

                    Spacer()

                    if speechRecognizer.isRecording {
                        Label("Слушаю…", systemImage: "waveform")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.blue)
                    }
                }

                ZStack(alignment: .topLeading) {
                    if prescriptionText.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Продиктуйте или вставьте текст назначения…")
                            Text("Нажмите микрофон, надиктуйте и подтвердите галочкой")
                                .font(.footnote)
                        }
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .padding(.top, 12)
                        .padding(.leading, 12)
                    }

                    // TextEditor + микрофон в углу
                    ZStack(alignment: .bottomTrailing) {
                        TextEditor(text: $prescriptionText)
                            .frame(minHeight: 180)
                            .scrollContentBackground(.hidden)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color(.secondarySystemBackground))
                            )
                            .contentShape(Rectangle())

                        micButton
                            .padding(.trailing, 8)
                            .padding(.bottom, 8)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color(.separator), lineWidth: 1)
                    )
                }


                // Распознанные лекарства
                if !parsedMedications.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Распознанные лекарства")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        VStack(spacing: 12) {
                            ForEach(parsedMedications) { med in
                                HStack(alignment: .top, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 12) {
                                        Text(med.name)
                                            .font(.headline)

                                        HStack(spacing: 16) {
                                            Label(med.dosage, systemImage: "scalemass")
                                            Label("\(med.timesPerDay) раз/день", systemImage: "clock")
                                            Label("\(med.durationInDays) дней", systemImage: "calendar")
                                        }
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                        if let comment = med.comment, !comment.isEmpty {
                                            Text(comment)
                                                .font(.caption)
                                                .foregroundStyle(.orange)
                                        }
                                    }

                                    Spacer()

                                    Button(role: .destructive) {
                                        deleteMedication(med)
                                    } label: {
                                        Image(systemName: "trash")
                                            .imageScale(.medium)
                                            .foregroundStyle(.red)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(.ultraThinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .contextMenu {
                                    Button(role: .destructive) {
                                        deleteMedication(med)
                                    } label: {
                                        Label("Удалить", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground))
        .onTapGesture {
                hideKeyboard()
            }
        .navigationTitle("Новое назначение")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Далее") {
                    onNext(parsedMedications)
                }
                .disabled(parsedMedications.isEmpty)
            }
        }
        .safeAreaInset(edge: .bottom) {
            bottomBar
        }
        .alert("Ошибка парсинга", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - Voice UI

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil,
                                        from: nil,
                                        for: nil)
    }
    
    private var micButton: some View {
        let isRecording = isRecordingFromMic

        let iconName = isRecording ? "checkmark" : "mic.fill"
        let iconColor: Color = isRecording ? .green : .blue
        let circleFill: AnyShapeStyle = isRecording
            ? AnyShapeStyle(Color.green.opacity(0.25))
            : AnyShapeStyle(.ultraThinMaterial)
        let shadowColor: Color = isRecording ? .green : .blue

        return Image(systemName: iconName)
            .font(.system(size: 24, weight: .semibold))
            .foregroundStyle(iconColor)
            .padding(14)
            .background(
                Circle()
                    .fill(circleFill)
            )
            .shadow(color: shadowColor.opacity(0.25), radius: 4, x: 0, y: 2)
            .contentShape(Circle())
            .onTapGesture {
                if isRecordingFromMic {
                    stopAndParseDictation()
                } else {
                    hideKeyboard()
                    startDictation()
                }
            }
    }




    private func startDictation() {
        isRecordingFromMic = true
        prescriptionText = ""
        speechRecognizer.transcribedText = ""

        speechRecognizer.requestAuthorization { granted in
            if granted {
                speechRecognizer.start()
                speechRecognizer.onUpdate = { newText in
                    let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
                    prescriptionText = trimmed
                }
            } else {
                hasSpeechPermission = false
                errorMessage = "Нет доступа к распознаванию речи. Проверьте настройки приватности."
                showError = true
                isRecordingFromMic = false
            }
        }
    }

    private func stopAndParseDictation() {
        isRecordingFromMic = false
        speechRecognizer.stop()

        let trimmed = prescriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        parsePrescription()
        prescriptionText = ""
    }

    private func clearInput() {
        prescriptionText = ""
        speechRecognizer.transcribedText = ""
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                if !prescriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button {
                        parsePrescription()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "wand.and.stars")
                            Text("Распознать")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.roundedRectangle(radius: 12))
                    .controlSize(.large)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(.systemGroupedBackground))
        }
    }

    // MARK: - Parsing

    private func parsePrescription() {
        let trimmed = prescriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let parser = PrescriptionParser()
        let medications = parser.parse(trimmed)

        if medications.isEmpty {
            errorMessage = "Не удалось распознать лекарства. Проверьте текст назначения."
            showError = true
        } else {
            parsedMedications.append(contentsOf: medications)
        }
    }

    private func deleteMedication(_ med: MedicationItem) {
        parsedMedications.removeAll { $0.id == med.id }
    }
}

struct PrescriptionInputStepView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            PrescriptionInputStepView(onNext: { _ in })
                .environmentObject(AppState())
        }
    }
}

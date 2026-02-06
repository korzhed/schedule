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

    /// Последняя партия лекарств из диктовки — на будущее
    @State private var lastBatch: [MedicationItem] = []

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {

                // Текст назначения
                VStack(alignment: .leading, spacing: 8) {
                    Text("Текст назначения")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    ZStack(alignment: .topLeading) {
                        if prescriptionText.isEmpty {
                            Text("Вставьте текст назначения от врача…")
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .padding(.top, 12)
                                .padding(.leading, 12)
                        }

                        // TextEditor + микрофон в правом нижнем углу
                        ZStack(alignment: .bottomTrailing) {
                            TextEditor(text: $prescriptionText)
                                .frame(minHeight: 180)
                                .scrollContentBackground(.hidden)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 8)

                            Button(action: {
                                toggleRecording()
                            }) {
                                Image(systemName: speechRecognizer.isRecording ? "mic.fill" : "mic")
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundStyle(speechRecognizer.isRecording ? Color.red : Color.blue)
                                    .shadow(color: Color.black.opacity(0.4), radius: 3, x: 0, y: 2)
                            }
                            .padding(.trailing, 8)
                            .padding(.bottom, 8)
                        }
                        .background(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color(.separator), lineWidth: 1)
                        )

                        if speechRecognizer.isRecording {
                            Text("Слушаю…")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .padding(.top, 8)
                                .padding(.leading, 12)
                        }
                    }
                }

                // Результат диктовки + кнопка вставки
                if !speechRecognizer.transcribedText.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Результат диктовки")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(speechRecognizer.transcribedText)
                            .font(.footnote)
                            .foregroundStyle(.primary)
                            .padding(8)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                            )

                        Button(action: {
                            appendDictationToPrescription()
                        }) {
                            Label("Вставить текст назначения", systemImage: "arrow.down.doc")
                                .font(.subheadline)
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .controlSize(.regular)
                        .padding(.top, 4)
                    }
                    .padding(.horizontal, 4)
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
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(med.name)
                                            .font(.headline)

                                        HStack(spacing: 8) {
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
        .navigationTitle("Новое назначение")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            bottomBar
        }
        .alert("Ошибка парсинга", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 8) {
            // более мягкий разделитель, чтобы в тёмной теме не было жёсткой полосы
            Divider()
                .overlay(Color(.separator).opacity(0.4))
                .padding(.horizontal, 16)

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
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.roundedRectangle(radius: 12))
                    .controlSize(.large)
                }

                Button {
                    onNext(parsedMedications)
                } label: {
                    Text("Далее")
                        .frame(maxWidth: .infinity)
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: 12))
                .controlSize(.large)
                .disabled(parsedMedications.isEmpty)
                .opacity(parsedMedications.isEmpty ? 0.5 : 1)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            // вместо серой «полосы» — фон, совпадающий с основным
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
            lastBatch = medications
            parsedMedications.append(contentsOf: medications)
        }
    }

    // MARK: - Voice control

    private func toggleRecording() {
        if speechRecognizer.isRecording {
            speechRecognizer.stop()
        } else {
            speechRecognizer.requestAuthorization { granted in
                if granted {
                    speechRecognizer.start()
                } else {
                    hasSpeechPermission = false
                    errorMessage = "Нет доступа к распознаванию речи. Проверьте настройки приватности."
                    showError = true
                }
            }
        }
    }

    /// Вставляем результат текущей диктовки в основной текст,
    /// останавливаем диктовку, очищаем «результат диктовки» и сразу распознаём
    private func appendDictationToPrescription() {
        if speechRecognizer.isRecording {
            speechRecognizer.stop()
        }

        let newPart = speechRecognizer.transcribedText
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newPart.isEmpty else { return }

        if prescriptionText.isEmpty {
            prescriptionText = newPart
        } else {
            prescriptionText += "\n" + newPart
        }

        speechRecognizer.transcribedText = ""
        parsePrescription()
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

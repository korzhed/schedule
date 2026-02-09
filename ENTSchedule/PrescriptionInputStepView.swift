import SwiftUI

struct PrescriptionInputStepView: View {

    @EnvironmentObject private var appState: AppState

    /// Колбэк, в который передаём распознанные лекарства
    let onNext: ([MedicationItem]) -> Void

    @State private var prescriptionText: String = ""
    @State private var parsedMedications: [MedicationItem] = []
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    @State private var showRecordingOverlay: Bool = false
    
    @State private var glowPhase: CGFloat = 0

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
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Продиктуйте или вставьте текст назначения…")
                                .font(.body)
                            Text("Говорите короткими фразами: название — дозировка — кратность — длительность.")
                                .font(.footnote)
                            Text("Например: ‘Називин 2 капли 3 раза в день 7 дней, в каждый носовой ход’.")
                                .font(.footnote)
                            Text("Нажмите микрофон, продиктуйте и подтвердите кнопкой ‘Готово’.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
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
                    .overlay(
                        Group {
                            if isRecordingFromMic {
                                AnimatedGlowBorder(phase: glowPhase)
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                        }
                    )
                    .shadow(color: isRecordingFromMic ? Color.blue.opacity(0.25) : Color.clear, radius: isRecordingFromMic ? 18 : 0)
                    .onAppear {
                        if isRecordingFromMic {
                            withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                                glowPhase = 1
                            }
                        }
                    }
                    .onChange(of: isRecordingFromMic) { newValue, _ in
                        if newValue {
                            glowPhase = 0
                            withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                                glowPhase = 1
                            }
                        }
                    }
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
        .overlay(alignment: .bottom) {
            if showRecordingOverlay {
                RecordingOverlayView(
                    isRecording: isRecordingFromMic,
                    text: speechRecognizer.transcribedText,
                    onStop: { stopAndParseDictation() },
                    onCancel: {
                        isRecordingFromMic = false
                        speechRecognizer.stop()
                        showRecordingOverlay = false
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
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
    
    @ViewBuilder
    private var micButton: some View {
        let isRecording = isRecordingFromMic

        let iconName = isRecording ? "checkmark" : "mic.fill"
        let baseColor: Color = isRecording ? .green : .blue

        Image(systemName: iconName)
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(.white) // ← иконка всегда белая
            .padding(12)
            .background(
                Circle().fill(.clear)
            )
            .glassEffect(
                .regular
                    .tint(baseColor.opacity(0.9)) // цвет стекла
                    .interactive()
            )
            .clipShape(Circle())
            .overlay(
                Circle()
                    .strokeBorder(.white.opacity(0.35), lineWidth: 1)
                    .blendMode(.screen)
            )
            .shadow(color: baseColor.opacity(0.35), radius: 10)
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
        showRecordingOverlay = true
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
        showRecordingOverlay = false
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
    
    private struct RecordingOverlayView: View {
        let isRecording: Bool
        let text: String
        let onStop: () -> Void
        let onCancel: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: isRecording ? "waveform" : "checkmark.circle")
                        .foregroundStyle(isRecording ? .blue : .green)
                    Text(isRecording ? "Слушаю…" : "Готово")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Spacer()
                    Button(role: .cancel) {
                        onCancel()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                }

                Text(text.isEmpty ? "Говорите…" : text)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentTransition(.opacity)

                HStack {
                    Button {
                        onStop()
                    } label: {
                        HStack {
                            Image(systemName: "checkmark")
                            Text("Готово")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                }
            }
            .padding(14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color(.separator), lineWidth: 1)
            )
            .shadow(radius: 8)
        }
    }
    
    private struct AnimatedGlowBorder: View {
        let phase: CGFloat

        var body: some View {
            GeometryReader { geo in
                let gradient = AngularGradient(
                    gradient: Gradient(colors: [
                        .blue.opacity(0.0),
                        .blue.opacity(0.6),
                        .purple.opacity(0.6),
                        .blue.opacity(0.6),
                        .blue.opacity(0.0)
                    ]),
                    center: .center,
                    angle: .degrees(Double(phase) * 360)
                )

                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(gradient, lineWidth: 3)
                    .blur(radius: 4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(gradient, lineWidth: 1)
                            .opacity(0.8)
                    )
                    .animation(nil, value: phase)
            }
        }
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


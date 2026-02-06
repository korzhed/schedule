import Foundation
import Speech
import AVFoundation
import Combine

final class SpeechRecognizer: NSObject, ObservableObject {

    @Published var transcribedText: String = ""
    @Published var isRecording: Bool = false

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "ru-RU"))
    private let audioEngine = AVAudioEngine()

    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    override init() {
        super.init()
    }

    // Запрос разрешения на распознавание речи
    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                completion(status == .authorized)
            }
        }
    }

    /// Старт записи и распознавания.
    /// Если хочешь НЕ очищать текст при новом старте — убери строку `transcribedText = ""`.
    func start() {
        guard !audioEngine.isRunning else { return }

        isRecording = true
        transcribedText = ""   // можно закомментировать, если нужен "накопительный" текст

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("Audio session error: \(error)")
            stop()
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        self.request = request

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            print("Audio engine start error: \(error)")
            stop()
            return
        }

        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }

            if let result = result {
                DispatchQueue.main.async {
                    // Здесь всегда храним ТЕКУЩУЮ диктовку целиком.
                    // Уже «накопленный» текст добавляй во вью:
                    // rawText += speechRecognizer.transcribedText
                    self.transcribedText = result.bestTranscription.formattedString
                }
            }

            if error != nil {
                DispatchQueue.main.async {
                    self.stop()
                }
            }
        }
    }

    /// Остановка записи и распознавания
    func stop() {
        isRecording = false

        if audioEngine.isRunning {
            audioEngine.stop()
        }

        audioEngine.inputNode.removeTap(onBus: 0)

        request?.endAudio()
        recognitionTask?.cancel()

        request = nil
        recognitionTask = nil

        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("Audio session deactivation error: \(error)")
        }
    }
}

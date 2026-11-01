import AVFoundation
import Foundation

/// A live session with Gemini Live, running on the phone. Once he's awake the mic is on the whole
/// time, so everything you say becomes context, but he stays quiet until you hold the screen and ask.
/// He never talks out loud: replies are text (speech bubbles on the Mac) with a little cartoon chirp here.
/// Tools (look at the screen, point) run on the Mac.
final class LiveVoice: NSObject, ObservableObject, URLSessionWebSocketDelegate {
    enum State: Equatable { case asleep, waking, listening, asking, thinking, speaking }

    @Published private(set) var state: State = .asleep

    static let model = "gemini-3.8-live"

    /// Asks the Mac for a short-lived key. Calls back with nil on failure.
    var requestToken: ((@escaping (String?) -> Void) -> Void)?
    /// Runs a tool on the Mac: (name, JSON arguments) → (output text, optional JPEG base64).
    var runTool: ((String, String, @escaping (String, String?) -> Void) -> Void)?
    /// What he's saying, as it streams in. `done` is true when the reply finished.
    var onCaption: ((String, _ done: Bool) -> Void)?
    var onError: ((String) -> Void)?
    var onStateChange: ((State) -> Void)?
    /// For the saved transcript: a session started or ended, something you said (in order, then its words), his replies.
    var onSessionStart: (() -> Void)?
    var onSessionEnd: (() -> Void)?
    var onUserTurn: ((_ itemID: String, _ asked: Bool) -> Void)?
    var onUserWords: ((_ itemID: String, _ text: String, _ asked: Bool) -> Void)?
    var onTypedQuestion: ((String) -> Void)?
    var onReply: ((String) -> Void)?
    var onReport: ((String) -> Void)?
    /// Recent transcript, handed to a fresh connection so he keeps context in long sessions.
    var resumeContext: (() -> String?)?

    /// Records the whole session's audio for proper transcription (meeting notes).
    let recorder = ChunkRecorder()
    /// True from wake until you end the session. Dropped connections (sessions time out after an hour)
    /// reconnect on their own while this is set, and the recording carries on.
    private var wantAwake = false
    private var reconnecting = false

    /// Loudness of his chirp right now, 0…1.
    private(set) var level: Double = 0

    var volume: Double {
        get { UserDefaults.standard.object(forKey: "volume") as? Double ?? 1 }
        set {
            UserDefaults.standard.set(newValue, forKey: "volume")
            if audioReady { player.volume = Float(newValue) }
        }
    }

    private var socket: URLSessionWebSocketTask?
    private lazy var webSocketSession = URLSession(
        configuration: .default,
        delegate: self,
        delegateQueue: OperationQueue.main
    )
    private var pendingSetup: [String: Any]?
    private var tokenTimeout: DispatchWorkItem?
    private var setupTimeout: DispatchWorkItem?
    private lazy var engine = AVAudioEngine()
    private lazy var player = AVAudioPlayerNode()
    private var converter: AVAudioConverter?
    private let wireFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)!
    private let playFormat = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1)!
    private var audioReady = false
    private var audioResourcesCreated = false

    private var transcript = ""
    private var pendingBuffers = 0
    private var responseActive = false
    private var sleepAfterReply = false
    /// Holding the screen to ask. Released before the session was ready: ask as soon as it is.
    private var holding = false
    private var askWhenReady = false
    private var chirpedThisResponse = false
    private var awaitingQuestion = false
    private var audioInputActive = false
    private var inputTurnCompleted = false
    private var inputTurnID: String?
    private var inputTranscript = ""
    private var inputTurnAsked = false

    private func setState(_ new: State) {
        guard new != state else { return }
        state = new
        onStateChange?(new)
    }

    // MARK: Wake and sleep

    func toggle() {
        state == .asleep ? wake() : sleep()
    }

    func wake() {
        guard state == .asleep else { return }
        wantAwake = true
        setState(.waking)
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard granted else {
                    self.reportError("Tvo needs microphone access. Turn it on for Tvo in the iPhone's Settings.")
                    self.wantAwake = false
                    self.setState(.asleep)
                    return
                }
                guard let requestToken = self.requestToken else {
                    self.reportError("I couldn't reach Tvo on your Mac. Open Tvo on your Mac and connect both devices to the same Wi-Fi.")
                    self.wantAwake = false
                    self.setState(.asleep)
                    return
                }
                let timeout = DispatchWorkItem { [weak self] in
                    guard let self, self.state == .waking, self.socket == nil else { return }
                    self.reportError("Tvo on your Mac took too long to prepare the Gemini session. Check the Mac's internet connection and try again.")
                    self.sleep()
                }
                self.tokenTimeout = timeout
                DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: timeout)
                self.requestSessionToken(requestToken)
            }
        }
    }

    private func requestSessionToken(_ requestToken: @escaping (@escaping (String?) -> Void) -> Void) {
        guard state == .waking, socket == nil else { return }
        requestToken { [weak self] token in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.state == .waking, self.socket == nil else { return }
                if let token {
                    self.tokenTimeout?.cancel()
                    self.tokenTimeout = nil
                    self.connect(token)
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                        guard let self, self.state == .waking, self.socket == nil else { return }
                        self.requestSessionToken(requestToken)
                    }
                }
            }
        }
    }

    func sleep() {
        let wasRunning = wantAwake || socket != nil
        wantAwake = false
        reconnecting = false
        recorder.finish()
        if wasRunning { onSessionEnd?() }
        awaitingQuestion = false
        audioInputActive = false
        inputTurnCompleted = false
        inputTurnID = nil
        inputTranscript = ""
        inputTurnAsked = false
        socket?.cancel(with: .normalClosure, reason: nil)
        socket = nil
        pendingSetup = nil
        tokenTimeout?.cancel()
        tokenTimeout = nil
        setupTimeout?.cancel()
        setupTimeout = nil
        stopAudio()
        transcript = ""
        pendingBuffers = 0
        responseActive = false
        sleepAfterReply = false
        holding = false
        askWhenReady = false
        toolsRunning = 0
        level = 0
        setState(.asleep)
    }

    private func reportError(_ message: String) {
        onCaption?(message, true)
        onError?(message)
    }

    /// Says a quick hi (for checking the chirp volume).
    func sayHi() {
        guard socket != nil else { wake(); return }
        endAudioInput()
        setState(.thinking)
        send(["clientContent": [
            "turns": [["role": "user", "parts": [["text": "Reply with a quick, cheerful hi in under eight words."]]]],
            "turnComplete": true,
        ]])
    }

    // MARK: Hold to ask

    /// You pressed and held the screen: what you say now is the question.
    func beginAsk() {
        holding = true
        onCaption?("", false)  // clears his last bubble
        if state == .asleep { wake(); return }
        guard socket != nil else { return }
        startAudioInput()
        if state == .listening || state == .speaking { setState(.asking) }
    }

    /// You let go: he answers (or does the thing) using everything he's heard as context.
    func endAsk() {
        guard holding else { return }
        holding = false
        guard socket != nil, state != .waking else { askWhenReady = true; return }
        guard !inputTurnCompleted else {
            endAudioInput()
            if state == .asking { setState(.listening) }
            return
        }
        ask()
    }

    private func ask() {
        askWhenReady = false
        setState(.thinking)
        awaitingQuestion = true
        endAudioInput()
    }

    @discardableResult
    func askText(_ question: String) -> Bool {
        let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, state == .listening, socket != nil else { return false }

        endAudioInput()
        onTypedQuestion?(question)
        inputTurnCompleted = false
        setState(.thinking)
        awaitingQuestion = true
        send(["clientContent": [
            "turns": [["role": "user", "parts": [["text": question]]]],
            "turnComplete": true,
        ]])
        return true
    }

    // MARK: Connection

    private func connect(_ tokenPayload: String) {
        guard let payload = try? JSONSerialization.jsonObject(with: Data(tokenPayload.utf8)) as? [String: Any] else {
            reportError("I couldn't read the Gemini session setup from the Mac.")
            sleep()
            return
        }
        if let error = payload["error"] as? String {
            reportError(error)
            sleep()
            return
        }
        guard let token = payload["token"] as? String,
              let setup = payload["setup"] as? [String: Any],
              var components = URLComponents(string: "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1alpha.GenerativeService.BidiGenerateContentConstrained") else {
            reportError("I couldn't read the Gemini session setup from the Mac.")
            sleep()
            return
        }
        components.queryItems = [URLQueryItem(name: "access_token", value: token)]
        guard let url = components.url else {
            reportError("I couldn't connect to Gemini.")
            sleep()
            return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let socket = webSocketSession.webSocketTask(with: request)
        self.socket = socket
        pendingSetup = setup
        NSLog("Googly Gemini Live: opening WebSocket")
        socket.resume()
        let timeout = DispatchWorkItem { [weak self, weak socket] in
            guard let self, let socket, self.socket === socket, self.state == .waking else { return }
            NSLog("Googly Gemini Live: setup timed out")
            self.reportError("Gemini took too long to finish starting the voice session. Check your internet connection and try again.")
            self.sleep()
        }
        setupTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: timeout)
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        guard webSocketTask === socket, let setup = pendingSetup else { return }
        pendingSetup = nil
        NSLog("Googly Gemini Live: WebSocket opened; sending setup")
        receive(on: webSocketTask)
        send(["setup": setup])
    }

    /// The connection dropped mid-session: get a new key and carry on, keeping the mic and recording running.
    private func reconnect(attempt: Int = 0) {
        socket = nil
        pendingSetup = nil
        responseActive = false
        toolsRunning = 0
        audioInputActive = false
        inputTurnID = nil
        inputTranscript = ""
        guard wantAwake, let requestToken else { return }
        reconnecting = true
        requestToken { [weak self] token in
            DispatchQueue.main.async {
                guard let self, self.wantAwake, self.socket == nil else { return }
                if let token {
                    self.connect(token)
                } else {
                    // The Mac may be briefly away; keep trying (the recording continues meanwhile).
                    DispatchQueue.main.asyncAfter(deadline: .now() + min(30, 2 + Double(attempt) * 3)) {
                        self.reconnect(attempt: attempt + 1)
                    }
                }
            }
        }
    }

    private func send(_ event: [String: Any]) {
        guard let socket, let data = try? JSONSerialization.data(withJSONObject: event),
              let text = String(data: data, encoding: .utf8) else { return }
        socket.send(.string(text)) { error in
            if let error { NSLog("Googly Gemini Live send failed: %@", error.localizedDescription) }
        }
    }

    private func receive(on socket: URLSessionWebSocketTask) {
        socket.receive { [weak self] result in
            guard let self, socket === self.socket else { return }
            switch result {
            case .success(let message):
                let data: Data
                let frameType: String
                switch message {
                case .string(let text):
                    data = Data(text.utf8)
                    frameType = "text"
                case .data(let binary):
                    data = binary
                    frameType = "binary"
                }
                guard let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    NSLog("Googly Gemini Live: ignored non-JSON WebSocket message (%d bytes)", data.count)
                    self.receive(on: socket)
                    return
                }
                if event["setupComplete"] != nil {
                    NSLog("Googly Gemini Live: received setupComplete in %@ frame", frameType)
                } else if event["error"] != nil {
                    NSLog("Googly Gemini Live: received server error in %@ frame", frameType)
                }
                DispatchQueue.main.async { self.handle(event) }
                self.receive(on: socket)
            case .failure(let error):
                NSLog("Googly Gemini Live receive failed: %@", error.localizedDescription)
                DispatchQueue.main.async {
                    guard socket === self.socket else { return }
                    if self.state == .waking, !self.reconnecting {
                        self.reportError("Gemini's voice connection failed before Tvo finished waking: \(error.localizedDescription)")
                        self.sleep()
                    } else if self.wantAwake {
                        self.reconnect()
                    } else {
                        self.sleep()
                    }
                }
            }
        }
    }

    // MARK: Events

    private func handle(_ event: [String: Any]) {
        if event["setupComplete"] != nil {
            sessionReady()
            return
        }
        if let error = event["error"] as? [String: Any] {
            let message = error["message"] as? String ?? "Unknown error"
            NSLog("Googly Gemini Live error: \(message)")
            reportError("Gemini couldn't continue the voice session: \(message)")
            sleep()
            return
        }

        let content = event["serverContent"] as? [String: Any]
        if let input = content?["inputTranscription"] as? [String: Any],
           let text = input["text"] as? String, !text.isEmpty {
            if inputTurnID == nil {
                let id = UUID().uuidString
                inputTurnID = id
                inputTranscript = ""
                inputTurnAsked = holding || awaitingQuestion
                onUserTurn?(id, inputTurnAsked)
                awaitingQuestion = false
            }
            inputTranscript += text
            if let inputTurnID {
                onUserWords?(inputTurnID, inputTranscript, inputTurnAsked)
            }
        }
        if let output = content?["outputTranscription"] as? [String: Any],
           let text = output["text"] as? String, !text.isEmpty {
            responseActive = true
            if transcript.isEmpty { chirpedThisResponse = false }
            transcript += text
            if !chirpedThisResponse, !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                chirpedThisResponse = true
                setState(.speaking)
                chirp(syllables: min(max(transcript.split(separator: " ").count, 3), 5))
            }
            onCaption?(transcript, false)
        }
        if let toolCall = event["toolCall"] as? [String: Any],
           let calls = toolCall["functionCalls"] as? [[String: Any]], !calls.isEmpty {
            responseActive = true
            if state != .speaking { setState(.thinking) }
            runTools(calls)
        }
        if content?["turnComplete"] as? Bool == true || content?["generationComplete"] as? Bool == true {
            responseActive = false
            if !transcript.isEmpty {
                onCaption?(transcript, true)
                onReply?(transcript)
                transcript = ""
            }
            inputTurnID = nil
            inputTranscript = ""
            awaitingQuestion = false
            inputTurnCompleted = true
            if toolsRunning == 0, !sleepAfterReply {
                if askWhenReady {
                    askWhenReady = false
                    onCaption?("Tvo is ready now. Hold the screen and repeat your question.", true)
                }
            }
            finishIfQuiet()
        }
    }

    private func sessionReady() {
        setupTimeout?.cancel()
        setupTimeout = nil
        NSLog("Googly Gemini Live: setup complete")
        if reconnecting {
            reconnecting = false
            if let context = resumeContext?(), !context.isEmpty {
                send(["clientContent": [
                    "turns": [["role": "user", "parts": [["text": "(Context: what I said earlier in this session, from my notes. Don't reply to this.)\n" + context]]]],
                    "turnComplete": false,
                ]])
            }
        } else {
            do {
                try startAudio()
            } catch {
                reportError("I couldn't start the microphone: \(error.localizedDescription)")
                sleep()
                return
            }
            onSessionStart?()
            chirp(syllables: 2)
        }
        if holding { startAudioInput() }
        if askWhenReady {
            askWhenReady = false
            setState(.listening)
            onCaption?("Tvo is ready now. Hold the screen and repeat your question.", true)
        } else {
            setState(holding ? .asking : .listening)
        }
    }

    private func startAudioInput() {
        guard socket != nil, wantAwake else { return }
        inputTurnCompleted = false
        audioInputActive = true
    }

    private func endAudioInput() {
        guard audioInputActive else { return }
        audioInputActive = false
        send(["realtimeInput": ["audioStreamEnd": true]])
    }

    private func runTools(_ calls: [[String: Any]]) {
        var remaining = calls.count
        toolsRunning += 1
        var images = [String?](repeating: nil, count: calls.count)
        var responses = [[String: Any]?](repeating: nil, count: calls.count)
        for (index, call) in calls.enumerated() {
            let name = call["name"] as? String ?? ""
            let callID = call["id"] as? String ?? UUID().uuidString
            let argumentsObject = call["args"] as? [String: Any] ?? [:]
            let argumentsData = (try? JSONSerialization.data(withJSONObject: argumentsObject)) ?? Data("{}".utf8)
            let arguments = String(data: argumentsData, encoding: .utf8) ?? "{}"
            if name == "go_to_sleep" { sleepAfterReply = true }
            let finish: (String, String?) -> Void = { [weak self] output, image in
                DispatchQueue.main.async {
                    guard let self, self.socket != nil else { return }
                    if name == "web_research", let range = output.range(of: "\n---REPORT---\n") {
                        self.onReport?(String(output[range.upperBound...]))
                    }
                    responses[index] = [
                        "id": callID,
                        "name": name,
                        "response": ["result": output],
                    ]
                    images[index] = image
                    remaining -= 1
                    if remaining == 0 {
                        self.toolsRunning = max(0, self.toolsRunning - 1)
                        for image in images.compactMap({ $0 }) {
                            self.send(["clientContent": [
                                "turns": [["role": "user", "parts": [["inlineData": ["mimeType": "image/jpeg", "data": image]]]]],
                                "turnComplete": false,
                            ]])
                        }
                        self.send(["toolResponse": ["functionResponses": responses.compactMap({ $0 })]])
                    }
                }
            }
            if let runTool { runTool(name, arguments, finish) } else { finish("The Mac isn't connected.", nil) }
        }
    }

    private var toolsRunning = 0

    /// Back to listening once he's replied and chirped (or asleep, if he said goodbye).
    private func finishIfQuiet() {
        guard pendingBuffers == 0, !responseActive, toolsRunning == 0 else { return }
        if sleepAfterReply { sleep(); return }
        if state == .speaking || state == .thinking { setState(holding ? .asking : .listening) }
    }

    // MARK: Audio

    private func startAudio() throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true)
        #endif

        audioResourcesCreated = true
        if !audioReady {
            let input = engine.inputNode
            try input.setVoiceProcessingEnabled(true)  // echo cancellation, so he doesn't hear himself
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: playFormat)
            player.installTap(onBus: 0, bufferSize: 1024, format: playFormat) { [weak self] buffer, _ in
                guard let self, let samples = buffer.floatChannelData?[0] else { return }
                var sum: Float = 0
                for i in 0..<Int(buffer.frameLength) { sum += samples[i] * samples[i] }
                let rms = sqrt(sum / Float(max(buffer.frameLength, 1)))
                self.level = min(1, Double(rms) * 5)
            }
            audioReady = true
        }
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        converter = AVAudioConverter(from: inputFormat, to: wireFormat)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2400, format: inputFormat) { [weak self] buffer, _ in
            self?.recorder.append(buffer)
            self?.sendMic(buffer)
        }
        player.volume = Float(volume)
        engine.prepare()
        try engine.start()
        player.play()
    }

    private func stopAudio() {
        guard audioResourcesCreated else { return }
        engine.inputNode.removeTap(onBus: 0)
        player.stop()
        engine.stop()
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    private func sendMic(_ buffer: AVAudioPCMBuffer) {
        guard let converter else { return }
        let ratio = wireFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 32)
        guard let out = AVAudioPCMBuffer(pcmFormat: wireFormat, frameCapacity: capacity) else { return }
        var fed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, out.frameLength > 0, let samples = out.int16ChannelData?[0] else { return }
        let data = Data(bytes: samples, count: Int(out.frameLength) * 2)
        DispatchQueue.main.async {
            guard self.audioInputActive else { return }
            self.send(["realtimeInput": [
                "audio": ["data": data.base64EncodedString(), "mimeType": "audio/pcm;rate=16000"],
            ]])
        }
    }

    /// A tiny cartoon chirp: a few soft, round, bell-like notes from a happy pentatonic scale,
    /// each with a little upward "boop" at the start, like a small creature humming.
    private func chirp(syllables: Int) {
        guard audioReady else { return }
        let rate = playFormat.sampleRate
        // C major pentatonic, two octaves up high (C6…E7), so it always sounds sweet together.
        let scale = [1046.5, 1174.7, 1318.5, 1568.0, 1760.0, 2093.0, 2349.3, 2637.0]
        var index = Int.random(in: 1...3)
        var samples: [Float] = []
        for i in 0..<syllables {
            if i > 0 { index = min(max(index + [-1, 1, 1, 2].randomElement()!, 0), scale.count - 1) }
            let note = scale[index] * 0.5  // drop an octave: rounder, less piercing
            let duration = i == syllables - 1 ? 0.13 : Double.random(in: 0.07...0.09)
            let count = Int(duration * rate)
            var phase = 0.0
            for n in 0..<count {
                let time = Double(n) / rate
                let t = Double(n) / Double(count)
                // Scoops up into the note over the first 25 ms, with a gentle wobble on the last one.
                let scoop = 1 - 0.18 * exp(-time / 0.012)
                let wobble = i == syllables - 1 ? 1 + 0.012 * sin(time * 2 * .pi * 18) : 1
                phase += 2 * .pi * note * scoop * wobble / rate
                let attack = min(1, time / 0.006)
                let envelope = attack * exp(-t * 3.2) * (1 - pow(t, 6))
                let wave = sin(phase) + 0.12 * sin(2 * phase)
                samples.append(Float(wave * envelope * 0.26))
            }
            samples += [Float](repeating: 0, count: Int(rate * 0.028))
        }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: playFormat, frameCapacity: AVAudioFrameCount(samples.count)),
              let out = buffer.floatChannelData?[0] else { return }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { out.update(from: $0.baseAddress!, count: samples.count) }
        pendingBuffers += 1
        player.scheduleBuffer(buffer) { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.pendingBuffers = max(0, self.pendingBuffers - 1)
                if self.pendingBuffers == 0 { self.level = 0 }
                self.finishIfQuiet()
            }
        }
    }
}

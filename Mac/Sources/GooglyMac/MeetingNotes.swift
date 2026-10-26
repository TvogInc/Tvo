import Foundation

/// Turns recorded audio into a proper transcript (with speaker labels) and keeps each session's
/// meeting notes as plain files any agent can read: ~/Documents/Tvo Notes/<date> <id>/.
enum MeetingNotes {
    static let model = "gemini-3.8-flash"

    static var root: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let root = documents.appendingPathComponent("Tvo Notes", isDirectory: true)
        let legacy = documents.appendingPathComponent("Bluey Notes", isDirectory: true)
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: root.path), fileManager.fileExists(atPath: legacy.path) {
            do {
                try fileManager.moveItem(at: legacy, to: root)
            } catch {
                NSLog("Tvo: couldn't rename the old meeting-notes folder: %@", error.localizedDescription)
                return legacy
            }
        }
        return root
    }

    struct Segment {
        var speaker: String
        var start: Double
        var end: Double
        var text: String
    }

    // MARK: Folders

    /// The session's folder, made the first time it's needed.
    static func folder(session: String, started: Date) -> URL {
        let fm = FileManager.default
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        writeReadmeIfNeeded()
        let tag = String(session.prefix(8)).lowercased()
        if let existing = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil))?
            .first(where: { $0.lastPathComponent.hasSuffix(tag) }) {
            return existing
        }
        let name = DateFormatter.folderName.string(from: started) + " " + tag
        let url = root.appendingPathComponent(name, isDirectory: true)
        try? fm.createDirectory(at: url.appendingPathComponent("audio"), withIntermediateDirectories: true)
        return url
    }

    private static func writeReadmeIfNeeded() {
        let url = root.appendingPathComponent("README.md")
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        let text = """
        # Tvo Notes

        Meeting notes recorded by Riley's Tvo app (the blueberry on the iPhone). One folder per listening \
        session, named by start time.

        In each session folder:
        - `notes.md`: the full transcript with timestamps and speaker labels, plus Riley's questions to Tvo, \
        Tvo's replies and any research reports, in time order. Start here.
        - `session.json`: the same data, structured.
        - `audio/`: the raw recording, as five-minute AAC chunks.

        Speaker letters (A, B, …) are assigned per five-minute chunk, so the same letter can mean different people \
        in different chunks. Lines marked "(live)" are a rough live transcript for audio that hasn't been fully \
        transcribed yet.
        """
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: Transcription

    /// Saves the chunk's audio into the session folder and transcribes it.
    static func transcribe(audio: Data, session: String, index: Int, sessionStarted: Date) async throws -> (segments: [Segment], folder: URL) {
        let folder = folder(session: session, started: sessionStarted)
        let audioURL = folder.appendingPathComponent("audio", isDirectory: true)
        try? FileManager.default.createDirectory(at: audioURL, withIntermediateDirectories: true)
        try audio.write(to: audioURL.appendingPathComponent(String(format: "chunk-%03d.m4a", index)))
        return (try await transcribe(audio), folder)
    }

    private static func transcribe(_ audio: Data) async throws -> [Segment] {
        let prompt = """
        Transcribe this meeting audio as chronological speaker turns. Assign consistent short speaker labels \
        (A, B, C, ...) within this clip. Include accurate start and end times in seconds. Return only the \
        structured transcription requested by the response schema; do not summarize.
        """
        let schema: [String: Any] = [
            "type": "OBJECT",
            "properties": [
                "segments": [
                    "type": "ARRAY",
                    "items": [
                        "type": "OBJECT",
                        "properties": [
                            "speaker": ["type": "STRING"],
                            "start": ["type": "NUMBER"],
                            "end": ["type": "NUMBER"],
                            "text": ["type": "STRING"],
                        ],
                        "required": ["speaker", "start", "end", "text"],
                    ],
                ],
            ],
            "required": ["segments"],
        ]
        let json = try await post(audio, prompt: prompt, schema: schema)
        let raw = (json["segments"] as? [[String: Any]] ?? []).compactMap { item -> Segment? in
            guard let text = item["text"] as? String else { return nil }
            return Segment(speaker: item["speaker"] as? String ?? "?",
                           start: item["start"] as? Double ?? 0,
                           end: item["end"] as? Double ?? 0,
                           text: text.trimmingCharacters(in: .whitespaces))
        }
        // Join one speaker's consecutive pieces into a single turn.
        var turns: [Segment] = []
        for segment in raw where !segment.text.isEmpty {
            if var last = turns.last, last.speaker == segment.speaker, segment.start - last.end < 2.5 {
                last.text += " " + segment.text
                last.end = segment.end
                turns[turns.count - 1] = last
            } else {
                turns.append(segment)
            }
        }
        return turns
    }

    private static func post(_ audio: Data, prompt: String, schema: [String: Any]) async throws -> [String: Any] {
        guard let key = Keychain.get(.gemini) else { throw RealtimeHost.TokenError.noKey }
        guard var components = URLComponents(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent") else {
            throw RealtimeHost.TokenError.failed("invalid transcription endpoint")
        }
        components.queryItems = [URLQueryItem(name: "key", value: key)]
        guard let url = components.url else { throw RealtimeHost.TokenError.failed("invalid transcription URL") }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "contents": [[
                "role": "user",
                "parts": [
                    ["text": prompt],
                    ["inlineData": ["mimeType": "audio/mp4", "data": audio.base64EncodedString()]],
                ],
            ]],
            "generationConfig": ["responseMimeType": "application/json", "responseSchema": schema],
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code),
              let responseJSON = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidate = (responseJSON["candidates"] as? [[String: Any]])?.first,
              let content = candidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.compactMap({ $0["text"] as? String }).first,
              let json = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else {
            throw RealtimeHost.TokenError.failed("transcription \(code) " + (String(data: data, encoding: .utf8) ?? ""))
        }
        return json
    }

    // MARK: Notes files

    /// Writes session.json and notes.md from the phone's copy of the session. Returns the folder.
    @discardableResult
    static func write(session json: [String: Any]) -> URL? {
        guard let id = json["id"] as? String, let startedAt = json["started"] as? Double else { return nil }
        let started = Date(timeIntervalSince1970: startedAt)
        let folder = folder(session: id, started: started)
        if let data = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: folder.appendingPathComponent("session.json"), options: .atomic)
        }
        try? markdown(json, started: started).write(to: folder.appendingPathComponent("notes.md"), atomically: true, encoding: .utf8)
        return folder
    }

    private static func markdown(_ json: [String: Any], started: Date) -> String {
        let ended = (json["ended"] as? Double).map { Date(timeIntervalSince1970: $0) }
        let entries = json["entries"] as? [[String: Any]] ?? []
        let pending = json["transcribing"] as? Int ?? 0
        let day = DateFormatter()
        day.dateStyle = .full
        day.timeStyle = .short
        let clock = DateFormatter()
        clock.dateFormat = "h:mm:ss a"

        var out = ["# Tvo session: \(day.string(from: started))", ""]
        if let ended {
            let minutes = Int(ended.timeIntervalSince(started) / 60)
            out.append("Ended \(clock.string(from: ended)) (\(minutes / 60)h \(minutes % 60)m).")
        } else {
            out.append("Still recording.")
        }
        if pending > 0 { out.append("\(pending) recording chunk(s) still being transcribed; this file updates when they're done.") }
        let asked = entries.filter { $0["kind"] as? String == "asked" }.count
        if asked > 0 { out.append("Riley asked Tvo \(asked) question(s); they're marked inline below.") }
        out += ["", "## Transcript", ""]

        for entry in entries {
            let text = (entry["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let time = (entry["time"] as? Double).map { clock.string(from: Date(timeIntervalSince1970: $0)) } ?? ""
            switch entry["kind"] as? String {
            case "transcript":
                out.append("**[\(time)] Speaker \(entry["speaker"] as? String ?? "?"):** \(text)")
            case "heard":
                out.append("[\(time)] (live) \(text)")
            case "asked":
                out.append("> **[\(time)] Riley asked Tvo:** \(text)")
            case "reply":
                out.append("> **Tvo:** \(text)")
            case "report":
                let quoted = text.components(separatedBy: "\n").map { "> " + $0 }.joined(separator: "\n")
                out.append("> **Research report:**\n" + quoted)
            default:
                out.append("[\(time)] \(text)")
            }
            out.append("")
        }
        return out.joined(separator: "\n")
    }
}

private extension DateFormatter {
    static let folderName: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH.mm"
        return f
    }()
}

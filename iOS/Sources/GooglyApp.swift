import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

@main
struct GooglyApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

struct RootView: View {
    @StateObject private var link = MacLink()
    @StateObject private var live = LiveVoice()
    @StateObject private var store = SessionStore()
    @StateObject private var updateChecker = PhoneUpdateChecker()
    @AppStorage(Palette.characterColorKey) private var characterColorHex = ""
    @State private var showApp = false
    @State private var showStartupSplash = true
    @Environment(\.scenePhase) private var scenePhase
    @State private var animator = FaceAnimator()
    @State private var showPairing = true
    @State private var holdStart: DispatchWorkItem?
    @State private var holdingToAsk = false
    @State private var liveError: String?
    @State private var dismissedUpdateVersion: String?
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            FaceView(animator: animator)
                .id(characterColorHex)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { live.toggle() }  // double tap: wake up / back to follow mode
                .simultaneousGesture(holdToAsk)

            ModeIndicator(state: live.state)

            SoundButton(link: link, live: live)

            // Tvo's app: sessions, transcripts and settings.
            Button { showApp = true } label: {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.35))
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.white.opacity(0.06)).frame(width: 34, height: 34))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open Tvo")
            .padding(.top, 10)
            .padding(.trailing, 62)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

            if showPairing && !link.connected {
                PairingView { withAnimation(.easeOut(duration: 0.3)) { showPairing = false } }
                    .transition(.opacity)
            }

            if let update = updateChecker.availableUpdate,
               dismissedUpdateVersion != update.version {
                PhoneUpdateBanner(
                    update: update,
                    showGuide: { openURL(URL(string: "https://tvoginc.github.io/Tvo/#install")!) },
                    dismiss: { dismissedUpdateVersion = update.version }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, 18)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .overlay {
            if showStartupSplash {
                TvoLaunchSplash {
                    withAnimation(.easeOut(duration: 0.45)) {
                        showStartupSplash = false
                    }
                }
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .background(Color.black)
        .ignoresSafeArea()
        .phoneChrome()
        .fullScreenCover(isPresented: $showApp) {
            BlueyAppView(store: store, live: live, link: link, updateChecker: updateChecker) { showApp = false }
        }
        .alert("Couldn't wake Tvo", isPresented: Binding(
            get: { liveError != nil },
            set: { if !$0 { liveError = nil } }
        )) {
            Button("OK", role: .cancel) { liveError = nil }
        } message: {
            Text(liveError ?? "")
        }
        .onAppear {
            link.onFace = { [animator] face in animator.receive(face, at: Date().timeIntervalSinceReferenceDate) }
            animator.localTalk = { [live] in live.level }
            wireLiveVoice()
            live.onError = { message in liveError = message }
            link.start()
            Task { await updateChecker.checkIfNeeded() }
        }
        .onChange(of: link.connected) { _, connected in
            if connected {
                withAnimation(.easeOut(duration: 0.4)) { showPairing = false }
                NotesSync.retryPending(store: store, link: link)
                store.resyncRecent()
                if !characterColorHex.isEmpty {
                    link.send(Packet(command: "characterColor", text: characterColorHex))
                }
            }
        }
        .onChange(of: characterColorHex) { _, color in
            guard !color.isEmpty else { return }
            link.send(Packet(command: "characterColor", text: color))
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                link.start()
                Task { await updateChecker.checkIfNeeded() }
            } else if phase == .background {
                link.stop()
            }
        }
    }

    struct PhoneAppUpdate: Equatable {
        let version: String
    }

    @MainActor
    final class PhoneUpdateChecker: ObservableObject {
        enum Status: Equatable {
            case idle
            case checking
            case current
            case available
            case noVersionedRelease
            case failed(String)
        }

        @Published private(set) var status: Status = .idle
        @Published private(set) var availableUpdate: PhoneAppUpdate?
        private var lastCheck: Date?

        func checkIfNeeded() async {
            guard lastCheck.map({ Date().timeIntervalSince($0) >= 86_400 }) ?? true else { return }
            await check()
        }

        func check() async {
            guard status != .checking else { return }
            status = .checking
            lastCheck = Date()

            do {
                var request = URLRequest(url: URL(string: "https://api.github.com/repos/TvogInc/Tvo/releases?per_page=20")!)
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                request.setValue("Tvo-iOS", forHTTPHeaderField: "User-Agent")
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
                    throw UpdateCheckError.invalidResponse
                }
                let releases = try JSONDecoder().decode([GitHubRelease].self, from: data)
                guard let release = releases.first(where: {
                    compareVersions($0.tagName, currentVersion) != nil
                }) else {
                    availableUpdate = nil
                    status = .noVersionedRelease
                    return
                }
                guard let comparison = compareVersions(release.tagName, currentVersion) else {
                    status = .noVersionedRelease
                    return
                }
                guard comparison == .orderedDescending else {
                    availableUpdate = nil
                    status = .current
                    return
                }
                availableUpdate = PhoneAppUpdate(version: release.tagName)
                status = .available
            } catch {
                availableUpdate = nil
                status = .failed(error.localizedDescription)
            }
        }

        private var currentVersion: String {
            Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        }

        private func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult? {
            func components(_ version: String) -> [Int]? {
                let value = version.hasPrefix("v") ? String(version.dropFirst()) : version
                let parts = value.split(separator: ".", omittingEmptySubsequences: false)
                guard !parts.isEmpty else { return nil }
                var result: [Int] = []
                for part in parts {
                    guard let component = Int(part) else { return nil }
                    result.append(component)
                }
                return result
            }

            guard let lhsParts = components(lhs), let rhsParts = components(rhs) else { return nil }
            for index in 0..<max(lhsParts.count, rhsParts.count) {
                let lhsPart = index < lhsParts.count ? lhsParts[index] : 0
                let rhsPart = index < rhsParts.count ? rhsParts[index] : 0
                if lhsPart != rhsPart {
                    return lhsPart > rhsPart ? .orderedDescending : .orderedAscending
                }
            }
            return .orderedSame
        }
    }

    private struct GitHubRelease: Decodable {
        let tagName: String

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
        }
    }

    private enum UpdateCheckError: LocalizedError {
        case invalidResponse
        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                "GitHub did not return a valid release response."
            }
        }
    }

    private struct PhoneUpdateBanner: View {
        let update: PhoneAppUpdate
        let showGuide: () -> Void
        let dismiss: () -> Void

        var body: some View {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 20))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tvo update available")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Version \(update.version) · Install with Xcode")
                        .font(.system(size: 12))
                        .opacity(0.75)
                }
                Button("Xcode guide", action: showGuide)
                    .font(.system(size: 13, weight: .semibold))
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                }
                .accessibilityLabel("Dismiss update notice")
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.horizontal, 24)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Press and hold the screen to ask him something; let go and he answers.
    private var holdToAsk: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard holdStart == nil, !holdingToAsk else { return }
                let work = DispatchWorkItem {
                    holdingToAsk = true
                    #if canImport(UIKit)
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    #endif
                    live.beginAsk()
                }
                holdStart = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)  // a quick tap isn't a hold
            }
            .onEnded { _ in
                holdStart?.cancel()
                holdStart = nil
                if holdingToAsk {
                    holdingToAsk = false
                    #if canImport(UIKit)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    #endif
                    live.endAsk()
                }
            }
    }

    /// Connects the live voice to the Mac: keys, tools, captions and wake/sleep.
    private func wireLiveVoice() {
        live.requestToken = { [link] done in
            link.request(Packet(command: "realtimeToken")) { reply in done(reply?.text) }
        }
        live.runTool = { [link] name, arguments, done in
            link.request(Packet(command: "tool", tool: name, text: arguments)) { reply in
                done(reply?.text ?? "The Mac didn't answer.", reply?.image)
            }
        }
        live.onSessionStart = { [store, live] in
            store.start()
            if let id = store.currentID { live.recorder.start(session: id) }
        }
        live.resumeContext = { [store] in store.recentText() }
        live.recorder.onChunk = { [store, link] chunk in
            store.addPending(chunk.sessionID, index: chunk.index, started: chunk.started)
            NotesSync.upload(chunk.sessionID, index: chunk.index, started: chunk.started, store: store, link: link)
        }
        store.onSync = { [store, link] sessions in NotesSync.send(sessions, store: store, link: link) }
        live.onSessionEnd = { [store] in store.end() }
        live.onUserTurn = { [store] item, asked in store.placeholder(itemID: item, asked: asked) }
        live.onUserWords = { [store] item, text, asked in store.heard(itemID: item, text: text, asked: asked) }
        live.onTypedQuestion = { [store] text in store.asked(text) }
        live.onReply = { [store] text in store.reply(text) }
        live.onReport = { [store] text in store.report(text) }
        live.onCaption = { [link] text, finished in
            link.send(Packet(command: finished ? "captionDone" : "caption", text: text))
        }
        live.onStateChange = { [link, animator] state in
            switch state {
            case .asleep:
                animator.awake = false
                animator.localMood = nil
                link.send(Packet(command: "asleep"))
            case .waking:
                animator.awake = true
                animator.localMood = .happy
            case .listening:
                animator.awake = true
                animator.localMood = nil
                link.send(Packet(command: "awake"))
            case .asking:
                animator.awake = true
                animator.localMood = .listening  // all ears while you hold
                link.send(Packet(command: "awake"))
            case .thinking:
                animator.localMood = .thinking
            case .speaking:
                animator.localMood = .talking
            }
        }
        link.onCommand = { [live] command in
            switch command {
            case "wake": live.wake()
            case "sleep": live.sleep()
            case "stop": live.sleep()
            default: break
            }
        }
    }
}

private struct TvoLaunchSplash: View {
    var onFinished: () -> Void
    @State private var revealed = false
    @State private var fading = false

    var body: some View {
        GeometryReader { geometry in
            let logoSize = min(min(geometry.size.width * 0.48, geometry.size.height * 0.74), 300)
            ZStack {
                Color.black
                RadialGradient(
                    colors: [Color(hex: 0x123A76).opacity(0.8), Color(hex: 0x3B0D69).opacity(0.42), .clear],
                    center: .center,
                    startRadius: 12,
                    endRadius: max(geometry.size.width, geometry.size.height) * 0.72
                )
                .opacity(revealed ? 1 : 0)

                VStack(spacing: logoSize * 0.02) {
                    TvoDotLogo()
                        .frame(width: logoSize * 1.6, height: logoSize * 0.62)
                        .opacity(revealed ? 1 : 0)
                        .animation(.easeInOut(duration: 0.6).delay(0.2), value: revealed)

                    TvoBlueberry()
                        .frame(width: logoSize * 0.5, height: logoSize * 0.5)
                        .opacity(revealed ? 1 : 0)
                        .animation(.spring(response: 0.8, dampingFraction: 0.72).delay(0.6), value: revealed)
                }
                .frame(width: logoSize * 1.7, height: logoSize * 0.9)
                .opacity(fading ? 0 : 1)

                VStack {
                    Spacer()
                    Text("A LITTLE MAGIC IS LOADING")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .tracking(3)
                        .foregroundStyle(Color(hex: 0xB9DFFF).opacity(revealed ? 0.86 : 0))
                        .padding(.bottom, max(geometry.safeAreaInsets.bottom, 22))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(fading ? 0 : 1)
            .ignoresSafeArea()
            .onAppear {
                withAnimation(.spring(response: 1.05, dampingFraction: 0.72).delay(0.12)) {
                    revealed = true
                }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(6_000))
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeInOut(duration: 0.35)) { fading = true }
                    try? await Task.sleep(for: .milliseconds(380))
                    guard !Task.isCancelled else { return }
                    onFinished()
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityLabel("Tvo")
    }
}

/// Shows which mode he's in: a solid border hugging the screen's own rounded corners (blue while he listens),
/// plus a small label in the corner. Following your mouse is just a little eye icon. No glows.
struct ModeIndicator: View {
    let state: LiveVoice.State

    private struct Look {
        let color: Color
        let label: String?
        let icon: String
        let border: CGFloat   // 0 = no border
        let pulse: Double     // pulses per second (opacity only)
    }

    private static let blue = Color(hex: 0x4F8BFF)

    private var look: Look {
        switch state {
        case .asleep:    return Look(color: Color(hex: Palette.inkSoft), label: nil, icon: "eye.fill", border: 0, pulse: 0)
        case .waking:    return Look(color: Color(hex: 0xFFD66B), label: "Waking up", icon: "sun.max.fill", border: 6, pulse: 1.6)
        case .listening: return Look(color: Self.blue, label: "Listening · hold to ask", icon: "ear", border: 10, pulse: 0)
        case .asking:    return Look(color: Self.blue, label: "I'm all ears", icon: "mic.fill", border: 16, pulse: 1.2)
        case .thinking:  return Look(color: Color(hex: 0xC79BFF), label: "Thinking", icon: "sparkles", border: 8, pulse: 1.1)
        case .speaking:  return Look(color: Color(hex: 0xFF9AD0), label: "Replying", icon: "bubble.left.fill", border: 8, pulse: 0)
        }
    }

    /// The phone screen's own corner radius, so the border lines up with the glass.
    private static let screenCornerRadius: CGFloat = {
        #if canImport(UIKit)
        if let radius = UIScreen.main.value(forKey: "_displayCornerRadius") as? CGFloat, radius > 0 { return radius }
        #endif
        return 55
    }()

    var body: some View {
        let look = look
        TimelineView(.animation(paused: look.pulse == 0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let wave = look.pulse > 0 ? 0.5 + 0.5 * sin(t * look.pulse * 2 * .pi) : 1
            ZStack(alignment: .topLeading) {
                if look.border > 0 {
                    RoundedRectangle(cornerRadius: Self.screenCornerRadius, style: .continuous)
                        .strokeBorder(look.color, lineWidth: look.border)
                        .opacity(look.pulse > 0 ? 0.65 + 0.35 * wave : 1)
                }
                HStack(spacing: 7) {
                    Image(systemName: look.icon)
                        .font(.system(size: 14, weight: .bold))
                    if let label = look.label {
                        Text(label).font(.fredoka(16))
                    }
                }
                .foregroundStyle(look.label == nil ? look.color.opacity(0.7) : .white)
                .padding(.horizontal, look.label == nil ? 0 : 14)
                .frame(minWidth: 34, minHeight: 34)
                .background(Capsule().fill(look.label == nil ? Color.white.opacity(0.06) : look.color))
                .padding(.top, 14 + look.border)
                .padding(.leading, 24 + look.border)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.25), value: state)
    }
}

private extension View {
    /// Hides the status bar and home indicator and keeps the screen awake.
    func phoneChrome() -> some View {
        #if os(iOS)
        return self
            .statusBarHidden(true)
            .persistentSystemOverlays(.hidden)
            .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        #else
        return self
        #endif
    }
}

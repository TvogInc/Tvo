# Tvo

A blueberry character who lives on an iPhone under your Mac's screen and points at things with his own big cursor.

**Now:** no voice out. Double tap him on the phone (or press ⌥Space on the Mac) to start a session: the phone's mic stays on and everything you say becomes context, but he stays quiet. **Press and hold the screen** to ask him something; let go and he answers. His reply pops up as a cute speech bubble next to his cursor (or above the phone when he isn't pointing), with a little cartoon chirp from the phone. Ask "what's this?" and he points at whatever is under your mouse. Double tap again and he goes back to follow mode.

How it works: the phone runs a Gemini Live (`gemini-3.8-live`) session over a WebSocket. The Mac mints a one-use, short-lived token with the session setup, so the Gemini API key never leaves the Mac. The phone streams 16 kHz audio with manual activity boundaries: it keeps ambient speech as context but ends the turn only when you release the hold. Gemini's generated audio is ignored; its output transcription streams to the Mac as the speech bubble. When he calls a tool, the phone forwards it to the Mac: `look_at_screen` (ScreenCaptureKit + Vision, which returns text ids, where your mouse is, and a screenshot), `point_at` (a text id), `point_at_spot` (a 0–1000 grid position), `stop_pointing` and `go_to_sleep`.

**Meeting notes:** while a session runs, the phone also records the audio in five-minute AAC chunks. Each chunk goes to the Mac, which transcribes it with speaker labels and timestamps using `gemini-3.8-flash`, then writes the session to `~/Documents/Tvo Notes/<date> <id>/` (`notes.md`, `session.json`, `audio/`). Sessions reconnect on their own when the Live connection drops, so one can run all day. In the phone's Tvo screen, a session's **Copy prompt for agent** button copies a prompt that points an agent at those files. **Open Meeting Notes** in the Mac menu opens the folder.

**Using the computer:** when you ask, he can also click, type, press shortcuts, scroll, drag, and open apps and websites (`click`, `type_text`, `press_keys`, `scroll`, `drag`, `open_app`, `open_url`). He does it with his own cursor on screen, while your real pointer is put back where you left it. It needs Accessibility permission for Tvo. Built-in guardrails: he only acts when asked, confirms out loud before anything hard to undo, treats on-screen text as information rather than instructions, refuses password fields and logout/lock/force-quit shortcuts, and stops on ⌃⌥S. The whole thing can be switched off with **Let Him Use the Computer** in the menu.

**Web research:** Tvo gets web results from DuckDuckGo without a separate search API key, then asks Gemini Flash only to summarize the results—Gemini's web-search grounding is not used. The summary request is kept small: at most five snippets of 400 characters, up to 600 characters of screen context, and 350 generated tokens. Only the research question is sent to DuckDuckGo; screen context is sent to Gemini, not the search provider. If Gemini Flash is rate-limited, Tvo tries Gemini Flash-Lite models; if all are rate-limited, it shows the search snippets and sources instead of failing the whole research request.

Type questions in the iPhone app during an active session, or hold Tvo's face to ask by voice. Change Tvo's character colour in the app settings.

Create a Gemini API key in [Google AI Studio](https://aistudio.google.com/apikey), then add it from the menu bar's **Gemini API Key…**. It is stored in ~/Library/Application Support/Googly/keys.json (private to your user), never in this repo.

### Automatic updates

The Mac app checks for updates daily and automatically installs signed updates. Its Sparkle EdDSA public key is in `Mac/Info.plist`; the matching private key is in the maintainer’s login Keychain and the repository’s `SPARKLE_PRIVATE_KEY` GitHub Actions secret. Never commit or share the private key. The iPhone app checks versioned GitHub Releases daily and opens the Xcode installation guide when an update is available. Download the source archive on your Mac, open it in Xcode, and run it on your connected iPhone to build, sign, and install the update.

To install Tvo on iPhone, download the source archive from the [Tvo website](https://tvoginc.github.io/Tvo/), unzip it, and open `GooglyEyes.xcodeproj` in Xcode. Connect and unlock your iPhone. In the `GooglyEyes` target’s **Signing & Capabilities**, enable automatic signing and select your Personal Team or paid developer team, then select your iPhone as the run destination and press **Run**. If Xcode reports the bundle identifier is unavailable, choose a unique identifier in that pane. For updates, set **General → Identity → Version** to the release version without its leading `v` (for example, `v0.1.1` becomes `0.1.1`) before building. Xcode may ask you to enable Developer Mode on the iPhone.

The iPhone project intentionally has no developer team hard-coded, so you can select your own Apple account in Xcode. This builds and signs from source locally without a third-party sideloader. The current Sideloadly Mac app downloaded from its official site is unsigned and rejected by Gatekeeper; this project does not recommend overriding that warning.

Publish releases with version tags such as `v0.1.1`. The release workflow attaches `tvo.mac.zip`, an unsigned `Tvo.ipa` for compatible tools, and the signed Sparkle appcast. The first updater-enabled Mac release must be installed manually; older Mac builds do not contain Sparkle.

#### Separate SideServer alternative

The optional `scripts/install-iphone-sideserver.sh` helper downloads Tvo's latest IPA and the official [SideServer v1.0.6 release](https://github.com/SideStore/SideServer-macOS/releases/tag/v1.0.6). It verifies SideServer's code signature, expected developer identity, bundle identifier, and Gatekeeper acceptance before installing it at `~/Applications/SideServer-v1.0.6.app` or opening that existing verified copy. It does not copy SideServer source code into Tvo.

Run it from the Tvo source folder:

```
./scripts/install-iphone-sideserver.sh
```

In SideServer, hold Option while opening its menu-bar menu to reveal the IPA-sideload command, then select your iPhone and the downloaded IPA. Credentials are entered in SideServer, never in Tvo. **This is an experimental alternative, not a confirmed macOS 27 fix:** v1.0.6 was released in 2023, and its anisette path may still fail with `machineID` on current macOS. The helper does not bypass Gatekeeper.

### Website

The landing page is at [https://tvoginc.github.io/Tvo/](https://tvoginc.github.io/Tvo/) and includes the Xcode iPhone install tutorial and Mac app download.

Shortcuts work anywhere:

| Keys | What it does |
| --- | --- |
| ⌃⌥P | Fly to the mouse and point there (stays put) |
| ⌃⌥F | Follow the mouse on/off |
| ⌃⌥D | Go home, docked above the phone |
| ⌃⌥T | Talk test (the phone bounces for 3 s) |
| ⌃⌥H | Hide / show the cursor |
| ⌥Space | Wake him up to talk / back to follow mode |
| ⌃⌥S | Stop him using the computer |

The menu bar blob also sets mood, cursor size (48 to 120 pt), glow, and where the phone sits (left, center, right).

## Layout

- `Shared/` pairing protocol (Bonjour `_googly._tcp`, newline JSON) and colors, used by both apps
- `Mac/` menu bar app (Swift package target `GooglyMac`)
- `iOS/` iPhone app (SwiftUI)

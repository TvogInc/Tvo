# Tvo

A blueberry character who lives on an iPhone under your Mac's screen and points at things with his own big cursor.

**Now:** no voice out. Double tap him on the phone (or press ⌥Space on the Mac) to start a session: the phone's mic stays on and everything you say becomes context, but he stays quiet. **Press and hold the screen** to ask him something; let go and he answers. His reply pops up as a cute speech bubble next to his cursor (or above the phone when he isn't pointing), with a little cartoon chirp from the phone. Ask "what's this?" and he points at whatever is under your mouse. Double tap again and he goes back to follow mode.

How it works: the phone runs a Gemini Live (`gemini-3.8-live`) session over a WebSocket. The Mac mints a one-use, short-lived token with the session setup, so the Gemini API key never leaves the Mac. The phone streams 16 kHz audio with manual activity boundaries: it keeps ambient speech as context but ends the turn only when you release the hold. Gemini's generated audio is ignored; its output transcription streams to the Mac as the speech bubble. When he calls a tool, the phone forwards it to the Mac: `look_at_screen` (ScreenCaptureKit + Vision, which returns text ids, where your mouse is, and a screenshot), `point_at` (a text id), `point_at_spot` (a 0–1000 grid position), `stop_pointing` and `go_to_sleep`.

**Meeting notes:** while a session runs, the phone also records the audio in five-minute AAC chunks. Each chunk goes to the Mac, which transcribes it with speaker labels and timestamps using `gemini-3.8-flash`, then writes the session to `~/Documents/Tvo Notes/<date> <id>/` (`notes.md`, `session.json`, `audio/`). Sessions reconnect on their own when the Live connection drops, so one can run all day. In the phone's Tvo screen, a session's **Copy prompt for agent** button copies a prompt that points an agent at those files. **Open Meeting Notes** in the Mac menu opens the folder.

**Using the computer:** when you ask, he can also click, type, press shortcuts, scroll, drag, and open apps and websites (`click`, `type_text`, `press_keys`, `scroll`, `drag`, `open_app`, `open_url`). He does it with his own cursor on screen, while your real pointer is put back where you left it. It needs Accessibility permission for Tvo. Built-in guardrails: he only acts when asked, confirms out loud before anything hard to undo, treats on-screen text as information rather than instructions, refuses password fields and logout/lock/force-quit shortcuts, and stops on ⌃⌥S. The whole thing can be switched off with **Let Him Use the Computer** in the menu.

**Web research:** Tvo gets web results from DuckDuckGo without a separate search API key, then asks Gemini Flash only to summarize the results—Gemini's web-search grounding is not used. The summary request is kept small: at most five snippets of 400 characters, up to 600 characters of screen context, and 350 generated tokens. Only the research question is sent to DuckDuckGo; screen context is sent to Gemini, not the search provider. If Gemini Flash is rate-limited, Tvo tries Gemini Flash-Lite models; if all are rate-limited, it shows the search snippets and sources instead of failing the whole research request.

Type questions in the iPhone app during an active session, or hold Tvo's face to ask by voice. Change Tvo's character colour in the app settings.

Create a Gemini API key in [Google AI Studio](https://aistudio.google.com/apikey), then add it from the menu bar's **Gemini API Key…**. It is stored in ~/Library/Application Support/Googly/keys.json (private to your user), never in this repo.

## Installing Tvo

```
./scripts/build.sh
open "build/Tvo.app"
```

The script builds the macOS app at `build/Tvo.app` using Swift already available on the Mac. It does not install Xcode or other dependencies.

To hand a prebuilt iPhone IPA to Sideloadly, pass its path:

```
./scripts/build.sh path/to/Tvo.ipa
```

Or run `scripts/install-iphone.sh path/to/Tvo.ipa` after building the Mac app. Sideloadly must already be installed; the script opens it and selects the IPA in Finder so you can drag it into Sideloadly, choose the iPhone, and complete signing there. Tvo does not collect Apple ID credentials. The local build script does not create an iPhone IPA; creating one from source requires an iOS SDK, which is not included with the macOS Command Line Tools. The GitHub Actions workflow below builds the IPA remotely. Sideloadly advertises macOS 10.12+ and iOS 27+ support, but this workflow has not been tested on macOS 27.

### Build and install the iPhone app without Xcode on your Mac

The GitHub Actions workflow builds an **unsigned** iPhone IPA on a GitHub-hosted macOS runner. Your Mac does not need Xcode. The iPhone app still needs to be signed for your Apple ID before installation; Sideloadly handles that on your Mac.

1. Push this project, including `.github/workflows/build-iphone-ipa.yml`, to a GitHub repository with Actions enabled.
2. On GitHub, open **Actions** → **Build iPhone IPA** → **Run workflow**. Wait for the run to finish.
3. Open the completed workflow run, download the `Tvo-unsigned-ipa` artifact, and unzip it to get `Tvo.ipa`.
4. Install and open [Sideloadly](https://sideloadly.io/) on your Mac. Connect your iPhone by USB, unlock it, and trust the Mac if prompted.
5. Drag `Tvo.ipa` into Sideloadly, select your iPhone, enter your Apple ID in Sideloadly, and click **Start**. Complete any verification prompts with Apple/Sideloadly. Tvo itself does not receive or store your Apple ID password.
6. If prompted, enable Developer Mode on the iPhone in **Settings** → **Privacy & Security** → **Developer Mode**, then trust the developer profile in **Settings** → **General** → **VPN & Device Management**.

To publish an IPA with a GitHub release, push a version tag such as `v0.1.0`. The workflow builds the same IPA and attaches `Tvo.ipa` to that release. Each IPA is unsigned and must be sideloaded with Sideloadly; this workflow does not install Xcode on your Mac or install the app directly onto the phone.

### Website

The static landing page is `index.html` with `site.css` and `site.js`. Publish the repository root with GitHub Pages to host it without a separate build step. The download button automatically links to the latest `Tvo.ipa` GitHub release when hosted at `owner.github.io/repository/`. For a custom domain or another host, set the `github-repository` meta tag in `index.html` to `owner/repository`.

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

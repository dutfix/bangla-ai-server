# Omni

A ChatGPT / Claude-style AI chat app in Flutter, with no login. Chat by text with streaming Markdown replies, dictate with the mic, or open hands-free voice mode and talk. Answers come from your OmniRoute API key; the voices are free (on-device Kokoro / Piper, the phone's own voices, or Microsoft Edge online voices).

It uses Flutter 3.50 stable and Dart 3.14 with Material 3 (the `material_ui` package). Android comes first, but the code also works on iOS.

The look follows the **FLARECAP "Sky & Ink"** design system: every colour, type size, radius, spacing value and motion timing lives in `lib/theme/` (`tokens.dart` + `app_theme.dart`), with light and dark themes. Fonts (DM Sans, Anton, DM Mono) and Heroicons v2 outline icons are bundled, so nothing is fetched at runtime.

## What's in it

- **Chat**: streaming replies, Markdown (headings, lists, tables, links, quotes) and code blocks with syntax colours and a Copy button. Stop generating at any time.
- **Message actions**: copy, read aloud with your call voice, regenerate the last reply, and edit-and-resend your own messages.
- **History sidebar** (drawer on phones, fixed panel on tablets): new chat, chats grouped by day, search across titles and message text, rename, delete. Chats are saved only on the phone (`chats.json` in app storage). Titles are written by the AI after the first reply.
- **Composer**: mic dictation (phone recognizer), and a round button that sends, stops, or starts a voice call when the box is empty.
- **Voice mode**: full screen with the animated action orb and a live waveform, captions, Interrupt and Hang up. Every call turn is written into the open chat, marked "Voice call".
- **Model picker** at the top: an editable list (default `auto`, plus `auto/fast`), and an optional system prompt in Settings.
- **Settings** (connection, model, custom instructions, call voice and speed, light/dark/system theme, delete all chats) and **Voices** (all three voice groups plus the "Find more voices" AI agent).

## Run it

```bash
flutter pub get
flutter run            # with an Android phone plugged in (USB debugging on)
```

To build an installable APK:

```bash
flutter build apk --release --split-per-abi
# -> build/app/outputs/flutter-apk/app-arm64-v8a-release.apk (most phones)
```

The release build is signed with the debug key so you can test it. Before you publish it on Google Play, set up your own signing key.

## Add your OmniRoute key

Open the side menu (top left), then **Settings**:

- **OmniRoute API key**: paste your key. It's stored encrypted on the phone (Android Keystore / iOS Keychain) and only sent to your base URL.
- **Base URL**: OmniRoute is OpenAI-compatible and listens on port 20128 at `/v1`.
  - If OmniRoute runs on your computer, enter `http://<your-computer's-LAN-IP>:20128/v1`, for example `http://192.168.1.100:20128/v1`. The phone has to be on the same Wi-Fi. `localhost` won't work, because on a phone it means the phone itself.
  - If you use a cloud or tunnel URL, paste that and keep `/v1` on the end.
- Tap **Test connection**. You should see the model reply "Connection works."
- **Model**: tap the model name at the top of the chat. `auto` lets OmniRoute pick; `auto/fast` gives quicker replies, which is good for calls. Add any of your own combo or model names there, or remove ones you don't use.

The app works with any OpenAI-compatible `/chat/completions` endpoint, so you can use another provider by changing the base URL and model. Replies stream in, and each sentence is spoken as soon as it's complete, so the AI starts talking quickly.

## Voices (all free)

Open the **Voices** screen (the person icon on the call screen). Every voice has **Test** and **Set as call voice**. Voices that run on the phone also have **Download** (with progress), **Cancel** and **Delete**.

1. **On-device (Kokoro / Piper)** works offline and keeps everything private. It's powered by sherpa-onnx.
   - **Kokoro**: 11 voices (American and British, female and male) with the best quality. They share one pack of about 103 MB, so one download unlocks all 11.
   - **Piper**: 10 English voices of about 21 MB each. They're fast even on cheap phones.
   - **Find more voices (AI)**: an agent that runs on your OmniRoute key. It reads the full list of free sherpa-onnx Piper voices on GitHub (183 voices in 48 language and region variants), and the AI picks the ones that match what you type, for example "Spanish female voices". Each pick is checked against the real list, so the AI can't invent a voice or a link. Found voices get the same Download, Test, Delete and Set buttons, plus Remove.
   - Voices download from the official sherpa-onnx GitHub release the first time you use them, so the app itself stays small.
2. **Phone built-in (Google / Samsung / etc.)** lists every voice from every text-to-speech engine on the phone, with an **Engine** switch on Android (Speech Services by Google, Samsung TTS and so on). On iOS you get the system, Enhanced and Premium voices. **Get more phone voices** opens the phone's text-to-speech settings so you can install more.
3. **Online free (Microsoft Edge)** gives you about 320 Microsoft neural voices in many languages. They're called straight from Dart with no API key, using the same service the `edge-tts` project uses. **This needs internet. It's unofficial and could stop working at any time** if Microsoft changes the service.

You set the speaking speed in Settings.

## Speech-to-text

The app listens with the **phone's built-in speech recognizer** through the `speech_to_text` plugin: Google on Android, Apple on iOS. It's free, needs no key, and is simpler and more reliable than putting a separate recognition model in the app. On many phones it also works offline once the offline language is installed (in the Google app or Speech Services settings on Android).

## Android permissions

These are already in `android/app/src/main/AndroidManifest.xml`:

- `INTERNET`: AI requests, voice downloads and Microsoft voices.
- `RECORD_AUDIO`: hearing you. The app asks for it the first time you call.
- `<queries>` for `RecognitionService` and `TTS_SERVICE`: lets the app see the speech recognizer and the TTS engines on Android 11 and later.
- `usesCleartextTraffic="true"`: lets the app reach OmniRoute over plain `http://` on your Wi-Fi.

minSdk is 24 (Android 7.0).

## iOS

`Info.plist` already has the microphone and speech recognition messages, plus permission to use plain HTTP on your local network. Run `flutter run` on a Mac with Xcode. If CocoaPods complains about the iOS version, set `platform :ios, '13.0'` in `ios/Podfile`.

## How a call works

Listen (it stops after about 2 seconds of silence), then send the text to OmniRoute and stream the reply. Each sentence becomes audio on the phone while the previous one is playing. When the reply is done, it listens again.

- **Interrupt** cuts the AI off mid-sentence and goes straight back to listening.
- **Hang up** stops everything.
- In calls the AI is told to keep its answers short and spoken; your own system prompt from Settings is added after that. The call continues the open chat, and the last 20 messages are kept as context.
- Tap the orb while it thinks or speaks to interrupt, too.

## Code map

```
lib/
  main.dart                    app, light/dark theme switch
  app_services.dart            creates the long-lived services
  theme/
    tokens.dart                Sky & Ink tokens: palette, gradients, radii,
                               spacing, sizes, layout, motion, fonts
    app_theme.dart             Material 3 colour schemes, type scale, ThemeData
    hero_icons.dart            Heroicons v2 renderer (+ generated data file)
  widgets/
    components.dart            buttons, chips, cards, rows, page title, sheets
    markdown_view.dart         Markdown + code blocks with copy
    message_tile.dart          one message with its actions
    composer.dart              message box, dictation, send/stop/voice button
    sidebar.dart               chat history
    model_sheet.dart           model picker
    voice_orb.dart             action orb and waveform
  models/chat.dart, voice.dart
  services/
    chat_controller.dart       send, stream, stop, regenerate, edit, titles
    chat_store.dart            saved chats (JSON file on the phone)
    read_aloud.dart            read one message with the call voice
    call_controller.dart       the listen -> think -> speak loop
    llm_client.dart            OpenAI-compatible streaming client (OmniRoute)
    listener.dart              speech-to-text (phone recognizer)
    speaker.dart               plays voices sentence by sentence (all engines)
    sherpa_worker.dart         Kokoro/Piper running in a background isolate
    voice_downloads.dart       download / unpack / delete voice packs
    voice_catalog.dart         the built-in Kokoro and Piper voice list
    voice_finder.dart          "Find more voices" AI agent
    system_voices.dart         phone TTS engines and voices
    edge_tts.dart              Microsoft Edge online voices (+ its token)
    settings_store.dart        key (secure storage) + settings
    text_utils.dart            sentence splitter, markdown cleanup
  screens/
    chat_screen.dart, voice_mode_screen.dart, settings_screen.dart,
    voices_screen.dart, find_voices_sheet.dart
test/                          chat logic, storage, theme and widget tests
assets/fonts, assets/licenses  bundled fonts (SIL OFL) and Heroicons (MIT)
```

## Known limits

- **sherpa_onnx is pinned to 1.13.8 on purpose.** Version 2.0 removed espeak-ng. In testing, 2.0.1 skipped every word missing from its English word list, so names, numbers and new words went silent, and other languages had no word list at all. 1.13.8 reads any word in any language its voices support. Upgrade only once 2.x fixes this.
- **No voice barge-in.** While the AI talks, you interrupt with the button, not by speaking, because without echo cancellation the mic would hear the AI's own voice. Speaker-phone use works best with this approach.
- **Kokoro on older phones** can take a moment for each sentence. If it lags, pick a Piper voice.
- The **AI finder adds Piper voices only**, because those are the voices that are sure to run offline with this setup. The Kokoro list is English (v0.19).
- **Microsoft Edge voices** need internet and may break without warning (unofficial).
- **Phone voices** depend on the phone. Some engines only show voices after you install their voice data. Network-only Google voices need internet.
- The phone recognizer sometimes stops in very noisy places. If it hears nothing, the app just keeps listening.
- GitHub allows 60 anonymous API calls an hour. The finder caches the voice list for a day, so this rarely matters.
- Your API key is only as safe as the phone it's stored on. Don't share builds that have a key filled in.
- Chats live only on this phone. Uninstalling the app deletes them.

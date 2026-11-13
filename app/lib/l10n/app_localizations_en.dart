// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'Bangla AI';

  @override
  String get appNameLatin => 'BANGLA AI';

  @override
  String get appTagline => 'Chat and talk in Bangla';

  @override
  String get cancel => 'Cancel';

  @override
  String get delete => 'Delete';

  @override
  String get rename => 'Rename';

  @override
  String get save => 'Save';

  @override
  String get saved => 'Saved';

  @override
  String get ok => 'OK';

  @override
  String get retry => 'Retry';

  @override
  String get done => 'Done';

  @override
  String get back => 'Back';

  @override
  String get clear => 'Clear';

  @override
  String get send => 'Send';

  @override
  String get stop => 'Stop';

  @override
  String get test => 'Test';

  @override
  String get copy => 'Copy';

  @override
  String get copied => 'Copied';

  @override
  String get tryAgain => 'Try again';

  @override
  String get newChat => 'New chat';

  @override
  String get needApiKey => 'Add your OmniRoute API key in Settings first.';

  @override
  String couldNotReadAloud(String error) {
    return 'Could not read aloud: $error';
  }

  @override
  String couldNotOpen(String link) {
    return 'Could not open $link';
  }

  @override
  String get code => 'code';

  @override
  String get groupToday => 'Today';

  @override
  String get groupYesterday => 'Yesterday';

  @override
  String get groupPrevious7 => 'Previous 7 days';

  @override
  String get groupPrevious30 => 'Previous 30 days';

  @override
  String get monthNames =>
      'January,February,March,April,May,June,July,August,September,October,November,December';

  @override
  String get renameChat => 'Rename chat';

  @override
  String get deleteChatTitle => 'Delete chat?';

  @override
  String deleteChatBody(String title) {
    return '\"$title\" will be deleted from this phone.';
  }

  @override
  String get voices => 'Voices';

  @override
  String get settings => 'Settings';

  @override
  String get searchChats => 'Search chats';

  @override
  String get noChatsYet => 'No chats yet';

  @override
  String get noMatches => 'No matches';

  @override
  String get chatsSavedHere => 'Your chats are saved on this phone.';

  @override
  String nothingMatches(String query) {
    return 'Nothing in your chats matches \"$query\".';
  }

  @override
  String get results => 'Results';

  @override
  String get chatOptions => 'Chat options';

  @override
  String get jumpToLatest => 'Jump to latest';

  @override
  String get chats => 'Chats';

  @override
  String get suggestExplain => 'Explain something';

  @override
  String get suggestExplainPrompt => 'Explain how ';

  @override
  String get suggestCode => 'Write code';

  @override
  String get suggestCodePrompt => 'Write a function that ';

  @override
  String get suggestSummarize => 'Summarize text';

  @override
  String get suggestSummarizePrompt => 'Summarize this:\n\n';

  @override
  String get suggestBrainstorm => 'Brainstorm';

  @override
  String get suggestBrainstormPrompt => 'Give me 10 ideas for ';

  @override
  String get howCanIHelp => 'HOW CAN I HELP?';

  @override
  String get emptyChatSub =>
      'Type a message, or talk hands-free in a voice call.';

  @override
  String get emptyChatSubText => 'Type anything you want to know.';

  @override
  String get connectOmniRoute => 'Connect OmniRoute';

  @override
  String get connectOmniRouteSub =>
      'Add your API key and server to start chatting';

  @override
  String get startVoiceCall => 'Start a voice call';

  @override
  String get startVoiceCallSub =>
      'Talk hands-free. Replies are read in your call voice.';

  @override
  String get voiceCall => 'Voice call';

  @override
  String get editAndResend => 'Edit and resend';

  @override
  String get interrupted => 'Interrupted';

  @override
  String get stopped => 'Stopped';

  @override
  String get stopReading => 'Stop reading';

  @override
  String get readAloud => 'Read aloud';

  @override
  String get regenerate => 'Regenerate';

  @override
  String get thinking => 'Thinking';

  @override
  String get messageHint => 'Message Bangla AI';

  @override
  String get stopGenerating => 'Stop generating';

  @override
  String get emptyReply => 'The AI sent an empty reply. Try again.';

  @override
  String connectedReply(String model, String reply) {
    return 'Connected. $model replied: \"$reply\"';
  }

  @override
  String get themeSystem => 'System';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get aiConnection => 'AI connection';

  @override
  String get aiConnectionHelp =>
      'OmniRoute or any OpenAI-compatible server. If OmniRoute runs on your computer, use http://<computer-ip>:20128/v1 with the phone on the same Wi-Fi, or your OmniRoute cloud or tunnel address.';

  @override
  String get apiKeyLabel => 'OmniRoute API key';

  @override
  String get apiKeyHelper => 'Stored encrypted on this phone.';

  @override
  String get hideKey => 'Hide key';

  @override
  String get showKey => 'Show key';

  @override
  String get serverAddress => 'Server address';

  @override
  String get testing => 'Testing...';

  @override
  String get testConnection => 'Test connection';

  @override
  String get model => 'Model';

  @override
  String modelsInList(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return '$countString in your list';
  }

  @override
  String get customInstructions => 'Custom instructions';

  @override
  String get systemPromptLabel => 'System prompt (optional)';

  @override
  String get systemPromptHint =>
      'For example: You are a patient tutor. Keep answers short.';

  @override
  String get systemPromptHelper =>
      'Sent with every chat and call, together with the instruction to reply in the app language. Calls also ask for short, spoken replies.';

  @override
  String get voice => 'Voice';

  @override
  String get callVoice => 'Call voice';

  @override
  String get callVoiceSub => 'Used in calls and for Read aloud';

  @override
  String get speakingSpeed => 'Speaking speed';

  @override
  String get language => 'Language';

  @override
  String get languageSub => 'App text, AI replies and speech recognition';

  @override
  String get appearance => 'Appearance';

  @override
  String get deleteAllChats => 'Delete all chats';

  @override
  String get deleteAllChatsSub => 'Chats are saved only on this phone';

  @override
  String get deleteAllChatsTitle => 'Delete all chats?';

  @override
  String get deleteAllChatsBody =>
      'Every saved chat on this phone will be deleted. This cannot be undone.';

  @override
  String get deleteAll => 'Delete all';

  @override
  String get allChatsDeleted => 'All chats deleted';

  @override
  String get about => 'About';

  @override
  String aboutVersion(String version) {
    return 'Version $version';
  }

  @override
  String get aboutSpeech =>
      'Speech recognition uses your phone\'s built-in recognizer (free) and listens in the app language: Bangla (bn-BD) by default. For offline recognition on Android, install the offline language in the Google app or Speech Services settings.';

  @override
  String testFailed(String error) {
    return 'Test failed: $error';
  }

  @override
  String nowCallVoice(String name) {
    return '$name is now the call voice';
  }

  @override
  String get callVoicePill => 'CALL VOICE';

  @override
  String get setAsCallVoice => 'Set as call voice';

  @override
  String get genderFemale => 'female';

  @override
  String get genderMale => 'male';

  @override
  String get langBanglaBangladesh => 'Bangla (Bangladesh)';

  @override
  String get langBanglaIndia => 'Bangla (India)';

  @override
  String get voicesIntro =>
      'Free Bangla voices from Speech Services by Google, built into your phone. They read the AI replies in calls and Read aloud.';

  @override
  String voiceNumbered(String number) {
    return 'Voice $number';
  }

  @override
  String get voiceOfflineTag => 'works offline';

  @override
  String get voiceNetworkTag => 'needs internet';

  @override
  String get voiceDefaultTag => 'default';

  @override
  String get selected => 'Selected';

  @override
  String get select => 'Select';

  @override
  String get play => 'Play';

  @override
  String get pitch => 'Pitch';

  @override
  String speedValue(String value) {
    return '${value}x';
  }

  @override
  String get loadingVoices => 'Looking for Bangla voices...';

  @override
  String get noBanglaVoicesTitle => 'No Bangla voice found';

  @override
  String get refreshVoices => 'Check again';

  @override
  String voiceTestSample(String name) {
    return 'Hi! This is $name. Does this voice sound good for our calls?';
  }

  @override
  String get setupNoGoogleTitle => 'Install Google\'s voice';

  @override
  String get setupNoGoogleBody =>
      'To hear replies in Bangla, install the free \"Speech Services by Google\" app from the Play Store, then come back.';

  @override
  String get setupNoGoogleButton => 'Open Play Store';

  @override
  String get setupNoBanglaTitle => 'Install the Bangla voice';

  @override
  String get setupNoBanglaBody =>
      'Google\'s Bangla voice is not on this phone yet. Tap below, choose Bangla (Bangladesh) and download it. It is free and works offline afterwards.';

  @override
  String get setupNoBanglaButton => 'Install Bangla voice';

  @override
  String get setupLater => 'Later';

  @override
  String get setupCouldNotOpen =>
      'Could not open the settings. Open Settings > Accessibility > Text-to-speech on your phone.';

  @override
  String get voiceUnavailableIos =>
      'Bangla voices come from your phone\'s speech settings.';

  @override
  String get callEnded => 'Call ended';

  @override
  String get connecting => 'Connecting...';

  @override
  String get listening => 'Listening';

  @override
  String get speakNow => 'speak now';

  @override
  String get tapToInterrupt => 'tap to interrupt';

  @override
  String get speaking => 'Speaking';

  @override
  String get somethingWentWrong => 'Something went wrong';

  @override
  String get voiceModeTitle => 'Voice';

  @override
  String get closeVoiceMode => 'Close voice mode';

  @override
  String get interrupt => 'Interrupt';

  @override
  String get callAgain => 'Call again';

  @override
  String get hangUp => 'Hang up';

  @override
  String get hideText => 'Hide text';

  @override
  String get showText => 'Show text';

  @override
  String get startTalkingHint =>
      'Start talking. I stop listening after a short pause.';

  @override
  String get callSavedInChat => 'Your call is saved in the chat.';

  @override
  String get youLabel => 'YOU';

  @override
  String get aiLabel => 'BANGLA AI';

  @override
  String voiceError(String error) {
    return 'Voice error: $error';
  }

  @override
  String get voiceOff =>
      'Voice is off for now. The admin will turn it on soon.';

  @override
  String get micPermission => 'Microphone permission is needed for calls.';

  @override
  String get speechUnavailable =>
      'Speech recognition is not available. Allow the microphone and make sure Google speech services (Android) are installed.';

  @override
  String get modelAutoDesc => 'Picks the best model for each message';

  @override
  String get modelAutoFastDesc => 'Picks a lighter model for faster replies';

  @override
  String get resetList => 'Reset list';

  @override
  String get modelSheetHelp =>
      'OmniRoute model IDs. Your choice applies to new replies and voice calls.';

  @override
  String get addModelHint => 'Add a model, e.g. openai/gpt-4o';

  @override
  String get addModel => 'Add model';

  @override
  String removeModel(String model) {
    return 'Remove $model';
  }

  @override
  String apiKeyRejected(int code) {
    final intl.NumberFormat codeNumberFormat = intl.NumberFormat.decimalPattern(
      localeName,
    );
    final String codeString = codeNumberFormat.format(code);

    return 'API key rejected ($codeString). Check your OmniRoute key.';
  }

  @override
  String get notFound404 =>
      'Not found (404). Check that the base URL ends with /v1 and the model name is right.';

  @override
  String aiRequestFailed(int code, String detail) {
    final intl.NumberFormat codeNumberFormat = intl.NumberFormat.decimalPattern(
      localeName,
    );
    final String codeString = codeNumberFormat.format(code);

    return 'AI request failed ($codeString): $detail';
  }

  @override
  String get unexpectedResponse => 'The AI returned an unexpected response.';

  @override
  String get timeoutError =>
      'The server took too long to answer. Check the address and your connection.';

  @override
  String get serverUnreachable =>
      'Can\'t reach the Bangla AI server. Check your internet and try again.';

  @override
  String get serverWaking =>
      'Server is waking up. This can take up to a minute...';

  @override
  String get serverOffline => 'Offline: can\'t reach the server right now.';

  @override
  String get appDisabled =>
      'The app is paused for now. Please try again later.';

  @override
  String get serverNotReady =>
      'The server isn\'t set up yet. Please try again later.';

  @override
  String get tooManyRequests =>
      'Too many requests right now. Wait a moment and try again.';

  @override
  String get modelSheetHelpServer =>
      'Models offered by Bangla AI. Your choice applies to new replies and voice calls.';

  @override
  String get defaultTag => 'default';

  @override
  String get useDefaultVoice => 'Use default voice';

  @override
  String get useDefaultVoiceSub => 'Voice, speed and pitch set by Bangla AI';

  @override
  String get phoneBestVoice => 'Best Bangla voice on this phone';

  @override
  String get retryNow => 'Try now';

  @override
  String get callStartHint =>
      'Start talking. I stop listening after a short pause.';

  @override
  String get callSavedHint => 'Your call is saved in the chat.';

  @override
  String get assistantLabel => 'BANGLA AI';

  @override
  String get modelAuto => 'Auto';

  @override
  String get modelFast => 'Fast';
}

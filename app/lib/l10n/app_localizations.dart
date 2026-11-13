import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart' show GlobalMaterialLocalizations;
import 'package:intl/intl.dart' as intl;

import 'app_localizations_bn.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        ...GlobalMaterialLocalizations.delegates,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('bn'),
    Locale('en'),
  ];

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'Bangla AI'**
  String get appName;

  /// No description provided for @appNameLatin.
  ///
  /// In en, this message translates to:
  /// **'BANGLA AI'**
  String get appNameLatin;

  /// No description provided for @appTagline.
  ///
  /// In en, this message translates to:
  /// **'Chat and talk in Bangla'**
  String get appTagline;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @rename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get rename;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @saved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get saved;

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @send.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get send;

  /// No description provided for @stop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get stop;

  /// No description provided for @test.
  ///
  /// In en, this message translates to:
  /// **'Test'**
  String get test;

  /// No description provided for @copy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copy;

  /// No description provided for @copied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get copied;

  /// No description provided for @tryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get tryAgain;

  /// No description provided for @newChat.
  ///
  /// In en, this message translates to:
  /// **'New chat'**
  String get newChat;

  /// No description provided for @needApiKey.
  ///
  /// In en, this message translates to:
  /// **'Add your OmniRoute API key in Settings first.'**
  String get needApiKey;

  /// No description provided for @couldNotReadAloud.
  ///
  /// In en, this message translates to:
  /// **'Could not read aloud: {error}'**
  String couldNotReadAloud(String error);

  /// No description provided for @couldNotOpen.
  ///
  /// In en, this message translates to:
  /// **'Could not open {link}'**
  String couldNotOpen(String link);

  /// No description provided for @code.
  ///
  /// In en, this message translates to:
  /// **'code'**
  String get code;

  /// No description provided for @groupToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get groupToday;

  /// No description provided for @groupYesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get groupYesterday;

  /// No description provided for @groupPrevious7.
  ///
  /// In en, this message translates to:
  /// **'Previous 7 days'**
  String get groupPrevious7;

  /// No description provided for @groupPrevious30.
  ///
  /// In en, this message translates to:
  /// **'Previous 30 days'**
  String get groupPrevious30;

  /// No description provided for @monthNames.
  ///
  /// In en, this message translates to:
  /// **'January,February,March,April,May,June,July,August,September,October,November,December'**
  String get monthNames;

  /// No description provided for @renameChat.
  ///
  /// In en, this message translates to:
  /// **'Rename chat'**
  String get renameChat;

  /// No description provided for @deleteChatTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete chat?'**
  String get deleteChatTitle;

  /// No description provided for @deleteChatBody.
  ///
  /// In en, this message translates to:
  /// **'\"{title}\" will be deleted from this phone.'**
  String deleteChatBody(String title);

  /// No description provided for @voices.
  ///
  /// In en, this message translates to:
  /// **'Voices'**
  String get voices;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @searchChats.
  ///
  /// In en, this message translates to:
  /// **'Search chats'**
  String get searchChats;

  /// No description provided for @noChatsYet.
  ///
  /// In en, this message translates to:
  /// **'No chats yet'**
  String get noChatsYet;

  /// No description provided for @noMatches.
  ///
  /// In en, this message translates to:
  /// **'No matches'**
  String get noMatches;

  /// No description provided for @chatsSavedHere.
  ///
  /// In en, this message translates to:
  /// **'Your chats are saved on this phone.'**
  String get chatsSavedHere;

  /// No description provided for @nothingMatches.
  ///
  /// In en, this message translates to:
  /// **'Nothing in your chats matches \"{query}\".'**
  String nothingMatches(String query);

  /// No description provided for @results.
  ///
  /// In en, this message translates to:
  /// **'Results'**
  String get results;

  /// No description provided for @chatOptions.
  ///
  /// In en, this message translates to:
  /// **'Chat options'**
  String get chatOptions;

  /// No description provided for @jumpToLatest.
  ///
  /// In en, this message translates to:
  /// **'Jump to latest'**
  String get jumpToLatest;

  /// No description provided for @chats.
  ///
  /// In en, this message translates to:
  /// **'Chats'**
  String get chats;

  /// No description provided for @suggestExplain.
  ///
  /// In en, this message translates to:
  /// **'Explain something'**
  String get suggestExplain;

  /// No description provided for @suggestExplainPrompt.
  ///
  /// In en, this message translates to:
  /// **'Explain how '**
  String get suggestExplainPrompt;

  /// No description provided for @suggestCode.
  ///
  /// In en, this message translates to:
  /// **'Write code'**
  String get suggestCode;

  /// No description provided for @suggestCodePrompt.
  ///
  /// In en, this message translates to:
  /// **'Write a function that '**
  String get suggestCodePrompt;

  /// No description provided for @suggestSummarize.
  ///
  /// In en, this message translates to:
  /// **'Summarize text'**
  String get suggestSummarize;

  /// No description provided for @suggestSummarizePrompt.
  ///
  /// In en, this message translates to:
  /// **'Summarize this:\n\n'**
  String get suggestSummarizePrompt;

  /// No description provided for @suggestBrainstorm.
  ///
  /// In en, this message translates to:
  /// **'Brainstorm'**
  String get suggestBrainstorm;

  /// No description provided for @suggestBrainstormPrompt.
  ///
  /// In en, this message translates to:
  /// **'Give me 10 ideas for '**
  String get suggestBrainstormPrompt;

  /// No description provided for @howCanIHelp.
  ///
  /// In en, this message translates to:
  /// **'HOW CAN I HELP?'**
  String get howCanIHelp;

  /// No description provided for @emptyChatSub.
  ///
  /// In en, this message translates to:
  /// **'Type a message, or talk hands-free in a voice call.'**
  String get emptyChatSub;

  /// No description provided for @emptyChatSubText.
  ///
  /// In en, this message translates to:
  /// **'Type anything you want to know.'**
  String get emptyChatSubText;

  /// No description provided for @connectOmniRoute.
  ///
  /// In en, this message translates to:
  /// **'Connect OmniRoute'**
  String get connectOmniRoute;

  /// No description provided for @connectOmniRouteSub.
  ///
  /// In en, this message translates to:
  /// **'Add your API key and server to start chatting'**
  String get connectOmniRouteSub;

  /// No description provided for @startVoiceCall.
  ///
  /// In en, this message translates to:
  /// **'Start a voice call'**
  String get startVoiceCall;

  /// No description provided for @startVoiceCallSub.
  ///
  /// In en, this message translates to:
  /// **'Talk hands-free. Replies are read in your call voice.'**
  String get startVoiceCallSub;

  /// No description provided for @voiceCall.
  ///
  /// In en, this message translates to:
  /// **'Voice call'**
  String get voiceCall;

  /// No description provided for @editAndResend.
  ///
  /// In en, this message translates to:
  /// **'Edit and resend'**
  String get editAndResend;

  /// No description provided for @interrupted.
  ///
  /// In en, this message translates to:
  /// **'Interrupted'**
  String get interrupted;

  /// No description provided for @stopped.
  ///
  /// In en, this message translates to:
  /// **'Stopped'**
  String get stopped;

  /// No description provided for @stopReading.
  ///
  /// In en, this message translates to:
  /// **'Stop reading'**
  String get stopReading;

  /// No description provided for @readAloud.
  ///
  /// In en, this message translates to:
  /// **'Read aloud'**
  String get readAloud;

  /// No description provided for @regenerate.
  ///
  /// In en, this message translates to:
  /// **'Regenerate'**
  String get regenerate;

  /// No description provided for @thinking.
  ///
  /// In en, this message translates to:
  /// **'Thinking'**
  String get thinking;

  /// No description provided for @messageHint.
  ///
  /// In en, this message translates to:
  /// **'Message Bangla AI'**
  String get messageHint;

  /// No description provided for @stopGenerating.
  ///
  /// In en, this message translates to:
  /// **'Stop generating'**
  String get stopGenerating;

  /// No description provided for @emptyReply.
  ///
  /// In en, this message translates to:
  /// **'The AI sent an empty reply. Try again.'**
  String get emptyReply;

  /// No description provided for @connectedReply.
  ///
  /// In en, this message translates to:
  /// **'Connected. {model} replied: \"{reply}\"'**
  String connectedReply(String model, String reply);

  /// No description provided for @themeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @aiConnection.
  ///
  /// In en, this message translates to:
  /// **'AI connection'**
  String get aiConnection;

  /// No description provided for @aiConnectionHelp.
  ///
  /// In en, this message translates to:
  /// **'OmniRoute or any OpenAI-compatible server. If OmniRoute runs on your computer, use http://<computer-ip>:20128/v1 with the phone on the same Wi-Fi, or your OmniRoute cloud or tunnel address.'**
  String get aiConnectionHelp;

  /// No description provided for @apiKeyLabel.
  ///
  /// In en, this message translates to:
  /// **'OmniRoute API key'**
  String get apiKeyLabel;

  /// No description provided for @apiKeyHelper.
  ///
  /// In en, this message translates to:
  /// **'Stored encrypted on this phone.'**
  String get apiKeyHelper;

  /// No description provided for @hideKey.
  ///
  /// In en, this message translates to:
  /// **'Hide key'**
  String get hideKey;

  /// No description provided for @showKey.
  ///
  /// In en, this message translates to:
  /// **'Show key'**
  String get showKey;

  /// No description provided for @serverAddress.
  ///
  /// In en, this message translates to:
  /// **'Server address'**
  String get serverAddress;

  /// No description provided for @testing.
  ///
  /// In en, this message translates to:
  /// **'Testing...'**
  String get testing;

  /// No description provided for @testConnection.
  ///
  /// In en, this message translates to:
  /// **'Test connection'**
  String get testConnection;

  /// No description provided for @model.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get model;

  /// No description provided for @modelsInList.
  ///
  /// In en, this message translates to:
  /// **'{count} in your list'**
  String modelsInList(int count);

  /// No description provided for @customInstructions.
  ///
  /// In en, this message translates to:
  /// **'Custom instructions'**
  String get customInstructions;

  /// No description provided for @systemPromptLabel.
  ///
  /// In en, this message translates to:
  /// **'System prompt (optional)'**
  String get systemPromptLabel;

  /// No description provided for @systemPromptHint.
  ///
  /// In en, this message translates to:
  /// **'For example: You are a patient tutor. Keep answers short.'**
  String get systemPromptHint;

  /// No description provided for @systemPromptHelper.
  ///
  /// In en, this message translates to:
  /// **'Sent with every chat and call, together with the instruction to reply in the app language. Calls also ask for short, spoken replies.'**
  String get systemPromptHelper;

  /// No description provided for @voice.
  ///
  /// In en, this message translates to:
  /// **'Voice'**
  String get voice;

  /// No description provided for @callVoice.
  ///
  /// In en, this message translates to:
  /// **'Call voice'**
  String get callVoice;

  /// No description provided for @callVoiceSub.
  ///
  /// In en, this message translates to:
  /// **'Used in calls and for Read aloud'**
  String get callVoiceSub;

  /// No description provided for @speakingSpeed.
  ///
  /// In en, this message translates to:
  /// **'Speaking speed'**
  String get speakingSpeed;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @languageSub.
  ///
  /// In en, this message translates to:
  /// **'App text, AI replies and speech recognition'**
  String get languageSub;

  /// No description provided for @appearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearance;

  /// No description provided for @deleteAllChats.
  ///
  /// In en, this message translates to:
  /// **'Delete all chats'**
  String get deleteAllChats;

  /// No description provided for @deleteAllChatsSub.
  ///
  /// In en, this message translates to:
  /// **'Chats are saved only on this phone'**
  String get deleteAllChatsSub;

  /// No description provided for @deleteAllChatsTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete all chats?'**
  String get deleteAllChatsTitle;

  /// No description provided for @deleteAllChatsBody.
  ///
  /// In en, this message translates to:
  /// **'Every saved chat on this phone will be deleted. This cannot be undone.'**
  String get deleteAllChatsBody;

  /// No description provided for @deleteAll.
  ///
  /// In en, this message translates to:
  /// **'Delete all'**
  String get deleteAll;

  /// No description provided for @allChatsDeleted.
  ///
  /// In en, this message translates to:
  /// **'All chats deleted'**
  String get allChatsDeleted;

  /// No description provided for @about.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get about;

  /// No description provided for @aboutVersion.
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String aboutVersion(String version);

  /// No description provided for @aboutSpeech.
  ///
  /// In en, this message translates to:
  /// **'Speech recognition uses your phone\'s built-in recognizer (free) and listens in the app language: Bangla (bn-BD) by default. For offline recognition on Android, install the offline language in the Google app or Speech Services settings.'**
  String get aboutSpeech;

  /// No description provided for @testFailed.
  ///
  /// In en, this message translates to:
  /// **'Test failed: {error}'**
  String testFailed(String error);

  /// No description provided for @nowCallVoice.
  ///
  /// In en, this message translates to:
  /// **'{name} is now the call voice'**
  String nowCallVoice(String name);

  /// No description provided for @callVoicePill.
  ///
  /// In en, this message translates to:
  /// **'CALL VOICE'**
  String get callVoicePill;

  /// No description provided for @setAsCallVoice.
  ///
  /// In en, this message translates to:
  /// **'Set as call voice'**
  String get setAsCallVoice;

  /// No description provided for @genderFemale.
  ///
  /// In en, this message translates to:
  /// **'female'**
  String get genderFemale;

  /// No description provided for @genderMale.
  ///
  /// In en, this message translates to:
  /// **'male'**
  String get genderMale;

  /// No description provided for @langBanglaBangladesh.
  ///
  /// In en, this message translates to:
  /// **'Bangla (Bangladesh)'**
  String get langBanglaBangladesh;

  /// No description provided for @langBanglaIndia.
  ///
  /// In en, this message translates to:
  /// **'Bangla (India)'**
  String get langBanglaIndia;

  /// No description provided for @voicesIntro.
  ///
  /// In en, this message translates to:
  /// **'Free Bangla voices from Speech Services by Google, built into your phone. They read the AI replies in calls and Read aloud.'**
  String get voicesIntro;

  /// No description provided for @voiceNumbered.
  ///
  /// In en, this message translates to:
  /// **'Voice {number}'**
  String voiceNumbered(String number);

  /// No description provided for @voiceOfflineTag.
  ///
  /// In en, this message translates to:
  /// **'works offline'**
  String get voiceOfflineTag;

  /// No description provided for @voiceNetworkTag.
  ///
  /// In en, this message translates to:
  /// **'needs internet'**
  String get voiceNetworkTag;

  /// No description provided for @voiceDefaultTag.
  ///
  /// In en, this message translates to:
  /// **'default'**
  String get voiceDefaultTag;

  /// No description provided for @selected.
  ///
  /// In en, this message translates to:
  /// **'Selected'**
  String get selected;

  /// No description provided for @select.
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get select;

  /// No description provided for @play.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get play;

  /// No description provided for @pitch.
  ///
  /// In en, this message translates to:
  /// **'Pitch'**
  String get pitch;

  /// No description provided for @speedValue.
  ///
  /// In en, this message translates to:
  /// **'{value}x'**
  String speedValue(String value);

  /// No description provided for @loadingVoices.
  ///
  /// In en, this message translates to:
  /// **'Looking for Bangla voices...'**
  String get loadingVoices;

  /// No description provided for @noBanglaVoicesTitle.
  ///
  /// In en, this message translates to:
  /// **'No Bangla voice found'**
  String get noBanglaVoicesTitle;

  /// No description provided for @refreshVoices.
  ///
  /// In en, this message translates to:
  /// **'Check again'**
  String get refreshVoices;

  /// No description provided for @voiceTestSample.
  ///
  /// In en, this message translates to:
  /// **'Hi! This is {name}. Does this voice sound good for our calls?'**
  String voiceTestSample(String name);

  /// No description provided for @setupNoGoogleTitle.
  ///
  /// In en, this message translates to:
  /// **'Install Google\'s voice'**
  String get setupNoGoogleTitle;

  /// No description provided for @setupNoGoogleBody.
  ///
  /// In en, this message translates to:
  /// **'To hear replies in Bangla, install the free \"Speech Services by Google\" app from the Play Store, then come back.'**
  String get setupNoGoogleBody;

  /// No description provided for @setupNoGoogleButton.
  ///
  /// In en, this message translates to:
  /// **'Open Play Store'**
  String get setupNoGoogleButton;

  /// No description provided for @setupNoBanglaTitle.
  ///
  /// In en, this message translates to:
  /// **'Install the Bangla voice'**
  String get setupNoBanglaTitle;

  /// No description provided for @setupNoBanglaBody.
  ///
  /// In en, this message translates to:
  /// **'Google\'s Bangla voice is not on this phone yet. Tap below, choose Bangla (Bangladesh) and download it. It is free and works offline afterwards.'**
  String get setupNoBanglaBody;

  /// No description provided for @setupNoBanglaButton.
  ///
  /// In en, this message translates to:
  /// **'Install Bangla voice'**
  String get setupNoBanglaButton;

  /// No description provided for @setupLater.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get setupLater;

  /// No description provided for @setupCouldNotOpen.
  ///
  /// In en, this message translates to:
  /// **'Could not open the settings. Open Settings > Accessibility > Text-to-speech on your phone.'**
  String get setupCouldNotOpen;

  /// No description provided for @voiceUnavailableIos.
  ///
  /// In en, this message translates to:
  /// **'Bangla voices come from your phone\'s speech settings.'**
  String get voiceUnavailableIos;

  /// No description provided for @callEnded.
  ///
  /// In en, this message translates to:
  /// **'Call ended'**
  String get callEnded;

  /// No description provided for @connecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting...'**
  String get connecting;

  /// No description provided for @listening.
  ///
  /// In en, this message translates to:
  /// **'Listening'**
  String get listening;

  /// No description provided for @speakNow.
  ///
  /// In en, this message translates to:
  /// **'speak now'**
  String get speakNow;

  /// No description provided for @tapToInterrupt.
  ///
  /// In en, this message translates to:
  /// **'tap to interrupt'**
  String get tapToInterrupt;

  /// No description provided for @speaking.
  ///
  /// In en, this message translates to:
  /// **'Speaking'**
  String get speaking;

  /// No description provided for @somethingWentWrong.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get somethingWentWrong;

  /// No description provided for @voiceModeTitle.
  ///
  /// In en, this message translates to:
  /// **'Voice'**
  String get voiceModeTitle;

  /// No description provided for @closeVoiceMode.
  ///
  /// In en, this message translates to:
  /// **'Close voice mode'**
  String get closeVoiceMode;

  /// No description provided for @interrupt.
  ///
  /// In en, this message translates to:
  /// **'Interrupt'**
  String get interrupt;

  /// No description provided for @callAgain.
  ///
  /// In en, this message translates to:
  /// **'Call again'**
  String get callAgain;

  /// No description provided for @hangUp.
  ///
  /// In en, this message translates to:
  /// **'Hang up'**
  String get hangUp;

  /// No description provided for @hideText.
  ///
  /// In en, this message translates to:
  /// **'Hide text'**
  String get hideText;

  /// No description provided for @showText.
  ///
  /// In en, this message translates to:
  /// **'Show text'**
  String get showText;

  /// No description provided for @startTalkingHint.
  ///
  /// In en, this message translates to:
  /// **'Start talking. I stop listening after a short pause.'**
  String get startTalkingHint;

  /// No description provided for @callSavedInChat.
  ///
  /// In en, this message translates to:
  /// **'Your call is saved in the chat.'**
  String get callSavedInChat;

  /// No description provided for @youLabel.
  ///
  /// In en, this message translates to:
  /// **'YOU'**
  String get youLabel;

  /// No description provided for @aiLabel.
  ///
  /// In en, this message translates to:
  /// **'BANGLA AI'**
  String get aiLabel;

  /// No description provided for @voiceError.
  ///
  /// In en, this message translates to:
  /// **'Voice error: {error}'**
  String voiceError(String error);

  /// No description provided for @voiceOff.
  ///
  /// In en, this message translates to:
  /// **'Voice is off for now. The admin will turn it on soon.'**
  String get voiceOff;

  /// No description provided for @micPermission.
  ///
  /// In en, this message translates to:
  /// **'Microphone permission is needed for calls.'**
  String get micPermission;

  /// No description provided for @speechUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Speech recognition is not available. Allow the microphone and make sure Google speech services (Android) are installed.'**
  String get speechUnavailable;

  /// No description provided for @modelAutoDesc.
  ///
  /// In en, this message translates to:
  /// **'Picks the best model for each message'**
  String get modelAutoDesc;

  /// No description provided for @modelAutoFastDesc.
  ///
  /// In en, this message translates to:
  /// **'Picks a lighter model for faster replies'**
  String get modelAutoFastDesc;

  /// No description provided for @resetList.
  ///
  /// In en, this message translates to:
  /// **'Reset list'**
  String get resetList;

  /// No description provided for @modelSheetHelp.
  ///
  /// In en, this message translates to:
  /// **'OmniRoute model IDs. Your choice applies to new replies and voice calls.'**
  String get modelSheetHelp;

  /// No description provided for @addModelHint.
  ///
  /// In en, this message translates to:
  /// **'Add a model, e.g. openai/gpt-4o'**
  String get addModelHint;

  /// No description provided for @addModel.
  ///
  /// In en, this message translates to:
  /// **'Add model'**
  String get addModel;

  /// No description provided for @removeModel.
  ///
  /// In en, this message translates to:
  /// **'Remove {model}'**
  String removeModel(String model);

  /// No description provided for @apiKeyRejected.
  ///
  /// In en, this message translates to:
  /// **'API key rejected ({code}). Check your OmniRoute key.'**
  String apiKeyRejected(int code);

  /// No description provided for @notFound404.
  ///
  /// In en, this message translates to:
  /// **'Not found (404). Check that the base URL ends with /v1 and the model name is right.'**
  String get notFound404;

  /// No description provided for @aiRequestFailed.
  ///
  /// In en, this message translates to:
  /// **'AI request failed ({code}): {detail}'**
  String aiRequestFailed(int code, String detail);

  /// No description provided for @unexpectedResponse.
  ///
  /// In en, this message translates to:
  /// **'The AI returned an unexpected response.'**
  String get unexpectedResponse;

  /// No description provided for @timeoutError.
  ///
  /// In en, this message translates to:
  /// **'The server took too long to answer. Check the address and your connection.'**
  String get timeoutError;

  /// No description provided for @serverUnreachable.
  ///
  /// In en, this message translates to:
  /// **'Can\'t reach the Bangla AI server. Check your internet and try again.'**
  String get serverUnreachable;

  /// No description provided for @serverWaking.
  ///
  /// In en, this message translates to:
  /// **'Server is waking up. This can take up to a minute...'**
  String get serverWaking;

  /// No description provided for @serverOffline.
  ///
  /// In en, this message translates to:
  /// **'Offline: can\'t reach the server right now.'**
  String get serverOffline;

  /// No description provided for @appDisabled.
  ///
  /// In en, this message translates to:
  /// **'The app is paused for now. Please try again later.'**
  String get appDisabled;

  /// No description provided for @serverNotReady.
  ///
  /// In en, this message translates to:
  /// **'The server isn\'t set up yet. Please try again later.'**
  String get serverNotReady;

  /// No description provided for @tooManyRequests.
  ///
  /// In en, this message translates to:
  /// **'Too many requests right now. Wait a moment and try again.'**
  String get tooManyRequests;

  /// No description provided for @modelSheetHelpServer.
  ///
  /// In en, this message translates to:
  /// **'Models offered by Bangla AI. Your choice applies to new replies and voice calls.'**
  String get modelSheetHelpServer;

  /// No description provided for @defaultTag.
  ///
  /// In en, this message translates to:
  /// **'default'**
  String get defaultTag;

  /// No description provided for @useDefaultVoice.
  ///
  /// In en, this message translates to:
  /// **'Use default voice'**
  String get useDefaultVoice;

  /// No description provided for @useDefaultVoiceSub.
  ///
  /// In en, this message translates to:
  /// **'Voice, speed and pitch set by Bangla AI'**
  String get useDefaultVoiceSub;

  /// No description provided for @phoneBestVoice.
  ///
  /// In en, this message translates to:
  /// **'Best Bangla voice on this phone'**
  String get phoneBestVoice;

  /// No description provided for @retryNow.
  ///
  /// In en, this message translates to:
  /// **'Try now'**
  String get retryNow;

  /// No description provided for @callStartHint.
  ///
  /// In en, this message translates to:
  /// **'Start talking. I stop listening after a short pause.'**
  String get callStartHint;

  /// No description provided for @callSavedHint.
  ///
  /// In en, this message translates to:
  /// **'Your call is saved in the chat.'**
  String get callSavedHint;

  /// No description provided for @assistantLabel.
  ///
  /// In en, this message translates to:
  /// **'BANGLA AI'**
  String get assistantLabel;

  /// Label for the "auto" model
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get modelAuto;

  /// Label for the "auto/fast" model
  ///
  /// In en, this message translates to:
  /// **'Fast'**
  String get modelFast;

  /// No description provided for @signIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get signIn;

  /// No description provided for @signUp.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get signUp;

  /// No description provided for @authWelcome.
  ///
  /// In en, this message translates to:
  /// **'Welcome back'**
  String get authWelcome;

  /// No description provided for @authWelcomeSub.
  ///
  /// In en, this message translates to:
  /// **'Sign in to your Bangla AI account.'**
  String get authWelcomeSub;

  /// No description provided for @authSignUpTitle.
  ///
  /// In en, this message translates to:
  /// **'New account'**
  String get authSignUpTitle;

  /// No description provided for @authSignUpSub.
  ///
  /// In en, this message translates to:
  /// **'It only takes a minute.'**
  String get authSignUpSub;

  /// No description provided for @continueWithGoogle.
  ///
  /// In en, this message translates to:
  /// **'Continue with Google'**
  String get continueWithGoogle;

  /// No description provided for @orWithEmail.
  ///
  /// In en, this message translates to:
  /// **'or with email'**
  String get orWithEmail;

  /// No description provided for @fieldName.
  ///
  /// In en, this message translates to:
  /// **'Your name'**
  String get fieldName;

  /// No description provided for @fieldEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get fieldEmail;

  /// No description provided for @fieldPassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get fieldPassword;

  /// No description provided for @fieldNewPassword.
  ///
  /// In en, this message translates to:
  /// **'New password'**
  String get fieldNewPassword;

  /// No description provided for @fieldCurrentPassword.
  ///
  /// In en, this message translates to:
  /// **'Current password'**
  String get fieldCurrentPassword;

  /// No description provided for @passwordHint.
  ///
  /// In en, this message translates to:
  /// **'At least 8 characters'**
  String get passwordHint;

  /// No description provided for @showPassword.
  ///
  /// In en, this message translates to:
  /// **'Show password'**
  String get showPassword;

  /// No description provided for @hidePassword.
  ///
  /// In en, this message translates to:
  /// **'Hide password'**
  String get hidePassword;

  /// No description provided for @forgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot password?'**
  String get forgotPassword;

  /// No description provided for @haveAccount.
  ///
  /// In en, this message translates to:
  /// **'Already have an account?'**
  String get haveAccount;

  /// No description provided for @noAccount.
  ///
  /// In en, this message translates to:
  /// **'No account yet?'**
  String get noAccount;

  /// No description provided for @notNow.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get notNow;

  /// No description provided for @errEmail.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email address'**
  String get errEmail;

  /// No description provided for @errPassword.
  ///
  /// In en, this message translates to:
  /// **'Use at least 8 characters'**
  String get errPassword;

  /// No description provided for @errName.
  ///
  /// In en, this message translates to:
  /// **'Enter your name'**
  String get errName;

  /// No description provided for @errWrongLogin.
  ///
  /// In en, this message translates to:
  /// **'The email or password is wrong.'**
  String get errWrongLogin;

  /// No description provided for @errEmailTaken.
  ///
  /// In en, this message translates to:
  /// **'An account with this email already exists. Sign in instead.'**
  String get errEmailTaken;

  /// No description provided for @errUseGoogle.
  ///
  /// In en, this message translates to:
  /// **'This email signs in with Google. Tap \"Continue with Google\".'**
  String get errUseGoogle;

  /// No description provided for @errNetwork.
  ///
  /// In en, this message translates to:
  /// **'Check your internet and try again.'**
  String get errNetwork;

  /// No description provided for @errTimeout.
  ///
  /// In en, this message translates to:
  /// **'The server is slow to answer. Try again.'**
  String get errTimeout;

  /// No description provided for @errAccountsDown.
  ///
  /// In en, this message translates to:
  /// **'Accounts are unavailable right now. Try again soon.'**
  String get errAccountsDown;

  /// No description provided for @errGeneric.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Try again.'**
  String get errGeneric;

  /// No description provided for @errWrongCode.
  ///
  /// In en, this message translates to:
  /// **'This code is wrong or has expired.'**
  String get errWrongCode;

  /// No description provided for @errCodeDigits.
  ///
  /// In en, this message translates to:
  /// **'Enter the 6-digit code'**
  String get errCodeDigits;

  /// No description provided for @errTooManyTries.
  ///
  /// In en, this message translates to:
  /// **'Too many wrong tries. Get a new code.'**
  String get errTooManyTries;

  /// No description provided for @errWrongCurrent.
  ///
  /// In en, this message translates to:
  /// **'The current password is wrong.'**
  String get errWrongCurrent;

  /// No description provided for @errImage.
  ///
  /// In en, this message translates to:
  /// **'This picture can\'t be used. Pick another one.'**
  String get errImage;

  /// No description provided for @googleCancelled.
  ///
  /// In en, this message translates to:
  /// **'Google sign-in was cancelled.'**
  String get googleCancelled;

  /// No description provided for @googleFailed.
  ///
  /// In en, this message translates to:
  /// **'Google sign-in didn\'t work. Try again.'**
  String get googleFailed;

  /// No description provided for @googleOff.
  ///
  /// In en, this message translates to:
  /// **'Google sign-in isn\'t set up yet. Use your email.'**
  String get googleOff;

  /// No description provided for @googleSigningIn.
  ///
  /// In en, this message translates to:
  /// **'Signing in with Google...'**
  String get googleSigningIn;

  /// No description provided for @resetTitle.
  ///
  /// In en, this message translates to:
  /// **'Reset password'**
  String get resetTitle;

  /// No description provided for @resetSub.
  ///
  /// In en, this message translates to:
  /// **'Enter your email and we\'ll send you a 6-digit code.'**
  String get resetSub;

  /// No description provided for @sendCode.
  ///
  /// In en, this message translates to:
  /// **'Send code'**
  String get sendCode;

  /// No description provided for @codeLabel.
  ///
  /// In en, this message translates to:
  /// **'6-digit code'**
  String get codeLabel;

  /// No description provided for @setNewPassword.
  ///
  /// In en, this message translates to:
  /// **'Set new password'**
  String get setNewPassword;

  /// No description provided for @resendCode.
  ///
  /// In en, this message translates to:
  /// **'Resend code'**
  String get resendCode;

  /// No description provided for @codeResent.
  ///
  /// In en, this message translates to:
  /// **'A new code is on its way.'**
  String get codeResent;

  /// No description provided for @passwordChanged.
  ///
  /// In en, this message translates to:
  /// **'Password changed.'**
  String get passwordChanged;

  /// No description provided for @verifyTitle.
  ///
  /// In en, this message translates to:
  /// **'Verify your email'**
  String get verifyTitle;

  /// No description provided for @verifyNotSent.
  ///
  /// In en, this message translates to:
  /// **'The code couldn\'t be sent right now. Tap \"Resend code\" in a little while.'**
  String get verifyNotSent;

  /// No description provided for @verifyButton.
  ///
  /// In en, this message translates to:
  /// **'Verify'**
  String get verifyButton;

  /// No description provided for @emailVerified.
  ///
  /// In en, this message translates to:
  /// **'Email verified'**
  String get emailVerified;

  /// No description provided for @emailNotVerified.
  ///
  /// In en, this message translates to:
  /// **'Email not verified yet'**
  String get emailNotVerified;

  /// No description provided for @verifyNow.
  ///
  /// In en, this message translates to:
  /// **'Verify now'**
  String get verifyNow;

  /// No description provided for @checkSpam.
  ///
  /// In en, this message translates to:
  /// **'Can\'t find it? Check your Spam folder.'**
  String get checkSpam;

  /// No description provided for @profile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profile;

  /// No description provided for @profileSub.
  ///
  /// In en, this message translates to:
  /// **'Your name, picture and account'**
  String get profileSub;

  /// No description provided for @changePhoto.
  ///
  /// In en, this message translates to:
  /// **'Change photo'**
  String get changePhoto;

  /// No description provided for @addPhoto.
  ///
  /// In en, this message translates to:
  /// **'Add a photo'**
  String get addPhoto;

  /// No description provided for @removePhoto.
  ///
  /// In en, this message translates to:
  /// **'Remove photo'**
  String get removePhoto;

  /// No description provided for @choosePhoto.
  ///
  /// In en, this message translates to:
  /// **'Choose from gallery'**
  String get choosePhoto;

  /// No description provided for @takePhoto.
  ///
  /// In en, this message translates to:
  /// **'Take a photo'**
  String get takePhoto;

  /// No description provided for @photoUpdated.
  ///
  /// In en, this message translates to:
  /// **'Photo updated'**
  String get photoUpdated;

  /// No description provided for @photoRemoved.
  ///
  /// In en, this message translates to:
  /// **'Photo removed'**
  String get photoRemoved;

  /// No description provided for @nameSaved.
  ///
  /// In en, this message translates to:
  /// **'Name saved'**
  String get nameSaved;

  /// No description provided for @accountSection.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get accountSection;

  /// No description provided for @signInMethod.
  ///
  /// In en, this message translates to:
  /// **'Sign-in method'**
  String get signInMethod;

  /// No description provided for @methodGoogle.
  ///
  /// In en, this message translates to:
  /// **'Google'**
  String get methodGoogle;

  /// No description provided for @methodEmail.
  ///
  /// In en, this message translates to:
  /// **'Email and password'**
  String get methodEmail;

  /// No description provided for @methodBoth.
  ///
  /// In en, this message translates to:
  /// **'Google, and email and password'**
  String get methodBoth;

  /// No description provided for @changePassword.
  ///
  /// In en, this message translates to:
  /// **'Change password'**
  String get changePassword;

  /// No description provided for @setPassword.
  ///
  /// In en, this message translates to:
  /// **'Set a password'**
  String get setPassword;

  /// No description provided for @setPasswordSub.
  ///
  /// In en, this message translates to:
  /// **'To also sign in with your email'**
  String get setPasswordSub;

  /// No description provided for @otherDevicesSignedOut.
  ///
  /// In en, this message translates to:
  /// **'Other devices were signed out.'**
  String get otherDevicesSignedOut;

  /// No description provided for @signOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get signOut;

  /// No description provided for @signOutConfirm.
  ///
  /// In en, this message translates to:
  /// **'Sign out?'**
  String get signOutConfirm;

  /// No description provided for @signOutBody.
  ///
  /// In en, this message translates to:
  /// **'Chats on this device stay here.'**
  String get signOutBody;

  /// No description provided for @signedOut.
  ///
  /// In en, this message translates to:
  /// **'Signed out'**
  String get signedOut;

  /// No description provided for @signInToChat.
  ///
  /// In en, this message translates to:
  /// **'Sign in to chat.'**
  String get signInToChat;

  /// No description provided for @signInRequiredSub.
  ///
  /// In en, this message translates to:
  /// **'You need an account to chat. Sign in or create one.'**
  String get signInRequiredSub;

  /// No description provided for @sidebarSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get sidebarSignIn;

  /// No description provided for @sidebarSignInSub.
  ///
  /// In en, this message translates to:
  /// **'or create an account'**
  String get sidebarSignInSub;

  /// No description provided for @errTooSoon.
  ///
  /// In en, this message translates to:
  /// **'Try again in {seconds} seconds.'**
  String errTooSoon(String seconds);

  /// No description provided for @resendIn.
  ///
  /// In en, this message translates to:
  /// **'Resend in {seconds}s'**
  String resendIn(String seconds);

  /// No description provided for @codeSentTo.
  ///
  /// In en, this message translates to:
  /// **'We sent a 6-digit code to {email}.'**
  String codeSentTo(String email);

  /// No description provided for @resetCodeSent.
  ///
  /// In en, this message translates to:
  /// **'If an account uses {email}, a code is on its way.'**
  String resetCodeSent(String email);

  /// No description provided for @welcomeName.
  ///
  /// In en, this message translates to:
  /// **'Welcome, {name}!'**
  String welcomeName(String name);

  /// No description provided for @triesLeft.
  ///
  /// In en, this message translates to:
  /// **'That code is wrong. {count} tries left.'**
  String triesLeft(String count);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['bn', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'bn':
      return AppLocalizationsBn();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}

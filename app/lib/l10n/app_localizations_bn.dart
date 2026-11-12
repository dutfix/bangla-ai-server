// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Bengali Bangla (`bn`).
class AppLocalizationsBn extends AppLocalizations {
  AppLocalizationsBn([String locale = 'bn']) : super(locale);

  @override
  String get appName => 'বাংলা এআই';

  @override
  String get appNameLatin => 'BANGLA AI';

  @override
  String get appTagline => 'বাংলায় চ্যাট করুন, কথা বলুন';

  @override
  String get cancel => 'বাতিল';

  @override
  String get delete => 'মুছুন';

  @override
  String get rename => 'নাম বদলান';

  @override
  String get save => 'সংরক্ষণ';

  @override
  String get saved => 'সংরক্ষিত হয়েছে';

  @override
  String get ok => 'ঠিক আছে';

  @override
  String get retry => 'আবার চেষ্টা করুন';

  @override
  String get done => 'শেষ';

  @override
  String get back => 'পেছনে';

  @override
  String get clear => 'মুছে দিন';

  @override
  String get send => 'পাঠান';

  @override
  String get stop => 'থামান';

  @override
  String get test => 'শুনে দেখুন';

  @override
  String get copy => 'কপি';

  @override
  String get copied => 'কপি হয়েছে';

  @override
  String get tryAgain => 'আবার চেষ্টা করুন';

  @override
  String get newChat => 'নতুন চ্যাট';

  @override
  String get needApiKey => 'আগে সেটিংসে আপনার OmniRoute API কী যোগ করুন।';

  @override
  String couldNotReadAloud(String error) {
    return 'জোরে পড়া গেল না: $error';
  }

  @override
  String couldNotOpen(String link) {
    return '$link খোলা গেল না';
  }

  @override
  String get code => 'কোড';

  @override
  String get groupToday => 'আজ';

  @override
  String get groupYesterday => 'গতকাল';

  @override
  String get groupPrevious7 => 'গত ৭ দিন';

  @override
  String get groupPrevious30 => 'গত ৩০ দিন';

  @override
  String get monthNames =>
      'জানুয়ারি,ফেব্রুয়ারি,মার্চ,এপ্রিল,মে,জুন,জুলাই,আগস্ট,সেপ্টেম্বর,অক্টোবর,নভেম্বর,ডিসেম্বর';

  @override
  String get renameChat => 'চ্যাটের নাম বদলান';

  @override
  String get deleteChatTitle => 'চ্যাটটি মুছবেন?';

  @override
  String deleteChatBody(String title) {
    return '\"$title\" এই ফোন থেকে মুছে যাবে।';
  }

  @override
  String get voices => 'কণ্ঠ';

  @override
  String get settings => 'সেটিংস';

  @override
  String get searchChats => 'চ্যাট খুঁজুন';

  @override
  String get noChatsYet => 'এখনো কোনো চ্যাট নেই';

  @override
  String get noMatches => 'কিছু মেলেনি';

  @override
  String get chatsSavedHere => 'আপনার চ্যাটগুলো এই ফোনেই সংরক্ষিত থাকে।';

  @override
  String nothingMatches(String query) {
    return 'আপনার চ্যাটে \"$query\" এর সাথে মেলে এমন কিছু নেই।';
  }

  @override
  String get results => 'ফলাফল';

  @override
  String get chatOptions => 'চ্যাটের অপশন';

  @override
  String get jumpToLatest => 'সর্বশেষ বার্তায় যান';

  @override
  String get chats => 'চ্যাট';

  @override
  String get suggestExplain => 'কিছু বুঝিয়ে দিন';

  @override
  String get suggestExplainPrompt => 'সহজ করে বুঝিয়ে বলুন: ';

  @override
  String get suggestCode => 'কোড লিখুন';

  @override
  String get suggestCodePrompt => 'একটি ফাংশন লিখুন যা ';

  @override
  String get suggestSummarize => 'লেখার সারাংশ';

  @override
  String get suggestSummarizePrompt => 'এটির সারাংশ করুন:\n\n';

  @override
  String get suggestBrainstorm => 'নতুন আইডিয়া';

  @override
  String get suggestBrainstormPrompt => '১০টি আইডিয়া দিন: ';

  @override
  String get howCanIHelp => 'কীভাবে সাহায্য করতে পারি?';

  @override
  String get emptyChatSub => 'বার্তা লিখুন, অথবা ভয়েস কলে সরাসরি কথা বলুন।';

  @override
  String get connectOmniRoute => 'OmniRoute সংযুক্ত করুন';

  @override
  String get connectOmniRouteSub =>
      'চ্যাট শুরু করতে আপনার API কী ও সার্ভার যোগ করুন';

  @override
  String get startVoiceCall => 'ভয়েস কল শুরু করুন';

  @override
  String get startVoiceCallSub =>
      'হাত খালি রেখে কথা বলুন। উত্তর আপনার কলের কণ্ঠে শোনানো হবে।';

  @override
  String get voiceCall => 'ভয়েস কল';

  @override
  String get editAndResend => 'সম্পাদনা করে আবার পাঠান';

  @override
  String get interrupted => 'থামিয়ে দেওয়া হয়েছে';

  @override
  String get stopped => 'থামানো হয়েছে';

  @override
  String get stopReading => 'পড়া থামান';

  @override
  String get readAloud => 'জোরে পড়ুন';

  @override
  String get regenerate => 'আবার উত্তর দিন';

  @override
  String get thinking => 'ভাবছি';

  @override
  String get messageHint => 'বাংলা এআই-কে লিখুন';

  @override
  String get stopGenerating => 'উত্তর থামান';

  @override
  String get emptyReply => 'এআই খালি উত্তর পাঠিয়েছে। আবার চেষ্টা করুন।';

  @override
  String connectedReply(String model, String reply) {
    return 'সংযোগ সফল। $model উত্তর দিয়েছে: \"$reply\"';
  }

  @override
  String get themeSystem => 'সিস্টেম';

  @override
  String get themeLight => 'লাইট';

  @override
  String get themeDark => 'ডার্ক';

  @override
  String get aiConnection => 'এআই সংযোগ';

  @override
  String get aiConnectionHelp =>
      'OmniRoute অথবা যেকোনো OpenAI-সমর্থিত সার্ভার। OmniRoute আপনার কম্পিউটারে চললে ফোন একই Wi-Fi-তে রেখে http://<কম্পিউটারের-IP>:20128/v1 ব্যবহার করুন, অথবা আপনার OmniRoute ক্লাউড বা টানেলের ঠিকানা দিন।';

  @override
  String get apiKeyLabel => 'OmniRoute API কী';

  @override
  String get apiKeyHelper => 'এই ফোনে এনক্রিপ্ট করে রাখা হয়।';

  @override
  String get hideKey => 'কী লুকান';

  @override
  String get showKey => 'কী দেখান';

  @override
  String get serverAddress => 'সার্ভারের ঠিকানা';

  @override
  String get testing => 'পরীক্ষা চলছে...';

  @override
  String get testConnection => 'সংযোগ পরীক্ষা করুন';

  @override
  String get model => 'মডেল';

  @override
  String modelsInList(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return 'আপনার তালিকায় $countStringটি';
  }

  @override
  String get customInstructions => 'নিজস্ব নির্দেশনা';

  @override
  String get systemPromptLabel => 'সিস্টেম প্রম্পট (ঐচ্ছিক)';

  @override
  String get systemPromptHint =>
      'যেমন: তুমি একজন ধৈর্যশীল শিক্ষক। উত্তর ছোট রাখো।';

  @override
  String get systemPromptHelper =>
      'প্রতিটি চ্যাট ও কলের সাথে পাঠানো হয়, অ্যাপের ভাষায় উত্তর দেওয়ার নির্দেশনার সাথে মিলিয়ে। কলে ছোট, কথ্য উত্তর চাওয়া হয়।';

  @override
  String get voice => 'কণ্ঠ';

  @override
  String get callVoice => 'কলের কণ্ঠ';

  @override
  String get callVoiceSub => 'কলে ও জোরে পড়ার সময় ব্যবহৃত হয়';

  @override
  String get speakingSpeed => 'কথা বলার গতি';

  @override
  String get language => 'ভাষা';

  @override
  String get languageSub => 'অ্যাপের লেখা, এআই-এর উত্তর ও কথা চেনা';

  @override
  String get appearance => 'অ্যাপের রূপ';

  @override
  String get deleteAllChats => 'সব চ্যাট মুছুন';

  @override
  String get deleteAllChatsSub => 'চ্যাট শুধু এই ফোনেই সংরক্ষিত থাকে';

  @override
  String get deleteAllChatsTitle => 'সব চ্যাট মুছবেন?';

  @override
  String get deleteAllChatsBody =>
      'এই ফোনে সংরক্ষিত সব চ্যাট মুছে যাবে। এটি আর ফেরানো যাবে না।';

  @override
  String get deleteAll => 'সব মুছুন';

  @override
  String get allChatsDeleted => 'সব চ্যাট মুছে ফেলা হয়েছে';

  @override
  String get about => 'অ্যাপ সম্পর্কে';

  @override
  String aboutVersion(String version) {
    return 'সংস্করণ $version';
  }

  @override
  String get aboutSpeech =>
      'কথা চেনার জন্য আপনার ফোনের নিজস্ব স্পিচ রিকগনাইজার (বিনামূল্যে) ব্যবহার হয়, আর এটি অ্যাপের ভাষায় শোনে: ডিফল্টভাবে বাংলা (bn-BD)। Android-এ অফলাইনে ব্যবহার করতে Google অ্যাপ বা Speech Services সেটিংস থেকে বাংলা অফলাইন ভাষা ইনস্টল করুন।';

  @override
  String testFailed(String error) {
    return 'শুনে দেখা গেল না: $error';
  }

  @override
  String nowCallVoice(String name) {
    return '$name এখন কলের কণ্ঠ';
  }

  @override
  String get callVoicePill => 'কলের কণ্ঠ';

  @override
  String get setAsCallVoice => 'কলের কণ্ঠ করুন';

  @override
  String get genderFemale => 'নারী';

  @override
  String get genderMale => 'পুরুষ';

  @override
  String get langBanglaBangladesh => 'বাংলা (বাংলাদেশ)';

  @override
  String get langBanglaIndia => 'বাংলা (ভারত)';

  @override
  String get voicesIntro =>
      'আপনার ফোনে থাকা Speech Services by Google-এর বিনামূল্যের বাংলা কণ্ঠ। কলে ও জোরে পড়ার সময় এগুলো এআই-এর উত্তর পড়ে শোনায়।';

  @override
  String voiceNumbered(String number) {
    return 'কণ্ঠ $number';
  }

  @override
  String get voiceOfflineTag => 'ইন্টারনেট ছাড়া চলে';

  @override
  String get voiceNetworkTag => 'ইন্টারনেট লাগে';

  @override
  String get voiceDefaultTag => 'ডিফল্ট';

  @override
  String get selected => 'নির্বাচিত';

  @override
  String get select => 'বেছে নিন';

  @override
  String get play => 'শুনুন';

  @override
  String get pitch => 'কণ্ঠের উচ্চতা';

  @override
  String speedValue(String value) {
    return '${value}x';
  }

  @override
  String get loadingVoices => 'বাংলা কণ্ঠ খোঁজা হচ্ছে...';

  @override
  String get noBanglaVoicesTitle => 'কোনো বাংলা কণ্ঠ পাওয়া যায়নি';

  @override
  String get refreshVoices => 'আবার দেখুন';

  @override
  String voiceTestSample(String name) {
    return 'হ্যালো! আমি $name। আমাদের কলের জন্য এই কণ্ঠটি কেমন লাগছে?';
  }

  @override
  String get setupNoGoogleTitle => 'Google-এর কণ্ঠ ইনস্টল করুন';

  @override
  String get setupNoGoogleBody =>
      'বাংলায় উত্তর শুনতে Play Store থেকে বিনামূল্যের \"Speech Services by Google\" অ্যাপটি ইনস্টল করুন, তারপর অ্যাপে ফিরে আসুন।';

  @override
  String get setupNoGoogleButton => 'Play Store খুলুন';

  @override
  String get setupNoBanglaTitle => 'বাংলা কণ্ঠ ইনস্টল করুন';

  @override
  String get setupNoBanglaBody =>
      'Google-এর বাংলা কণ্ঠ এখনো এই ফোনে নেই। নিচে চাপুন, বাংলা (বাংলাদেশ) বেছে নিয়ে ডাউনলোড করুন। এটি বিনামূল্যে, আর পরে ইন্টারনেট ছাড়াই চলে।';

  @override
  String get setupNoBanglaButton => 'বাংলা কণ্ঠ ইনস্টল করুন';

  @override
  String get setupLater => 'পরে';

  @override
  String get setupCouldNotOpen =>
      'সেটিংস খোলা গেল না। ফোনের Settings > Accessibility > Text-to-speech খুলুন।';

  @override
  String get voiceUnavailableIos =>
      'বাংলা কণ্ঠ আপনার ফোনের স্পিচ সেটিংস থেকে আসে।';

  @override
  String get callEnded => 'কল শেষ';

  @override
  String get connecting => 'সংযোগ হচ্ছে...';

  @override
  String get listening => 'শুনছি';

  @override
  String get speakNow => 'এখন বলুন';

  @override
  String get tapToInterrupt => 'থামাতে চাপুন';

  @override
  String get speaking => 'বলছি';

  @override
  String get somethingWentWrong => 'কিছু একটা সমস্যা হয়েছে';

  @override
  String get voiceModeTitle => 'ভয়েস';

  @override
  String get closeVoiceMode => 'ভয়েস মোড বন্ধ করুন';

  @override
  String get interrupt => 'থামান';

  @override
  String get callAgain => 'আবার কল করুন';

  @override
  String get hangUp => 'কল কাটুন';

  @override
  String get hideText => 'লেখা লুকান';

  @override
  String get showText => 'লেখা দেখান';

  @override
  String get startTalkingHint =>
      'কথা বলা শুরু করুন। একটু থামলেই আমি শোনা বন্ধ করব।';

  @override
  String get callSavedInChat => 'আপনার কলটি চ্যাটে সংরক্ষিত আছে।';

  @override
  String get youLabel => 'আপনি';

  @override
  String get aiLabel => 'বাংলা এআই';

  @override
  String voiceError(String error) {
    return 'কণ্ঠে সমস্যা: $error';
  }

  @override
  String get micPermission => 'কলের জন্য মাইক্রোফোনের অনুমতি দরকার।';

  @override
  String get speechUnavailable =>
      'কথা চেনার সুবিধা পাওয়া যাচ্ছে না। মাইক্রোফোনের অনুমতি দিন এবং (Android-এ) Google speech services ইনস্টল আছে কিনা দেখুন।';

  @override
  String get modelAutoDesc =>
      'প্রতিটি বার্তার জন্য সবচেয়ে উপযুক্ত মডেল নিজে থেকে বেছে নেয়';

  @override
  String get modelAutoFastDesc => 'আরও দ্রুত উত্তরের জন্য হালকা মডেল বেছে নেয়';

  @override
  String get resetList => 'তালিকা রিসেট করুন';

  @override
  String get modelSheetHelp =>
      'OmniRoute মডেল আইডি। আপনার পছন্দ নতুন উত্তর ও ভয়েস কলে প্রযোজ্য হবে।';

  @override
  String get addModelHint => 'মডেল যোগ করুন, যেমন openai/gpt-4o';

  @override
  String get addModel => 'মডেল যোগ করুন';

  @override
  String removeModel(String model) {
    return '$model সরান';
  }

  @override
  String apiKeyRejected(int code) {
    final intl.NumberFormat codeNumberFormat = intl.NumberFormat.decimalPattern(
      localeName,
    );
    final String codeString = codeNumberFormat.format(code);

    return 'API কী গ্রহণ করা হয়নি ($codeString)। আপনার OmniRoute কী দেখুন।';
  }

  @override
  String get notFound404 =>
      'পাওয়া যায়নি (404)। সার্ভারের ঠিকানা /v1 দিয়ে শেষ হয়েছে কিনা এবং মডেলের নাম ঠিক আছে কিনা দেখুন।';

  @override
  String aiRequestFailed(int code, String detail) {
    final intl.NumberFormat codeNumberFormat = intl.NumberFormat.decimalPattern(
      localeName,
    );
    final String codeString = codeNumberFormat.format(code);

    return 'এআই অনুরোধ ব্যর্থ হয়েছে ($codeString): $detail';
  }

  @override
  String get unexpectedResponse => 'এআই অপ্রত্যাশিত উত্তর দিয়েছে।';

  @override
  String get timeoutError =>
      'সার্ভার উত্তর দিতে অনেক দেরি করছে। ঠিকানা ও ইন্টারনেট সংযোগ দেখুন।';

  @override
  String get serverUnreachable =>
      'বাংলা এআই সার্ভারে পৌঁছানো যাচ্ছে না। ইন্টারনেট সংযোগ দেখে আবার চেষ্টা করুন।';

  @override
  String get serverWaking =>
      'সার্ভার চালু হচ্ছে। এক মিনিট পর্যন্ত লাগতে পারে...';

  @override
  String get serverOffline => 'অফলাইন: এখন সার্ভারে পৌঁছানো যাচ্ছে না।';

  @override
  String get appDisabled =>
      'অ্যাপটি এখন সাময়িকভাবে বন্ধ আছে। কিছুক্ষণ পরে আবার চেষ্টা করুন।';

  @override
  String get serverNotReady =>
      'সার্ভার এখনও প্রস্তুত নয়। কিছুক্ষণ পরে আবার চেষ্টা করুন।';

  @override
  String get tooManyRequests =>
      'এই মুহূর্তে অনেক অনুরোধ। একটু অপেক্ষা করে আবার চেষ্টা করুন।';

  @override
  String get modelSheetHelpServer =>
      'বাংলা এআই-এর দেওয়া মডেল। আপনার বাছাই নতুন উত্তর ও ভয়েস কলে ব্যবহার হবে।';

  @override
  String get defaultTag => 'ডিফল্ট';

  @override
  String get useDefaultVoice => 'ডিফল্ট ভয়েস ব্যবহার করুন';

  @override
  String get useDefaultVoiceSub => 'বাংলা এআই-এর ঠিক করা ভয়েস, গতি ও পিচ';

  @override
  String get phoneBestVoice => 'এই ফোনের সেরা বাংলা ভয়েস';

  @override
  String get retryNow => 'এখন চেষ্টা করুন';

  @override
  String get callStartHint =>
      'কথা বলা শুরু করুন। একটু থামলে আমি শোনা বন্ধ করব।';

  @override
  String get callSavedHint => 'আপনার কল চ্যাটে সেভ করা আছে।';

  @override
  String get assistantLabel => 'বাংলা এআই';

  @override
  String get modelAuto => 'স্বয়ংক্রিয়';

  @override
  String get modelFast => 'দ্রুত';
}

import 'package:flutter/painting.dart';

/// One of the four Bangla AI agents. All four have the same model and the
/// same tools; they differ in personality and what they enjoy most. The
/// server holds their full instructions (agents.js); the ids must match.
class Agent {
  const Agent({
    required this.id,
    required this.name,
    required this.nameEn,
    required this.role,
    required this.roleEn,
    required this.blurb,
    required this.blurbEn,
    required this.initial,
    required this.color,
    required this.suggestions,
    required this.suggestionsEn,
  });

  final String id;
  final String name;
  final String nameEn;
  final String role;
  final String roleEn;
  final String blurb;
  final String blurbEn;

  /// The letter on the agent's avatar.
  final String initial;
  final Color color;
  final List<String> suggestions;
  final List<String> suggestionsEn;

  String nameFor(bool english) => english ? nameEn : name;
  String roleFor(bool english) => english ? roleEn : role;
  String blurbFor(bool english) => english ? blurbEn : blurb;
  List<String> suggestionsFor(bool english) =>
      english ? suggestionsEn : suggestions;
}

const agents = <Agent>[
  Agent(
    id: 'mita',
    name: 'মিতা',
    nameEn: 'Mita',
    role: 'সবকিছুর সঙ্গী',
    roleEn: 'Everyday companion',
    blurb: 'পরিকল্পনা, রিমাইন্ডার, রুটিন আর রোজকার সব কাজে পাশে থাকা বন্ধু।',
    blurbEn: 'A friend for plans, reminders, routines and everyday life.',
    initial: 'ম',
    color: Color(0xFF1E8C55),
    suggestions: [
      'আগামীকাল সকাল ৭টায় আমাকে ব্যায়ামের কথা মনে করিয়ে দিও',
      'এই সপ্তাহের একটা সহজ রুটিন বানিয়ে দাও',
      'আজ ঢাকার আবহাওয়া কেমন?',
    ],
    suggestionsEn: [
      'Remind me to exercise tomorrow at 7 AM',
      'Make me a simple routine for this week',
      "What's the weather in Dhaka today?",
    ],
  ),
  Agent(
    id: 'shongket',
    name: 'সংকেত',
    nameEn: 'Shongket',
    role: 'কোডিং ও প্রোগ্রামিং',
    roleEn: 'Coding and programming',
    blurb: 'কোড লেখা, বাগ ধরা, বোঝানো আর সিস্টেম ডিজাইনে দক্ষ ইঞ্জিনিয়ার।',
    blurbEn: 'An engineer for writing, debugging and explaining code.',
    initial: 'স',
    color: Color(0xFF2F6FB0),
    suggestions: [
      'Flutter-এ কীবোর্ড বন্ধ হয়ে যাওয়ার কারণ কী হতে পারে?',
      'একটা Python স্ক্রিপ্ট লিখে দাও যা CSV ফাইল পড়ে',
      'REST API আর GraphQL-এর পার্থক্য বুঝিয়ে বলো',
    ],
    suggestionsEn: [
      'Why might the keyboard close in a Flutter app?',
      'Write a Python script that reads a CSV file',
      'Explain REST vs GraphQL',
    ],
  ),
  Agent(
    id: 'onnesha',
    name: 'অন্বেষা',
    nameEn: 'Onnesha',
    role: 'গবেষণা ও তথ্য',
    roleEn: 'Research and facts',
    blurb: 'ওয়েবে খুঁজে, উৎস পড়ে সঠিক তথ্য আর লিংক দেয় এমন গবেষক।',
    blurbEn: 'A researcher who searches the web, reads sources and cites them.',
    initial: 'অ',
    color: Color(0xFF7A4FB5),
    suggestions: [
      'আজকের বাংলাদেশের বড় খবরগুলো কী?',
      '২০ হাজার টাকার মধ্যে ভালো ফোন খুঁজে তুলনা করো',
      'পেছনে কাজ করো: বাংলাদেশে ফ্রিল্যান্সিংয়ের সেরা সাইটগুলোর একটা রিপোর্ট',
    ],
    suggestionsEn: [
      "What are today's top news in Bangladesh?",
      'Compare good phones under 20,000 taka',
      'In the background: a report on the best freelancing sites in Bangladesh',
    ],
  ),
  Agent(
    id: 'rongon',
    name: 'রঙ্গন',
    nameEn: 'Rongon',
    role: 'সৃজনশীল সঙ্গী',
    roleEn: 'Creative partner',
    blurb: 'গল্প, কবিতা, ক্যাপশন, নাম আর নতুন আইডিয়ার সঙ্গী।',
    blurbEn: 'A partner for stories, poems, captions, names and ideas.',
    initial: 'র',
    color: Color(0xFFC0392B),
    suggestions: [
      'বর্ষা নিয়ে চার লাইনের একটা কবিতা লেখো',
      'আমার চায়ের দোকানের জন্য দশটা নাম ভাবো',
      'ছোটদের জন্য একটা মজার গল্প বলো',
    ],
    suggestionsEn: [
      'Write a four-line poem about the rain',
      'Think of ten names for my tea shop',
      'Tell a fun story for kids',
    ],
  ),
];

const defaultAgentId = 'mita';

Agent agentById(String? id) =>
    agents.firstWhere((a) => a.id == id, orElse: () => agents.first);

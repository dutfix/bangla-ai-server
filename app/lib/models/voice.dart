/// A Bangla voice from the phone's speech engine: Google's "Speech Services
/// by Google" on Android. Free, built into the phone, nothing to download
/// beyond Google's own Bangla voice data.
enum VoiceGender { female, male }

class VoiceOption {
  const VoiceOption({
    required this.name,
    required this.locale,
    this.network = false,
    this.quality = '',
    this.gender,
  });

  /// The engine's voice id, e.g. bn-bd-x-ban-local.
  final String name;

  /// BCP-47 locale, e.g. bn-BD.
  final String locale;

  /// Needs internet (Google's "network" voices sound a little better).
  final bool network;

  /// The engine's quality label, e.g. high or very high.
  final String quality;

  /// Only set when the engine reports it; Google usually does not.
  final VoiceGender? gender;

  bool get india => locale.toLowerCase().startsWith('bn-in');

  /// Builds a voice from one entry of flutter_tts getVoices, or null when it
  /// is not a usable Bangla voice.
  static VoiceOption? fromEngine(Map<dynamic, dynamic> m) {
    final name = '${m['name'] ?? ''}';
    final locale = '${m['locale'] ?? ''}'.replaceAll('_', '-');
    if (name.isEmpty || !locale.toLowerCase().startsWith('bn')) return null;
    final features = '${m['features'] ?? ''}'.toLowerCase();
    final text = '$name $features ${m['gender'] ?? ''}'.toLowerCase();
    return VoiceOption(
      name: name,
      locale: locale,
      network:
          '${m['network_required']}' == '1' ||
          name.toLowerCase().contains('network'),
      quality: '${m['quality'] ?? ''}'.replaceAll('_', ' ').toLowerCase(),
      gender: RegExp(r'\bfemale\b').hasMatch(text)
          ? VoiceGender.female
          : RegExp(r'\bmale\b').hasMatch(text)
          ? VoiceGender.male
          : null,
    );
  }

  /// Whether the engine marked this voice's data as not installed.
  static bool notInstalled(Map<dynamic, dynamic> m) =>
      '${m['features'] ?? ''}'.contains('notInstalled');

  @override
  bool operator ==(Object other) =>
      other is VoiceOption && other.name == name && other.locale == locale;

  @override
  int get hashCode => Object.hash(name, locale);
}

/// Sorts Bangla voices the way the app prefers them: Bangladesh before India,
/// offline (local) before network, then by name.
int compareBanglaVoices(VoiceOption a, VoiceOption b) {
  int rank(VoiceOption v) => (v.india ? 2 : 0) + (v.network ? 1 : 0);
  final r = rank(a).compareTo(rank(b));
  return r != 0 ? r : a.name.compareTo(b.name);
}

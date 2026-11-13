# Bangla AI Admin

The Android admin dashboard for Bangla AI. It signs in with a 6-digit code
emailed to the admin address and edits the server's settings for every user:
the OmniRoute connection, models and prompts (AI tab), voice on/off, phone
voice and cloud voice providers (Voice tab), and shows usage numbers
(Overview tab).

Build: `flutter build apk --release` (the version code must stay above the
last release, so updates install over it).

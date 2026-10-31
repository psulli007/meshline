# Meshline: App Store Connect setup (Peter)

BLOCKED FIRST: the ASC API returns FORBIDDEN_ERROR.PLA_NOT_ACCEPTED for team VB3RRU9AB4.
Peter (Account Holder) must review and accept the updated Program License Agreement at
https://developer.apple.com/account (the bot will not accept agreements). Until then the API
cannot register bundle IDs, app groups, or profiles, and TestFlight uploads will fail.

After that, the bot registers bundle IDs com.hellofaro.meshline and
com.hellofaro.meshline.ShareExtension (App Groups: group.com.hellofaro.meshline).

Then in App Store Connect > Apps > + > New App:
- Platforms: iOS
- Name: Meshline (fallback if taken: Meshline Offline Chat)
- Primary Language: English (U.S.)
- Bundle ID: com.hellofaro.meshline
- SKU: meshline-ios-001
- User Access: Full Access

/// The privacy policy shown inside the app (LEG-1). The same text is
/// published at [privacyPolicyUrl] from `docs/privacy.md`; keep the two in
/// step (a test compares them).
///
/// It describes version 1.0: ads through Google AdMob with Google's consent
/// form, progress saved on the device only, no analytics, no accounts, no
/// purchases. Update it BEFORE shipping any feature that changes what data
/// leaves the phone (LEG-2).
const String privacyPolicyUrl =
    'https://southicarus.github.io/probe-dash/privacy.html';

const String privacyPolicyUpdated = '11 October 2026';

/// Title and paragraphs, in order.
const List<(String, String)> privacyPolicySections = [
  (
    'In short',
    'Probe Dash has no accounts and does not ask for your name, email, '
        'contacts, photos or location. Your game progress stays on your '
        'phone. The game shows ads through Google AdMob, and Google collects '
        'some data from your device to do that.',
  ),
  (
    'What stays on your phone',
    'Your crystals, upgrades, best distance, run count and settings are '
        'saved in a file on your device. They are not sent to us or to '
        'anyone else. Uninstalling the game deletes them.',
  ),
  (
    'Ads and what Google collects',
    'Ads are provided by Google AdMob. To show ads, limit how often you see '
        'them and prevent fraud, Google\'s software in the game collects your '
        'device\'s advertising ID, IP address (which shows your approximate '
        'region), device and app information, and how you interact with ads. '
        'Google acts on this data under its own privacy policy: '
        'https://policies.google.com/privacy. How Google uses data from apps '
        'that use its services: '
        'https://policies.google.com/technologies/partner-sites.',
  ),
  (
    'Your choices',
    'In the European Economic Area, the United Kingdom and Switzerland the '
        'game asks for your consent before loading ads, and you can change '
        'your choice at any time under Settings > Privacy choices. On any '
        'Android phone you can reset or delete your advertising ID in the '
        'phone\'s Settings > Privacy > Ads. Watching an ad for a reward is '
        'always optional.',
  ),
  (
    'Children',
    'Probe Dash is not directed at children under 13, and ads are limited '
        'to content rated for teens or younger audiences.',
  ),
  (
    'What we do not do',
    'We do not sell your data, we do not run our own analytics in this '
        'version, and we do not receive the data Google collects in a form '
        'that identifies you.',
  ),
  (
    'Changes',
    'If a later version collects more (for example anonymous play '
        'statistics), this policy will be updated first and the date above '
        'will change.',
  ),
  (
    'Contact',
    'Questions or requests: open an issue at '
        'https://github.com/SouthIcarus/probe-dash/issues or use the '
        'developer contact shown on the game\'s Google Play page.',
  ),
];

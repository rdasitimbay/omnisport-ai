import 'dart:convert';

/// Cached Smart ID credential for offline display.
/// Stored as a plain Map in Hive box 'smart_id_cache' — no TypeAdapter needed.
class SmartIdCredential {
  final String athleteUid;
  final String token;
  final String smartIdNum;
  final bool isEligible;
  final int expMs;
  final int cachedAtMs;
  final String fullName;
  final String category;
  final String photoUrl;
  final bool medicalOk;
  final bool paymentOk;
  final String institutionId;

  const SmartIdCredential({
    required this.athleteUid,
    required this.token,
    required this.smartIdNum,
    required this.isEligible,
    required this.expMs,
    required this.cachedAtMs,
    required this.fullName,
    required this.category,
    required this.photoUrl,
    required this.medicalOk,
    required this.paymentOk,
    required this.institutionId,
  });

  bool get isExpired => expMs < DateTime.now().millisecondsSinceEpoch;

  DateTime get expiryDate => DateTime.fromMillisecondsSinceEpoch(expMs);

  /// Decodes the JWT payload without verifying signature (client-side display only).
  static Map<String, dynamic> _decodePayload(String token) {
    final parts = token.split('.');
    if (parts.length < 2) return {};
    try {
      final padded = base64Url.normalize(parts[1]);
      return json.decode(utf8.decode(base64Url.decode(padded))) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  factory SmartIdCredential.fromTokenResponse({
    required String athleteUid,
    required String token,
    required String smartIdNum,
    required bool isEligible,
    required bool medicalOk,
    required bool paymentOk,
    required int expMs,
  }) {
    final payload = _decodePayload(token);
    return SmartIdCredential(
      athleteUid:    athleteUid,
      token:         token,
      smartIdNum:    smartIdNum,
      isEligible:    isEligible,
      expMs:         expMs,
      cachedAtMs:    DateTime.now().millisecondsSinceEpoch,
      fullName:      payload['fullName']      as String? ?? '',
      category:      payload['category']      as String? ?? '',
      photoUrl:      payload['photoUrl']       as String? ?? '',
      medicalOk:     medicalOk,
      paymentOk:     paymentOk,
      institutionId: payload['institutionId'] as String? ?? '',
    );
  }

  factory SmartIdCredential.fromMap(Map<String, dynamic> m) => SmartIdCredential(
    athleteUid:    m['athleteUid']    as String? ?? '',
    token:         m['token']         as String? ?? '',
    smartIdNum:    m['smartIdNum']    as String? ?? '',
    isEligible:    m['isEligible']    as bool?   ?? false,
    expMs:         m['expMs']         as int?    ?? 0,
    cachedAtMs:    m['cachedAtMs']    as int?    ?? 0,
    fullName:      m['fullName']      as String? ?? '',
    category:      m['category']      as String? ?? '',
    photoUrl:      m['photoUrl']      as String? ?? '',
    medicalOk:     m['medicalOk']     as bool?   ?? false,
    paymentOk:     m['paymentOk']     as bool?   ?? false,
    institutionId: m['institutionId'] as String? ?? '',
  );

  Map<String, dynamic> toMap() => {
    'athleteUid':    athleteUid,
    'token':         token,
    'smartIdNum':    smartIdNum,
    'isEligible':    isEligible,
    'expMs':         expMs,
    'cachedAtMs':    cachedAtMs,
    'fullName':      fullName,
    'category':      category,
    'photoUrl':      photoUrl,
    'medicalOk':     medicalOk,
    'paymentOk':     paymentOk,
    'institutionId': institutionId,
  };
}

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Ortam degiskenlerini okur.
///
/// Kaynak onceligi:
/// 1) `--dart-define=YONETICI_SIFRE_HASH=...` (derleme aninda gomulur)
/// 2) `String.fromEnvironment` ile tanimli degerler
///
/// NOT: Bir mobil APK icin gomulu degerler gizli DEGILDIR; APK
/// decompile edildiginde gorunur. Bu yuzden sifre dogrulamasi asil
/// olarak Functions tarafinda yapilir, buradaki deger sadece
/// cevrimdisi (offline) yedek yoldur.
class UygulamaAyarlari {
  UygulamaAyarlari._();

  /// Firestore'da saklanan yonetici sifresinin SHA-256 ozeti.
  static const String varsayilanSifreHash = String.fromEnvironment(
    'YONETICI_SIFRE_HASH',
    defaultValue: '',
  );

  /// Sifre dogrulama sunucusu (Cloud Function) adresi.
  /// Bos ise cevrimdisi mod calisir.
  static const String sifreDogrulamaUrl = String.fromEnvironment(
    'YONETICI_DOGRULAMA_URL',
    defaultValue: '',
  );

  /// Sunucu dogrulaması kullanilabilir mi?
  static bool get sunucuDogrulamasiAktif => sifreDogrulamaUrl.isNotEmpty;

  /// Girilen sifrenin SHA-256 ozetini uretir (hex, kucuk harf).
  static String sifreOzeti(String sifre) {
    final bytes = utf8.encode(sifre);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Girilen sifre, gomulu ozete uyuyor mu?
  ///
  /// `sifreHash` bos ise `false` doner: kimlik dogrulama
  /// yapilamadan yonetici girisine izin vermek guvenlik acigi olurdu.
  ///
  /// Bos sifre de reddedilir: bir yoneticinin sifresi bos birakildiginda
  /// herkes yonetici olabilirdi.
  static bool sifreDogruMu(String sifre, {String? sifreHash}) {
    // SHA-256 ozeti hex encoding'dir; buyuk/kucuk harf ayni ozeti
    // temsil eder. Karsilastirmadan once normalize edilir.
    final beklenen = (sifreHash ?? varsayilanSifreHash).trim().toLowerCase();
    if (beklenen.isEmpty) return false;
    if (sifre.isEmpty) return false;
    return sifreOzeti(sifre).toLowerCase() == beklenen;
  }

  /// Rastgele onaltilik token uretir (parola sifirlama gibi isler icin).
  static String rastgeleToken({int uzunluk = 32}) {
    final rastgele = Random.secure();
    final baytlar = List<int>.generate(
      uzunluk,
      (_) => rastgele.nextInt(256),
    );
    return base64Url.encode(baytlar);
  }
}
/// Uygulama kimlik bilgileri ve hakkında ekranının veri kaynağı.
///
/// Hakkında ekranında gösterilen sürüm, geliştirici ve kütüphane
/// listesi tek yerde toplanır; sürüm `pubspec.yaml` ile eşleşecek
/// şekilde güncellenmelidir.
class UygulamaBilgisi {
  UygulamaBilgisi._();

  static const String uygulamaAdi = 'Akıllı Takip Sistemi';
  static const String tamAd = 'Çoklu Öğrenci Takip Sistemi';
  static const String surum = '1.0.0';
  static const String yapimNumarasi = '1';
  static const String gelistiren = 'Mehmet Gökdeniz';
  static const String aciklama =
      'Öğrencilere görev atayan, ödev teslimini takip eden ve '
      'onay sürecini yöneten mobil uygulama.';

  /// Hakkında ekranında listelenen açık kaynaklı kütüphaneler.
  ///
  /// Her biri `pubspec.yaml` içindeki gerçek bir bağımlılıktır; lisans
  /// bilgileri paketlerin kendi deposundan gelir.
  static const List<Kutuphane> kutuphaneler = [
    Kutuphane(
      ad: 'Flutter',
      aciklama: 'Çoklu platform arayüz çatısı (Dart).',
      lisans: 'BSD-3-Clause',
    ),
    Kutuphane(
      ad: 'Firebase Core',
      aciklama: 'Firebase istemci SDK ana paketi.',
      lisans: 'BSD-3-Clause',
    ),
    Kutuphane(
      ad: 'Cloud Firestore',
      aciklama: 'Gerçek zamanlı NoSQL belge veritabanı.',
      lisans: 'Apache-2.0',
    ),
    Kutuphane(
      ad: 'Firebase Cloud Messaging',
      aciklama: 'Cihazlara anlık bildirim gönderimi.',
      lisans: 'Apache-2.0',
    ),
    Kutuphane(
      ad: 'geolocator',
      aciklama: 'Konum servislerine erişim ve konum takibi.',
      lisans: 'Apache-2.0',
    ),
    Kutuphane(
      ad: 'shared_preferences',
      aciklama: 'Kalıcı anahtar-değer saklama.',
      lisans: 'BSD-3-Clause',
    ),
    Kutuphane(
      ad: 'url_launcher',
      aciklama: 'Dış bağlantı ve harita uygulamalarını açma.',
      lisans: 'BSD-3-Clause',
    ),
    Kutuphane(
      ad: 'image_picker',
      aciklama: 'Galeriden ve kameradan görsel seçimi.',
      lisans: 'BSD-3-Clause',
    ),
    Kutuphane(
      ad: 'local_auth',
      aciklama: 'Biyometrik ve cihaz kimliği doğrulama.',
      lisans: 'BSD-3-Clause',
    ),
    Kutuphane(
      ad: 'flutter_local_notifications',
      aciklama: 'Yerel bildirim kanalı ve bildirim gösterme.',
      lisans: 'MIT',
    ),
    Kutuphane(
      ad: 'crypto',
      aciklama: 'SHA-256 gibi kriptografik özet hesapları.',
      lisans: 'BSD-3-Clause',
    ),
    Kutuphane(
      ad: 'http',
      aciklama: 'HTTP istekleri (şifre doğrulama servisi).',
      lisans: 'BSD-3-Clause',
    ),
  ];
}

/// Hakkında ekranında gösterilen tek bir kütüphane kaydı.
class Kutuphane {
  final String ad;
  final String aciklama;
  final String lisans;

  const Kutuphane({
    required this.ad,
    required this.aciklama,
    required this.lisans,
  });
}
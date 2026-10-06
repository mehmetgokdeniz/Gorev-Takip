import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/bildirim.dart';

/// Bildirim altyapısını tek noktadan yönetir.
///
/// Sorumlulukları:
///   - Android bildirim kanalını oluşturmak
///   - FCM token'ını kullanıcı belgesine yazmak (çoklu cihaz desteği)
///   - Uygulama içi bildirim listesini okumak / okundu işaretlemek
///   - Ön plandayken gelen push'u yerel bildirim olarak göstermek
class BildirimServisi {
  BildirimServisi._();

  static final BildirimServisi instance = BildirimServisi._();

  /// `functions/index.js` içindeki `channelId` ile BIREBIR ayni olmali.
  ///
  /// Farkli bir deger yazilirsa Android bildirimi bu kanala düşmez ve
  /// uygulama acilista olusturulmus kanala sessizce gomulur.
  static const String kanalId = 'gorev_bildirimleri';
  static const String kanalAdi = 'Görev Bildirimleri';
  static const String kanalAciklama =
      'Yeni görev, onay bekleyen ödev ve onaylanan ödev bildirimleri.';

  // Yönetici panelinde kullanılan sabit belge.
  static const String yoneticiKoleksiyon = 'ayarlar';
  static const String yoneticiBelge = 'yonetici';
  static const String ogrenciKoleksiyon = 'ogrenciler';
  static const String tokensAltKoleksiyon = 'tokens';
  static const String bildirimlerAltKoleksiyon = 'bildirimler';

  static FlutterLocalNotificationsPlugin? _yerelBildirimler;

  /// Ekranların dispose olduğunda iptal ettiği token yenileme abonelikleri.
  ///
  /// `tokenYenilemesiniDinle` her panel açılışında yeni bir abonelik
  /// kuruyordu; kayıt tutulmadığı için eskileri ömür boyu açık kalıyor,
  /// her oturum değişiminde birikiyordu. Singleton olan bu servis
  /// ekranlardan bağımsız yaşadığı için abonelikler burada toplanır.
  ///
  /// Anahtar, token'ın yazıldığı belgedir: aynı belge için ikinci bir
  /// dinleyici kurulmaz.
  final Map<String, StreamSubscription<String>> _tokenAbonelikleri = {};

  /// Ekran `dispose()` olduğunda çağrılır.
  void abonelikleriIptalEt() {
    for (final StreamSubscription<String> abonelik in _tokenAbonelikleri.values) {
      abonelik.cancel();
    }
    _tokenAbonelikleri.clear();
  }

  /// Android bildirim kanalını oluşturur ve ön plan bildirimlerini hazırlar.
  ///
  /// Neden gerekli: Android 8+ her uygulamanın bildirim göndermek için
  /// bir kanala ihtiyaci vardir. Kanal bir kez kurulduktan sonra
  /// `importance` degeri KULLANICI TARAFINDAN degistirilemez; bu yuzden
  /// bastan `Importance.high` ile kurulmalidir. Aksi halde bildirimler
  /// sessizce gomulur ve kullanici hicbir sey gormez.
  Future<void> kanalKur() async {
    try {
      _yerelBildirimler ??= FlutterLocalNotificationsPlugin();
      final FlutterLocalNotificationsPlugin yerel = _yerelBildirimler!;

      const AndroidNotificationChannel kanal = AndroidNotificationChannel(
        kanalId,
        kanalAdi,
        description: kanalAciklama,
        importance: Importance.high,
      );

      await yerel
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(kanal);

      debugPrint('Bildirim kanalı oluşturuldu: $kanalId');
    } catch (e) {
      debugPrint('Bildirim kanalı oluşturulamadı: $e');
    }
  }

/// Uygulama ön plandayken gelen push'u sistem bildirimi olarak gösterir.
  ///
  /// Firebase, uygulama ön plandayken gelen `notification` payload'ını
  /// Android bildirimi olarak OTOMATİK göstermez. Bu yüzden `onMessage`
  /// içinde elle gösterilmesi gerekir.
  ///
  /// Dokunma davranışını FCM yönetir: `notification` payload'ı taşıyan
  /// mesajlarda sistem, uygulamayı açarken `onMessageOpenedApp` tetikler.
  Future<void> onPlandaGoster(RemoteMessage mesaj) async {
    final RemoteNotification? bildirim = mesaj.notification;
    if (bildirim == null) return;

    try {
      final FlutterLocalNotificationsPlugin? yerel = _yerelBildirimler;
      if (yerel == null) return;

      await yerel.show(
        bildirim.hashCode,
        bildirim.title ?? 'Bildirim',
        bildirim.body ?? '',
        NotificationDetails(
          android: AndroidNotificationDetails(
            kanalId,
            kanalAdi,
            channelDescription: kanalAciklama,
            importance: Importance.high,
            priority: Priority.high,
            styleInformation: BigTextStyleInformation(bildirim.body ?? ''),
          ),
        ),
        payload: jsonEncode(mesaj.data),
      );
    } catch (e) {
      debugPrint('Ön plan bildirimi gösterilemedi: $e');
    }
  }

  /// Bildirim verisi geldiğinde çağrılır; hangi ekrana gidileceğini döner.
  ///
  /// Değer `gorevId` içeriyorsa görev detay ekranı hedeflenir, aksi
  /// halde bildirim listesi açılır.
  static Map<String, String> veriHaritasiniCoz(Map<String, dynamic> veri) {
    return {
      'tur': veri['tur'] as String? ?? '',
      'gorevId': veri['gorevId'] as String? ?? '',
      'ogrenciId': veri['ogrenciId'] as String? ?? '',
    };
  }

  // ------------------------------------------------------------
  // TOKEN KAYDI
  // ------------------------------------------------------------

  /// Cihazın FCM token'ını verilen kullanıcı belgesine yazar.
  ///
  /// Belge yolu yönetici için `ayarlar/yonetici`, öğrenci için
  /// `ogrenciler/{id}` olur. Token yenilendiğinde aynı işlem
  /// tekrar çalışır (eski token'lar Functions tarafından temizlenir).
  Future<void> tokeniKaydet(String token, String belgeYolu, String belgeId) async {
    try {
      await FirebaseFirestore.instance
          .collection(belgeYolu)
          .doc(belgeId)
          .collection(tokensAltKoleksiyon)
          .doc(token)
          .set({
        'olusturma': FieldValue.serverTimestamp(),
        'platform': Platform.isAndroid ? 'android' : 'ios',
      }, SetOptions(merge: true));
      debugPrint("Bildirim token kaydedildi: $belgeYolu/$belgeId");
    } catch (e) {
      debugPrint("Token kaydedilemedi: $e");
    }
  }

  /// Cihazın güncel token'ını alıp kaydeder.
  Future<void> tokeniAlVeKaydet(String belgeYolu, String belgeId) async {
    try {
      final String? token = await FirebaseMessaging.instance.getToken();
      if (token != null && token.isNotEmpty) {
        await tokeniKaydet(token, belgeYolu, belgeId);
      }
    } catch (e) {
      debugPrint("FCM token alınamadı: $e");
    }
  }

  /// Token yenilendiğinde dinlemeyi başlatır.
  void tokenYenilemesiniDinle(String belgeYolu, String belgeId) {
    final String anahtar = '$belgeYolu/$belgeId';
    if (_tokenAbonelikleri.containsKey(anahtar)) return;

    _tokenAbonelikleri[anahtar] =
        FirebaseMessaging.instance.onTokenRefresh.listen(
      (String token) => tokeniKaydet(token, belgeYolu, belgeId),
      onError: (Object e) => debugPrint("Token yenileme hatası: $e"),
    );
  }

  /// Bildirim izni ister (zaten verilmişse sessizce geçer).
  Future<void> izinIste() async {
    try {
      await FirebaseMessaging.instance.requestPermission(alert: true, badge: true, sound: true);
    } catch (e) {
      debugPrint("Bildirim izni alınamadı: $e");
    }
  }

  // ------------------------------------------------------------
  // UYGULAMA İÇİ BİLDİRİM LİSTESİ
  // ------------------------------------------------------------

  /// Kullanıcının bildirim akışı (en yeni önce).
  Stream<List<Bildirim>> bildirimleriIzle(
    String belgeYolu, String belgeId, {
    BildirimTuru? turVarsayilan,
  }) {
    return FirebaseFirestore.instance
        .collection(belgeYolu)
        .doc(belgeId)
        .collection(bildirimlerAltKoleksiyon)
        .orderBy('zaman', descending: true)
        .limit(100)
        .snapshots()
        .map((QuerySnapshot<Map<String, dynamic>> snapshot) => snapshot.docs
            .map((doc) => Bildirim.dokumandan(doc, turVarsayilan: turVarsayilan))
            .toList(growable: false));
  }

  /// Okunmamış bildirim sayısı (rozet için).
  Stream<int> okunmamisSayisi(String belgeYolu, String belgeId) {
    return FirebaseFirestore.instance
        .collection(belgeYolu)
        .doc(belgeId)
        .collection(bildirimlerAltKoleksiyon)
        .where('okundu', isEqualTo: false)
        .snapshots()
        .map((QuerySnapshot<Map<String, dynamic>> snapshot) => snapshot.docs.length);
  }

  /// Bir bildirimi okundu olarak işaretler.
  Future<void> okunduIsaretle(String belgeYolu, String belgeId, Bildirim bildirim) async {
    if (bildirim.okundu) return;
    try {
      await FirebaseFirestore.instance
          .collection(belgeYolu)
          .doc(belgeId)
          .collection(bildirimlerAltKoleksiyon)
          .doc(bildirim.id)
          .update({'okundu': true});
    } catch (e) {
      debugPrint("Bildirim okundu işaretlenemedi: $e");
    }
  }

  /// Tüm bildirimleri okundu sayar.
  Future<void> tumunuOkunduIsaretle(String belgeYolu, String belgeId) async {
    try {
      final QuerySnapshot<Map<String, dynamic>> snapshot = await FirebaseFirestore.instance
          .collection(belgeYolu)
          .doc(belgeId)
          .collection(bildirimlerAltKoleksiyon)
          .where('okundu', isEqualTo: false)
          .get();

      if (snapshot.docs.isEmpty) return;

      final WriteBatch batch = FirebaseFirestore.instance.batch();
      for (final QueryDocumentSnapshot<Map<String, dynamic>> doc in snapshot.docs) {
        batch.update(doc.reference, {'okundu': true});
      }
      await batch.commit();
    } catch (e) {
      debugPrint("Bildirimler toplu işaretlenemedi: $e");
    }
  }
}
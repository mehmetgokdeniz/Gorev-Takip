import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../models/bildirim.dart';

/// Bildirim altyapısını tek noktadan yönetir.
///
/// Sorumlulukları:
///   - FCM token'ını kullanıcı belgesine yazmak (çoklu cihaz desteği)
///   - Uygulama içi bildirim listesini okumak / okundu işaretlemek
///   - Gelen push bildiriminin hangi ekrana götürdüğünü çözmek
class BildirimServisi {
  BildirimServisi._();

  static final BildirimServisi instance = BildirimServisi._();

  // Yönetici panelinde kullanılan sabit belge.
  static const String yoneticiKoleksiyon = 'ayarlar';
  static const String yoneticiBelge = 'yonetici';
  static const String ogrenciKoleksiyon = 'ogrenciler';
  static const String tokensAltKoleksiyon = 'tokens';
  static const String bildirimlerAltKoleksiyon = 'bildirimler';

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
  Stream<List<Bildirim>> bildirimleriIzle(String belgeYolu, String belgeId) {
    return FirebaseFirestore.instance
        .collection(belgeYolu)
        .doc(belgeId)
        .collection(bildirimlerAltKoleksiyon)
        .orderBy('zaman', descending: true)
        .limit(100)
        .snapshots()
        .map((QuerySnapshot<Map<String, dynamic>> snapshot) => snapshot.docs
            .map(Bildirim.dokumandan)
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
import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import '../models/bildirim.dart';
import '../screens/bildirimler_ekrani.dart';
import '../screens/gorev_detay_ekrani.dart';
import 'bildirim_servisi.dart';

/// Bildirim dokunma (tap) yönlendirmesini tek noktadan yönetir.
///
/// Üç giriş noktası vardır ve üçü de aynı kararı verir:
///   - Uygulama arka plandayken dokunuldu   (`onMessageOpenedApp`)
///   - Uygulama kapalıyken dokunuldu, sonra açıldı (`getInitialMessage`)
///   - Uygulama ön plandayken bildirim geldi  (`onMessage` → SnackBar)
///
/// Nihai hedef daima aynı: `gorevId` varsa görev detay ekranı,
/// yoksa bildirim listesi.
class BildirimYonlendirici {
  BildirimYonlendirici._();

  static final BildirimYonlendirici instance = BildirimYonlendirici._();

  /// Global messenger anahtarı, SnackBar'lar için.
  static final GlobalKey<ScaffoldMessengerState> messengerAnahtari =
      GlobalKey<ScaffoldMessengerState>();

  /// Global navigator anahtarı, bildirimden ekran açmak için.
  static final GlobalKey<NavigatorState> navigatorAnahtari =
      GlobalKey<NavigatorState>();

  /// Bildirimin ait olduğu belgeyi hatırlar; bildirimden ekran
  /// açabilmek için gerekir (navigator üzerinden gidilirken bilinir).
  String? _aktifBelgeYolu;
  String? _aktifBelgeId;

  /// Yönetici mi öğrenci mi — onay butonu doğru ekranda görünsün.
  bool _yoneticiModu = false;

  /// Uygulama açılışında (veya panel değişiminde) aktif kullanıcıyı bildirir.
  void aktifKullaniciyiAyarla({
    required String belgeYolu,
    required String belgeId,
    required bool yoneticiModu,
  }) {
    _aktifBelgeYolu = belgeYolu;
    _aktifBelgeId = belgeId;
    _yoneticiModu = yoneticiModu;
  }

  /// Arka plan mesaj işleyicisi.
  ///
  /// Firebase bu fonksiyonu ayrı bir izole isolate içinde çalıştırır;
  /// ekran açılmaz, yalnızca bildirim kaydı oluşmuştur.
  @pragma('vm:entry-point')
  static Future<void> arkaPlanIsleyici(RemoteMessage message) async {
    debugPrint('Arka planda bildirim alındı: ${message.messageId}');
  }

  /// Uygulama ön plandayken bildirim geldiğinde SnackBar gösterir.
  ///
  /// SnackBar'daki "Aç" düğmesi de doğrudan görev detayına gider;
  /// kullanıcı listeye uğramadan ödevi görebilir.
  void onMesaj(RemoteMessage message) {
    final RemoteNotification? bildirim = message.notification;
    final ScaffoldMessengerState? messenger = messengerAnahtari.currentState;
    if (bildirim == null || messenger == null) return;

    messenger.showSnackBar(
      SnackBar(
        content: Text('${bildirim.title ?? 'Bildirim'}\n${bildirim.body ?? ''}'),
        backgroundColor: const Color(0xFF9C27B0),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: 'Aç',
          textColor: Colors.white,
          onPressed: () => mesajiYonlendir(message.data),
        ),
      ),
    );
  }

  /// Arka plandayken dokunulan bildirimi yönlendirir.
  void onMesajAcildi(RemoteMessage message) => mesajiYonlendir(message.data);

  /// Uygulama kapalıyken bildirimden açıldıysa işlenir.
  ///
  /// Uygulama henüz çizilmemiş olabilir; bu yüzden iş, ilk kare
  /// bittikten sonra `geriCekilenBildirim` üzerinden tekrar oynatılır.
  void onIlkMesaj(RemoteMessage? message) {
    if (message == null) return;
    geriCekilenBildirim = message.data;
  }

  /// `getInitialMessage` ile gelen bildirim, ilk kareden sonra işlenir.
  Map<String, dynamic>? geriCekilenBildirim;

  /// İlk kare bittikten sonra çağrılır.
  void ilkKaredenSonraIsle() {
    final Map<String, dynamic>? veri = geriCekilenBildirim;
    geriCekilenBildirim = null;
    if (veri != null) mesajiYonlendir(veri);
  }

  /// Bildirim veri haritasını hedef ekrana çevirir.
  void mesajiYonlendir(Map<String, dynamic> hamVeri) {
    final Map<String, String> veri = BildirimServisi.veriHaritasiniCoz(hamVeri);
    final String gorevId = veri['gorevId'] ?? '';

    // Kullanıcı henüz giriş yapmamışsa ekran açacak bağlam yoktur;
    // bildirim kaydı Firestore'da durduğu için giriş sonrası listede görünür.
    if (_aktifBelgeId == null) {
      debugPrint('Bildirim yönlendirilemedi: aktif kullanıcı yok. gorevId=$gorevId');
      return;
    }

    final NavigatorState? navigator = navigatorAnahtari.currentState;
    if (navigator == null) {
      debugPrint('Bildirim yönlendirilemedi: navigator hazır değil.');
      return;
    }

    if (gorevId.isEmpty) {
      _bildirimListesiniAc(navigator);
      return;
    }

    _gorevDetayiniAc(navigator, gorevId);
  }

  void _gorevDetayiniAc(NavigatorState navigator, String gorevId) {
    // Üst üste ekran açmayı önle: aynı göreve ikinci kez dokunulursa
    // mevcut detay ekranının üstüne yeni bir tane yığılmasın.
    if (_aktifEkranGorevId == gorevId && navigator.canPop()) {
      navigator.pop();
    }
    _aktifEkranGorevId = gorevId;

    navigator.push(
      MaterialPageRoute(
        builder: (context) => GorevDetayEkrani(
          gorevId: gorevId,
          onayVerilebilir: _yoneticiModu,
        ),
      ),
    );
  }

  void _bildirimListesiniAc(NavigatorState navigator) {
    final String yol = _aktifBelgeYolu!;
    final String id = _aktifBelgeId!;
    navigator.push(
      MaterialPageRoute(
        builder: (context) => BildirimlerEkrani(
          belgeYolu: yol,
          belgeId: id,
          onayVerilebilir: _yoneticiModu,
        ),
      ),
    );
  }

  /// Açık olan detay ekranının görev kimliği.
  String? _aktifEkranGorevId;

  /// Bir öğrenci bildirimini okundu işaretleyip görev detayını açar.
  Future<void> bildirimiAc(Bildirim bildirim, BuildContext benzeri) async {
    await BildirimServisi.instance.okunduIsaretle(
      _aktifBelgeYolu!,
      _aktifBelgeId!,
      bildirim,
    );
    mesajiYonlendir({
      'tur': bildirim.tur.kod,
      'gorevId': bildirim.gorevId,
      'ogrenciId': bildirim.ogrenciId,
    });
  }

  /// Bildirim türüne göre kullanıcıya gösterilecek kısa bilgi.
  static String turAciklamasi(BildirimTuru tur) => switch (tur) {
        BildirimTuru.gorevAtanldi => 'Yeni bir görev atandı.',
        BildirimTuru.onayaGonderildi => 'Bir ödev onaya gönderildi.',
        BildirimTuru.onaylandi => 'Ödevin onaylandı.',
      };
}
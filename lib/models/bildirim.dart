import 'package:cloud_firestore/cloud_firestore.dart';

/// Uygulama içi bildirimin türü.
///
/// Cloud Functions ile paylaşılan sözleşmedir: `functions/index.js`
/// içindeki `TUR` nesnesiyle değerler birebir aynı olmalıdır.
enum BildirimTuru {
  gorevAtanldi,
  onayaGonderildi,
  onaylandi;

  /// Push bildiriminin `data` haritasındaki `tur` değeri.
  String get kod => switch (this) {
        BildirimTuru.gorevAtanldi => 'gorev_atanldi',
        BildirimTuru.onayaGonderildi => 'onay_bekliyor',
        BildirimTuru.onaylandi => 'onaylandi',
      };

  static BildirimTuru koddan(String? kod) => switch (kod) {
        'onay_bekliyor' => BildirimTuru.onayaGonderildi,
        'onaylandi' => BildirimTuru.onaylandi,
        _ => BildirimTuru.gorevAtanldi,
      };

  String get etiket => switch (this) {
        BildirimTuru.gorevAtanldi => 'Yeni görev',
        BildirimTuru.onayaGonderildi => 'Onaya gönderildi',
        BildirimTuru.onaylandi => 'Onaylandı',
      };
}

/// Firestore'da saklanan tek bir bildirim kaydı.
///
/// Kaynak: `{koleksiyon}/{belge}/bildirimler/{bildirimId}`
/// (öğrenci için `ogrenciler/{id}`, yönetici için `ayarlar/yonetici`)
class Bildirim {
  final String id;
  final BildirimTuru tur;
  final String baslik;
  final String govde;

  /// Tıklandığında açılacak görevin kimliği.
  final String gorevId;

  /// Bildirimin ait olduğu öğrenci (yönetici bildirimlerinde dolu).
  final String ogrenciId;

  final bool okundu;
  final DateTime? zaman;

  const Bildirim({
    required this.id,
    required this.tur,
    required this.baslik,
    required this.govde,
    this.gorevId = '',
    this.ogrenciId = '',
    this.okundu = false,
    this.zaman,
  });

  factory Bildirim.dokumandan(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    final Map<String, dynamic> veri = snapshot.data() ?? const {};
    return Bildirim(
      id: snapshot.id,
      tur: BildirimTuru.koddan(veri['tur'] as String?),
      baslik: veri['baslik'] as String? ?? '',
      govde: veri['govde'] as String? ?? '',
      gorevId: veri['gorevId'] as String? ?? '',
      ogrenciId: veri['ogrenciId'] as String? ?? '',
      okundu: veri['okundu'] as bool? ?? false,
      zaman: (veri['zaman'] as Timestamp?)?.toDate(),
    );
  }

  /// Bildirimin ait olduğu görev dokümanının yolu.
  ///
  /// Görev silinmişse (ya da bildirim bozuk veri içeriyorsa) `null`
  /// döner; çağıran taraf detay ekranı açmaz.
  String? get gorevYolu {
    if (gorevId.isEmpty) return null;
    return 'gorevler/$gorevId';
  }

  Bildirim kopyala({bool? okundu}) => Bildirim(
        id: id,
        tur: tur,
        baslik: baslik,
        govde: govde,
        gorevId: gorevId,
        ogrenciId: ogrenciId,
        okundu: okundu ?? this.okundu,
        zaman: zaman,
      );
}
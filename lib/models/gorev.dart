import 'package:cloud_firestore/cloud_firestore.dart';

/// Görevin yaşam döngüsündeki durumu.
///
/// Firestore'daki `gorevler` belgelerinde `durum` alanı olarak
/// saklanır. Cloud Functions bu değerlerin değişimini izleyip
/// bildirim üretir.
enum GorevDurumu {
  atanlandi,
  onayBekliyor,
  onaylandi;

  /// Firestore'da saklanan değer.
  String get kod => switch (this) {
        GorevDurumu.atanlandi => 'atanlandi',
        GorevDurumu.onayBekliyor => 'onay_bekliyor',
        GorevDurumu.onaylandi => 'onaylandi',
      };

  /// Kullanıcıya gösterilen etiket.
  String get etiket => switch (this) {
        GorevDurumu.atanlandi => 'Yapılıyor',
        GorevDurumu.onayBekliyor => 'Onay Bekliyor',
        GorevDurumu.onaylandi => 'Onaylandı',
      };

  /// Firestore'dan gelen değeri çözer. Bilinmeyen veya eksik
  /// değerler `atanlandi` sayılır (geriye dönük uyum).
  static GorevDurumu koddan(String? kod) => switch (kod) {
        'onay_bekliyor' => GorevDurumu.onayBekliyor,
        'onaylandi' => GorevDurumu.onaylandi,
        _ => GorevDurumu.atanlandi,
      };
}

/// `gorevler` koleksiyonundaki tek bir görev kaydı.
///
/// Uygulama genelinde görevler ham `Map` olarak gezilirdi; bu model
/// alan okumasını tek yerde toplar ve başlangıç/son tarih gibi
/// alanların her ekranda aynı yorumlanmasını garanti eder.
class Gorev {
  final String id;
  final String ogrenciId;
  final String baslik;
  final String aciklama;
  final GorevDurumu durum;
  final DateTime? baslangicTarihi;
  final DateTime? sonTarihi;
  final List<String> resimYollari;
  final DateTime? olusturmaZamani;

  const Gorev({
    required this.id,
    required this.ogrenciId,
    required this.baslik,
    this.aciklama = '',
    this.durum = GorevDurumu.atanlandi,
    this.baslangicTarihi,
    this.sonTarihi,
    this.resimYollari = const [],
    this.olusturmaZamani,
  });

  factory Gorev.dokumandan(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    final Map<String, dynamic> veri = snapshot.data() ?? const {};
    return Gorev(
      id: snapshot.id,
      ogrenciId: veri['ogrenciId'] as String? ?? '',
      baslik: veri['baslik'] as String? ?? '',
      aciklama: veri['aciklama'] as String? ?? '',
      durum: GorevDurumu.koddan(veri['durum'] as String?),
      baslangicTarihi: (veri['baslangicTarihi'] as Timestamp?)?.toDate(),
      sonTarihi: (veri['sonTarih'] as Timestamp?)?.toDate(),
      resimYollari: (veri['resimYollari'] as List<dynamic>? ?? const [])
          .map((dynamic e) => e.toString())
          .toList(growable: false),
      olusturmaZamani: (veri['zaman'] as Timestamp?)?.toDate(),
    );
  }

  /// Bildirim listesinde tek satırda gösterilecek özet.
  ///
  /// Baslik, durum ve iki tarihi birlikte verir: kullanıcı bildirimi
  /// okumadan hangi ödevin ne zaman başlayıp ne zaman biteceğini görür.
  String get ozet {
    final StringBuffer sb = StringBuffer();
    sb.write('$baslik — ${durum.etiket}');

    final String? aralik = tarihAraligiMetni;
    if (aralik != null) {
      sb.write(' • $aralik');
    }
    return sb.toString();
  }

  /// "05.01.2026 – 12.01.2026" gibi aralık metni.
  ///
  /// Tarihlerden yalnız biri varsa yalnız o gösterilir; ikisi de
  /// yoksa `null` döner.
  String? get tarihAraligiMetni {
    final String? bas = baslangicTarihi == null ? null : tarihBicimle(baslangicTarihi!);
    final String? son = sonTarihi == null ? null : tarihBicimle(sonTarihi!);
    if (bas == null && son == null) return null;
    if (bas == null) return 'Son tarih: $son';
    if (son == null) return 'Başlangıç: $bas';
    return '$bas – $son';
  }

  /// Son tarih geçti mi? (Tarih gün sonunda biter.)
  bool get sonTarihGecti {
    final DateTime? son = sonTarihi;
    if (son == null) return false;
    final DateTime bugun = DateTime.now();
    final DateTime sonGun = DateTime(son.year, son.month, son.day);
    final DateTime bugunGun = DateTime(bugun.year, bugun.month, bugun.day);
    return sonGun.isBefore(bugunGun);
  }

  static String tarihBicimle(DateTime tarih) {
    final String gun = tarih.day.toString().padLeft(2, '0');
    final String ay = tarih.month.toString().padLeft(2, '0');
    return '$gun.$ay.${tarih.year}';
  }

  @override
  String toString() => 'Gorev($id, $baslik, ${durum.kod})';
}

/// `gorevler` koleksiyonuna yeni görev yazarken kullanılan alan adları.
///
/// Yazma işlemleri tek yerden geçerse, alan adı değişikliklerinde
/// okuyan tarafın hepsini güncellemek gerekmez.
class GorevAlanlari {
  GorevAlanlari._();

  static const String ogrenciId = 'ogrenciId';
  static const String baslik = 'baslik';
  static const String durum = 'durum';
  static const String aciklama = 'aciklama';
  static const String resimYollari = 'resimYollari';
  static const String baslangicTarihi = 'baslangicTarihi';
  static const String sonTarihi = 'sonTarih';
  static const String zaman = 'zaman';
}
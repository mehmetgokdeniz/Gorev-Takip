import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Base64 ve uzak görselleri çözüp önbelleğe alan yardımcı.
///
/// Sorun: fotoğraflar Firestore'da base64 metin olarak saklanıyor ve
/// `Image.memory(base64Decode(...))` her `build()` çağrısında yeniden
/// çözülüyordu. Liste kaydırıldıkça aynı görsel defalarca decode
/// edildiği için akıcılık düşüyordu.
///
/// Burada çözüm şu: metin bir kez `base64Decode` edilir, çıkan baytlar
/// `ui.decodeImageFromList` ile bir kez `ui.Image`'a dönüştürülür ve
/// sonuç LRU mantığıyla saklanır. Sonraki karelerde `RawImage` doğrudan
/// önbellekteki `ui.Image`'ı çizer.
class GorselOnbellek {
  GorselOnbellek._();

  /// Mevcut `ui.Image` → yol eşleşmesi. `LinkedHashMap` sıralı olduğu için
  /// ilk giren ilk çıkar mantığıyla en eskiyi atmak kolaydır.
  static final LinkedHashMap<String, ui.Image> _onbellek =
      LinkedHashMap<String, ui.Image>();

  /// Çözüm süreci devam eden yollar. Aynı yol için iki kez decode
  /// istemeyi engeller (hızlı kaydırmada `Future` üst üste binmesin).
  static final Map<String, Future<ui.Image>> _surecler = {};

  /// Üst sınır. Ortalama bir ödev fotoğrafı ~150 KB; 200 fotoğraf
  /// yaklaşık 30 MB'a denk gelir. Sınır aşılınca en eski atılır.
  static const int _azamiGorsel = 200;

  /// Liste küçük görsellerinde 240 px genişlik yeterli; büyük ölçek
  /// (dokunup büyütme) tam çözümü `gorseliBuyut` içinde yapar.
  static const double _onizlemeGenislik = 240;

  /// Önbellekte hazır mı? (Senkron çizim için).
  static bool icinde(String yol) => _onbellek.containsKey(yol);

  /// Önbellekteki `ui.Image`, yoksa `null`.
  static ui.Image? gorsel(String yol) => _onbellek[yol];

  /// Görseli çözüp önbelleğe alır. Aynı yol için çağrılanlar
  /// aynı `Future`'ı paylaşır.
  static Future<ui.Image> yukle(String yol) {
    final Future<ui.Image>? mevcut = _surecler[yol];
    if (mevcut != null) return mevcut;

    final Completer<ui.Image> tamamlayici = Completer<ui.Image>();
    _surecler[yol] = tamamlayici.future;

    () async {
      try {
        final Uint8List baytlar = base64Decode(yol);
        final ui.Codec kodek = await ui.instantiateImageCodec(
          baytlar,
          targetWidth: _onizlemeGenislik.round(),
        );
        final ui.FrameInfo kare = await kodek.getNextFrame();
        final ui.Image gorsel = kare.image;
        _sakla(yol, gorsel);
        tamamlayici.complete(gorsel);
      } catch (hata) {
        // Bozuk base64 veya desteklenmeyen biçim: çağıran taraf
        // kırık görsel ikonu gösterir.
        _surecler.remove(yol);
        tamamlayici.completeError(hata);
        return;
      }
      _surecler.remove(yol);
    }();

    return tamamlayici.future;
  }

  /// Tam boyutlu çözüm (dokunup büyütme ekranı için). Önbelleğe yazılmaz.
  static Future<ui.Image> tamBoyutYukle(String yol) async {
    final Uint8List baytlar = base64Decode(yol);
    final ui.Codec kodek = await ui.instantiateImageCodec(baytlar);
    final ui.FrameInfo kare = await kodek.getNextFrame();
    return kare.image;
  }

  static void _sakla(String yol, ui.Image gorsel) {
    // Aynı yol yeniden kaydediliyorsa eskiyi çıkar.
    _onbellek.remove(yol);
    _onbellek[yol] = gorsel;

    // ATILAN GÖRSELLER BİLEREK SERBEST BIRAKILMAZ.
    //
    // `ui.Image.dispose()` o an halen çizimde olan bir görsel üzerinde
    // çağrılırsa Flutter "image has been disposed" hatası verir: RawImage
    // elindeki referansı bir sonraki karede kullanmaya devam eder.
    // Referans düşürülür; artık ulaşılamayan `ui.Image` nesnesi
    // çöp toplayıcıya gider. 200 görsel sınırı, uygulamanın
    // gerçek kullanımında (öğrenci başına birkaç ödev) hiçbir zaman
    // bu yola girmez.
    while (_onbellek.length > _azamiGorsel) {
      _onbellek.remove(_onbellek.keys.first);
    }
  }

  /// Her şeyi siler. Ekranların kapandığı noktada çağrılabilir.
  static void temizle() => _onbellek.clear();
}

/// Uzak (http) ve base64 görselleri tek widget'ta gösterir.
///
/// Uzak görseller `Image.network`'in kendi önbelleğini kullanır; onlar
/// için ek iş gerekmez. Base64 olanlar [GorselOnbellek] üzerinden çözülür.
class OnbellekliGorsel extends StatelessWidget {
  final String yol;
  final double? genislik;
  final double? yukseklik;
  final BoxFit fit;

  const OnbellekliGorsel({
    super.key,
    required this.yol,
    this.genislik,
    this.yukseklik,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    if (yol.isEmpty) {
      return _BozukGorsel(genislik: genislik, yukseklik: yukseklik);
    }

    if (yol.startsWith('http')) {
      return Image.network(
        yol,
        width: genislik,
        height: yukseklik,
        fit: fit,
        errorBuilder: (_, __, ___) =>
            _BozukGorsel(genislik: genislik, yukseklik: yukseklik),
      );
    }

    // Önbellekte hazırsa senkron çiz: kare gecikmesi olmaz.
    final ui.Image? onbellekteki = GorselOnbellek.gorsel(yol);
    if (onbellekteki != null) {
      return RawImage(
        image: onbellekteki,
        width: genislik,
        height: yukseklik,
        fit: fit,
      );
    }

    return FutureBuilder<ui.Image>(
      future: GorselOnbellek.yukle(yol),
      builder: (context, anlik) {
        final ui.Image? gorsel = anlik.data;
        if (gorsel != null) {
          return RawImage(
            image: gorsel,
            width: genislik,
            height: yukseklik,
            fit: fit,
          );
        }
        if (anlik.hasError) {
          return _BozukGorsel(genislik: genislik, yukseklik: yukseklik);
        }
        return SizedBox(
          width: genislik,
          height: yukseklik,
          child: const Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      },
    );
  }
}

class _BozukGorsel extends StatelessWidget {
  final double? genislik;
  final double? yukseklik;

  const _BozukGorsel({this.genislik, this.yukseklik});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: genislik,
      height: yukseklik,
      child: const Center(child: Icon(Icons.broken_image_outlined)),
    );
  }
}
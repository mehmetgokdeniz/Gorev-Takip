import 'package:flutter_test/flutter_test.dart';
import 'package:gorev_takibi/config/uygulama_ayarlari.dart';
import 'package:gorev_takibi/models/gorev.dart';

void main() {
  group('Sifre dogrulama', () {
    test('ozet 64 karakter hex olmalidir', () {
      final ozet = UygulamaAyarlari.sifreOzeti('herhangi bir sifre');
      expect(ozet.length, 64);
      expect(ozet, matches(RegExp(r'^[a-f0-9]{64}$')));
    });

    test('ayni sifre her zaman ayni ozeti vermeli', () {
      // Gercek sifre veya ozeti test dosyasinda TUTULMAZ; ozet
      // algoritmasinin deterministik oldugu dogrulanir.
      const sifre = 'ornek-sifre-degeri';
      expect(
        UygulamaAyarlari.sifreOzeti(sifre),
        UygulamaAyarlari.sifreOzeti(sifre),
      );
    });

    test('bos hash tanimliysa hicbir sifre kabul edilmemeli', () {
      // Kimlik dogrulama yapilamiyorsa yonetici girisine izin
      // vermek guvenlik acigi olurdu.
      final sonuc = UygulamaAyarlari.sifreDogruMu(
        'herhangi bir sifre',
        sifreHash: '',
      );
      expect(sonuc, isFalse);
    });

    test('eslesen hash ile dogru sifre kabul edilir', () {
      // Ozet hesaplanarak uretilir; sabit bir deger kaynak kodda tutulmaz.
      const sifre = 'test-sifresi-1234';
      final hash = UygulamaAyarlari.sifreOzeti(sifre);

      expect(UygulamaAyarlari.sifreDogruMu(sifre, sifreHash: hash), isTrue);
      expect(UygulamaAyarlari.sifreDogruMu('yanlis sifre', sifreHash: hash), isFalse);
    });

    test('buyuk/kucuk harf farki sonucu degistirmemeli', () {
      const sifre = 'test-sifresi-1234';
      final hash = UygulamaAyarlari.sifreOzeti(sifre).toUpperCase();

      expect(
        UygulamaAyarlari.sifreDogruMu(sifre, sifreHash: hash),
        isTrue,
        reason: 'Hash once kucuk harfe cevrilmeli.',
      );
    });

    test('bos sifre ASLA kabul edilmemeli', () {
      // Bos sifrenin SHA-256 ozeti:
      // e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
      const bosSifreOzeti =
          'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';

      expect(
        UygulamaAyarlari.sifreDogruMu('', sifreHash: bosSifreOzeti),
        isFalse,
        reason: 'Yonetici sifresi bos birakilmissa herkes girebilirdi.',
      );

      expect(
        UygulamaAyarlari.sifreDogruMu('', sifreHash: 'a' * 64),
        isFalse,
      );
    });
  });

  group('Ortam degiskenleri', () {
    test('dogrulama URL i bos ise sunucu dogrulamasi kapali olmali', () {
      // Test ortaminda --dart-define verilmedigi icin beklenen davranis.
      expect(UygulamaAyarlari.sunucuDogrulamasiAktif, isFalse);
    });

    test('rastgele token yeterince uzun ve benzersiz olmali', () {
      final a = UygulamaAyarlari.rastgeleToken();
      final b = UygulamaAyarlari.rastgeleToken();
      expect(a.length, greaterThan(30));
      expect(a, isNot(b));
    });
  });

  group('Gorev durumu', () {
    test('kodlari Firestore ile eslesmeli', () {
      expect(GorevDurumu.atanlandi.kod, 'atanlandi');
      expect(GorevDurumu.onayBekliyor.kod, 'onay_bekliyor');
      expect(GorevDurumu.onaylandi.kod, 'onaylandi');
    });

    test('bilinmeyen kod varsayilana dusmeli', () {
      expect(GorevDurumu.koddan('bilinmeyen'), GorevDurumu.atanlandi);
      expect(GorevDurumu.koddan(null), GorevDurumu.atanlandi);
    });
  });

  group('Gorev tarih bicimleme', () {
    test('gun ve ay iki haneli olmali', () {
      expect(Gorev.tarihBicimle(DateTime(2026, 1, 5)), '05.01.2026');
      expect(Gorev.tarihBicimle(DateTime(2026, 12, 31)), '31.12.2026');
    });
  });

  group('Gorev tarih araligi', () {
    Gorev ornekGorev({DateTime? baslangic, DateTime? son}) => Gorev(
          id: 'g1',
          ogrenciId: 'o1',
          baslik: 'Test',
          baslangicTarihi: baslangic,
          sonTarihi: son,
        );

    test('iki tarih varsa aralik gosterilmeli', () {
      final metin = ornekGorev(
        baslangic: DateTime(2026, 1, 5),
        son: DateTime(2026, 1, 12),
      ).tarihAraligiMetni;
      expect(metin, '05.01.2026 – 12.01.2026');
    });

    test('yalnizca son tarih varsa etiketlenmeli', () {
      final metin = ornekGorev(son: DateTime(2026, 1, 12)).tarihAraligiMetni;
      expect(metin, 'Son tarih: 12.01.2026');
    });

    test('yalnizca baslangic varsa etiketlenmeli', () {
      final metin = ornekGorev(baslangic: DateTime(2026, 1, 5)).tarihAraligiMetni;
      expect(metin, 'Başlangıç: 05.01.2026');
    });

    test('hicbiri yoksa null donmeli', () {
      expect(ornekGorev().tarihAraligiMetni, isNull);
    });
  });

  group('Gorev son tarih kontrolu', () {
    test('gecmis tarih isaretlenmeli', () {
      final gorev = Gorev(
        id: 'g1',
        ogrenciId: 'o1',
        baslik: 'Test',
        sonTarihi: DateTime.now().subtract(const Duration(days: 1)),
      );
      expect(gorev.sonTarihGecti, isTrue);
    });

    test('gelecek tarih isaretlenmemeli', () {
      final gorev = Gorev(
        id: 'g1',
        ogrenciId: 'o1',
        baslik: 'Test',
        sonTarihi: DateTime.now().add(const Duration(days: 1)),
      );
      expect(gorev.sonTarihGecti, isFalse);
    });

    test('tarih yoksa gecmis sayilmamali', () {
      final gorev = Gorev(id: 'g1', ogrenciId: 'o1', baslik: 'Test');
      expect(gorev.sonTarihGecti, isFalse);
    });
  });

  group('Gorev ozeti', () {
    test('baslik, durum ve tarih birlikte gorunmeli', () {
      final gorev = Gorev(
        id: 'g1',
        ogrenciId: 'o1',
        baslik: 'Matematik Odevi',
        baslangicTarihi: DateTime(2026, 1, 5),
        sonTarihi: DateTime(2026, 1, 12),
      );
      expect(gorev.ozet, 'Matematik Odevi — Yapılıyor • 05.01.2026 – 12.01.2026');
    });
  });
}
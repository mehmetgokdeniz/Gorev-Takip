import 'package:flutter_test/flutter_test.dart';
import 'package:gorev_takibi/config/uygulama_ayarlari.dart';
import 'package:gorev_takibi/models/bildirim.dart';
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

  group('Gorev tarih araligi uyumu', () {
    Gorev ornekGorev({DateTime? baslangic, DateTime? son}) => Gorev(
          id: 'g1',
          ogrenciId: 'o1',
          baslik: 'Test',
          baslangicTarihi: baslangic,
          sonTarihi: son,
        );

    test('araliktaki her gun dahil olmali', () {
      final gorev = ornekGorev(
        baslangic: DateTime(2026, 1, 5),
        son: DateTime(2026, 1, 12),
      );

      expect(gorev.tarihAraliginaDahilMi(DateTime(2026, 1, 5)), isTrue,
          reason: 'Baslangic gunu dahil olmali.');
      expect(gorev.tarihAraliginaDahilMi(DateTime(2026, 1, 8)), isTrue);
      expect(gorev.tarihAraliginaDahilMi(DateTime(2026, 1, 12)), isTrue,
          reason: 'Son gun dahil olmali.');
    });

    test('aralik disindaki gunler haric olmali', () {
      final gorev = ornekGorev(
        baslangic: DateTime(2026, 1, 5),
        son: DateTime(2026, 1, 12),
      );

      expect(gorev.tarihAraliginaDahilMi(DateTime(2026, 1, 4)), isFalse);
      expect(gorev.tarihAraliginaDahilMi(DateTime(2026, 1, 13)), isFalse);
      expect(gorev.tarihAraliginaDahilMi(DateTime(2026, 6, 1)), isFalse);
    });

    test('gunun saati onemsiz olmali', () {
      final gorev = ornekGorev(
        baslangic: DateTime(2026, 1, 5, 8, 30),
        son: DateTime(2026, 1, 12, 23, 45),
      );

      expect(gorev.tarihAraliginaDahilMi(DateTime(2026, 1, 5, 0, 0)), isTrue,
          reason: 'Sabah 08:30 baslayan gorev, o gunun 00:00inda da gorunmeli.');
    });

    test('yalnizca son tarih varsa o gun sayilmali', () {
      // Eski kayitlarda baslangic tarihi yoktur; tek tarih kullanilir.
      final gorev = ornekGorev(son: DateTime(2026, 1, 12));
      expect(gorev.tarihAraliginaDahilMi(DateTime(2026, 1, 12)), isTrue);
      expect(gorev.tarihAraliginaDahilMi(DateTime(2026, 1, 11)), isFalse);
    });

    test('hicbir tarih yoksa hicbir gun sayilmamali', () {
      expect(ornekGorev().tarihAraliginaDahilMi(DateTime(2026, 1, 12)), isFalse);
    });

    test('ters aralik veri hatasinda tek gun sayilmali', () {
      // Baslangic son tarihten sonra gelmisse coklu gunlu aralik olusturulamaz.
      final gorev = ornekGorev(
        baslangic: DateTime(2026, 1, 12),
        son: DateTime(2026, 1, 5),
      );

      expect(gorev.tarihAraliginaDahilMi(DateTime(2026, 1, 12)), isTrue);
      expect(gorev.tarihAraliginaDahilMi(DateTime(2026, 1, 8)), isFalse);
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

  group('Bildirim turu cozumleme', () {
    test('bilinen kodlar dogru tur vermeli', () {
      expect(BildirimTuru.koddanVeya('onay_bekliyor', BildirimTuru.gorevAtanldi),
          BildirimTuru.onayaGonderildi);
      expect(BildirimTuru.koddanVeya('onaylandi', BildirimTuru.gorevAtanldi),
          BildirimTuru.onaylandi);
      expect(BildirimTuru.koddanVeya('gorev_atanldi', BildirimTuru.onayaGonderildi),
          BildirimTuru.gorevAtanldi);
    });

    test('tur alani eksik yonetici bildirimi onaya gonderilmis sayilmali', () {
      // `yoneticiyeBildir` `tur` degerini gecirmedigi donemde yazilan
      // kayitlarda alan yoktur. Yonetici ekrani varsayilan olarak
      // "Onay bekleyen" filtresinde acildigi icin bu kayitlar aksi halde
      // gizleniyordu.
      expect(BildirimTuru.koddanVeya(null, BildirimTuru.onayaGonderildi),
          BildirimTuru.onayaGonderildi);
      expect(BildirimTuru.koddanVeya('', BildirimTuru.onayaGonderildi),
          BildirimTuru.onayaGonderildi);
    });

    test('varsayilan tur bilinmeyen kodlari da yakalamali', () {
      expect(BildirimTuru.koddanVeya('bozuk_kod', BildirimTuru.onayaGonderildi),
          BildirimTuru.onayaGonderildi);
    });

    test('koddan varsayilani degistirmemeli', () {
      // Ogrenci tarafinda varsayilan tur verilmedigi icin eski davranis
      // korunur: bilinmeyen kod "yeni gorev" sayilir.
      expect(BildirimTuru.koddan(null), BildirimTuru.gorevAtanldi);
      expect(BildirimTuru.koddan('onay_bekliyor'), BildirimTuru.onayaGonderildi);
    });
  });
}
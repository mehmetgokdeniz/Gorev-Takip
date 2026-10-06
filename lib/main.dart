import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import 'package:local_auth/local_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'config/uygulama_ayarlari.dart';
import 'models/gorev.dart';
import 'services/bildirim_servisi.dart';
import 'services/bildirim_yonlendirici.dart';
import 'services/gorsel_onbellek.dart';
import 'widgets/bildirim_rozeti.dart';
import 'screens/gorev_detay_ekrani.dart';
import 'screens/hakkinda_ekrani.dart';
import 'screens/splash_ekrani.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'firebase_options.dart';

// Bildirim dokunma yönlendirmesi tek katmanda toplandı.
// _tokeniKaydet, _foregroundBildirimGoster ve _globalAnahtar buradan gelir.
final BildirimServisi _bildirim = BildirimServisi.instance;
final BildirimYonlendirici _yonlendirici = BildirimYonlendirici.instance;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Android bildirim kanalı. Kanal `importance: high` olmadan kurulursa
  // bildirimler sessizce gömülür ve kullanıcı hiçbir şey görmez.
  // Kanal bir kez kurulduktan sonra önemi değiştirilemeyeceği için
  // uygulama her açılışta bu çağrı yapılır (idempotenttir).
  await _bildirim.kanalKur();

  FirebaseMessaging.onBackgroundMessage(BildirimYonlendirici.arkaPlanIsleyici);

  FirebaseMessaging.onMessage.listen((mesaj) {
    // Ön planda gelen bildirim iki yer gösterir: sistem bildirimi
    // (uygulamayı kapatmadan da görünür) ve uygulama içi SnackBar.
    _bildirim.onPlandaGoster(mesaj);
    _yonlendirici.onMesaj(mesaj);
  });
  FirebaseMessaging.onMessageOpenedApp.listen(_yonlendirici.onMesajAcildi);

  // Uygulama kapalıyken bildirimden açıldıysa veri ilk kareden
  // sonra işlenecek; kullanıcı girişi henüz yapılmamış olabilir.
  _yonlendirici.onIlkMesaj(await FirebaseMessaging.instance.getInitialMessage());

  SharedPreferences prefs = await SharedPreferences.getInstance();
  String? kayitliOgrenciId = prefs.getString('aktif_ogrenci_id');
  bool yoneticiOturumuAcik = prefs.getBool('yonetici_aktif') ?? false;

  Widget baslangicEkrani = const GirisEkrani();
  if (yoneticiOturumuAcik) {
    baslangicEkrani = const YoneticiPaneli();
    _yonlendirici.aktifKullaniciyiAyarla(
      belgeYolu: BildirimServisi.yoneticiKoleksiyon,
      belgeId: BildirimServisi.yoneticiBelge,
      yoneticiModu: true,
    );
  } else if (kayitliOgrenciId != null) {
    baslangicEkrani = OgrenciPaneli(ogrenciId: kayitliOgrenciId);
    _yonlendirici.aktifKullaniciyiAyarla(
      belgeYolu: BildirimServisi.ogrenciKoleksiyon,
      belgeId: kayitliOgrenciId,
      yoneticiModu: false,
    );
  }

  runApp(GorevTakipUygulamasi(
    baslangicEkrani: SplashEkrani(baslangicEkrani: baslangicEkrani),
  ));

  // İlk kare bittikten sonra bekleyen bildirimi işle.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    _yonlendirici.ilkKaredenSonraIsle();
  });
}

class GorevTakipUygulamasi extends StatelessWidget {
  final Widget baslangicEkrani;
  const GorevTakipUygulamasi({super.key, required this.baslangicEkrani});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Çoklu Öğrenci Takip Sistemi',
      scaffoldMessengerKey: BildirimYonlendirici.messengerAnahtari,
      navigatorKey: BildirimYonlendirici.navigatorAnahtari,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0D0F12), // Çok koyu şık füme/siyah
        primaryColor: const Color(0xFF8A2BE2),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF9C27B0),
          secondary: Color(0xFF00E676),
          surface: Color(0xFF161B22), // Modern kart rengi
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF161B22),
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        useMaterial3: true,
      ),
      home: baslangicEkrani,
    );
  }
}

// Yardımcı: Base64 / uzak görsel gösterici.
//
// Önceden `Image.memory(base64Decode(...))` her `build()` çağrısında
// yeniden decode ediyordu; liste kaydırıldıkça aynı fotoğraf onlarca kez
// çözülüyordu. Artık çözüm bir kez yapılıp `GorselOnbellek`'e yazılıyor.
Widget bulutGorselCikar(String base64Str, {double? width, double? height, BoxFit fit = BoxFit.cover}) {
  if (base64Str.isEmpty) {
    return const SizedBox(
      width: 40,
      height: 40,
      child: Icon(Icons.person, size: 40, color: Colors.white70),
    );
  }
  return OnbellekliGorsel(
    yol: base64Str,
    genislik: width,
    yukseklik: height,
    fit: fit,
  );
}

// Görseli Büyütme (Dialog) Fonksiyonu
void gorseliBuyut(BuildContext context, String base64Str) {
  showDialog(
    context: context,
    builder: (context) => Dialog(
      backgroundColor: Colors.black,
      child: InteractiveViewer(
        child: OnbellekliGorsel(yol: base64Str, fit: BoxFit.contain),
      ),
    ),
  );
}

// ==========================================
// 1. GİRİŞ VE ROL SEÇİMİ
// ==========================================
class GirisEkrani extends StatefulWidget {
  const GirisEkrani({super.key});

  @override
  State<GirisEkrani> createState() => _GirisEkraniState();
}

class _GirisEkraniState extends State<GirisEkrani> {
  @override
  void initState() {
    super.initState();
    _bildirimIzniIste();
  }

  Future<void> _bildirimIzniIste() async {
    try {
      await FirebaseMessaging.instance.requestPermission(alert: true, badge: true, sound: true);
    } catch (e) {
      debugPrint("Bildirim izni alınamadı: $e");
    }
  }

  /// Yönetici oturumu açıldığında yönlendiriciyi bilgilendirir.
  ///
  /// Bu çağrı ATLANIRSA bildirimlere dokunmak işe yaramaz: yönlendirici
  /// aktif kullanıcıyı bilmediği için "aktif kullanıcı yok" deyip mesajı
  /// düşürür ve hiçbir ekran açmaz. Giriş ekranındaki HER iki giriş
  /// yolundan (biyometrik ve şifre) sonra çağrılmalıdır.
  void _yoneticiyiEtkinlestir() {
    _yonlendirici.aktifKullaniciyiAyarla(
      belgeYolu: BildirimServisi.yoneticiKoleksiyon,
      belgeId: BildirimServisi.yoneticiBelge,
      yoneticiModu: true,
    );
  }

  /// Öğrenci girişi başarılı olduğunda yönlendiriciyi bilgilendirir.
  void _ogrenciyiEtkinlestir(String ogrenciId) {
    _yonlendirici.aktifKullaniciyiAyarla(
      belgeYolu: BildirimServisi.ogrenciKoleksiyon,
      belgeId: ogrenciId,
      yoneticiModu: false,
    );
  }

  Future<void> _yoneticiGirisAkisi(BuildContext context) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    bool biyometrikAktif = prefs.getBool('biyometrik_aktif') ?? true;

    if (biyometrikAktif) {
      final LocalAuthentication auth = LocalAuthentication();
      try {
        bool canCheck = await auth.canCheckBiometrics || await auth.isDeviceSupported();
        if (canCheck) {
          bool didAuthenticate = await auth.authenticate(
            localizedReason: 'Yönetici paneline girmek için kimliğinizi doğrulayın',
          );
          if (didAuthenticate) {
            await prefs.setBool('yonetici_aktif', true);
            _yoneticiyiEtkinlestir();
            if (context.mounted) {
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const YoneticiPaneli()));
            }
            return;
          }
        }
      } catch (e) {
        // Hata durumunda şifreye düşer
      }
    }
    if (context.mounted) _sifreSorVeGirisYap(context);
  }

  Future<bool> _yoneticiSifresiniDogrula(String sifre) async {
    final String ozet = UygulamaAyarlari.sifreOzeti(sifre);

    // Sunucu dogrulamasi etkinse ve erisilebilirse onu esas al.
    if (UygulamaAyarlari.sunucuDogrulamasiAktif) {
      try {
        final Uri uri = Uri.parse(UygulamaAyarlari.sifreDogrulamaUrl);
        final http.Response yanit = await http
            .post(
              uri,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'sifreOzeti': ozet}),
            )
            .timeout(const Duration(seconds: 10));
        return yanit.statusCode == 200;
      } catch (e) {
        // Sunucuya ulasilamiyorsa asagi dusulur.
        debugPrint("Sunucu dogrulamasi yapilamadi: $e");
      }
    }

    // Cevrimdisi yedek yol: derleme aninda gomulen ozet.
    return UygulamaAyarlari.sifreDogruMu(sifre);
  }

  Future<void> _sifreGirisiniTamamla(
    BuildContext dialogContext,
    BuildContext sayfaContext,
    TextEditingController sifreCtrl,
    ValueNotifier<bool> yukleniyor,
  ) async {
    final String girilen = sifreCtrl.text;
    if (girilen.isEmpty) return;

    yukleniyor.value = true;
    final bool dogru = await _yoneticiSifresiniDogrula(girilen);
    yukleniyor.value = false;

    if (!dialogContext.mounted) return;

    if (!dogru) {
      ScaffoldMessenger.of(sayfaContext).showSnackBar(
        const SnackBar(content: Text('Hatalı Şifre!')),
      );
      return;
    }

    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool('yonetici_aktif', true);
    _yoneticiyiEtkinlestir();

    if (!dialogContext.mounted) return;

    Navigator.pop(dialogContext);
    Navigator.pushReplacement(
      sayfaContext,
      MaterialPageRoute(builder: (context) => const YoneticiPaneli()),
    );
  }

  void _sifreSorVeGirisYap(BuildContext context) {
    final TextEditingController sifreCtrl = TextEditingController();
    final ValueNotifier<bool> sifreGizli = ValueNotifier<bool>(true);
    final ValueNotifier<bool> yukleniyor = ValueNotifier<bool>(false);

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF161B22),
          title: const Text('Yönetici Şifresi', style: TextStyle(fontWeight: FontWeight.bold)),
          content: ValueListenableBuilder<bool>(
            valueListenable: sifreGizli,
            builder: (context, gizli, child) {
              return TextField(
                controller: sifreCtrl,
                obscureText: gizli,
                enabled: !yukleniyor.value,
                decoration: InputDecoration(
                  hintText: "Şifrenizi giriniz",
                  filled: true,
                  fillColor: const Color(0xFF0D0F12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  suffixIcon: IconButton(
                    icon: Icon(gizli ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => sifreGizli.value = !gizli,
                  ),
                ),
                autofocus: true,
                onSubmitted: (_) => _sifreGirisiniTamamla(
                  dialogContext,
                  context,
                  sifreCtrl,
                  yukleniyor,
                ),
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('İptal', style: TextStyle(color: Colors.grey)),
            ),
            ValueListenableBuilder<bool>(
              valueListenable: yukleniyor,
              builder: (context, yukleniyorDurumu, child) {
                return ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurpleAccent, foregroundColor: Colors.white),
                  onPressed: yukleniyorDurumu
                      ? null
                      : () => _sifreGirisiniTamamla(
                            dialogContext,
                            context,
                            sifreCtrl,
                            yukleniyor,
                          ),
                  child: yukleniyorDurumu
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Giriş Yap'),
                );
              },
            ),
          ],
        );
      },
    );
  }

  void _ogrenciIdGirisYapPenceresi(BuildContext context) {
    final TextEditingController idCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF161B22),
          title: const Text('Öğrenci Girişi', style: TextStyle(fontWeight: FontWeight.bold)),
          content: TextField(
            controller: idCtrl,
            decoration: InputDecoration(
              hintText: "Öğrenci ID giriniz",
              filled: true,
              fillColor: const Color(0xFF0D0F12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('İptal', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurpleAccent, foregroundColor: Colors.white),
              onPressed: () async {
                String girilenId = idCtrl.text.trim();
                if (girilenId.isNotEmpty) {
                  var doc = await FirebaseFirestore.instance.collection('ogrenciler').doc(girilenId).get();
                  if (doc.exists) {
                    SharedPreferences prefs = await SharedPreferences.getInstance();
                    await prefs.setString('aktif_ogrenci_id', girilenId);
                    _ogrenciyiEtkinlestir(girilenId);
                    if (dialogContext.mounted) {
                      Navigator.pop(dialogContext);
                      Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => OgrenciPaneli(ogrenciId: girilenId)));
                    }
                  } else {
                    if (dialogContext.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bu ID ile kayıtlı öğrenci bulunamadı!')));
                    }
                  }
                }
              },
              child: const Text('Giriş Yap'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF161B22),
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: Colors.deepPurpleAccent.withValues(alpha: 0.3), blurRadius: 20, spreadRadius: 5)],
                ),
                child: const Icon(Icons.school_rounded, size: 64, color: Colors.deepPurpleAccent),
              ),
              const SizedBox(height: 24),
              const Text('Akıllı Takip Sistemi', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, letterSpacing: 1)),
              const SizedBox(height: 8),
              const Text('Devam etmek için rolünüzü seçin', style: TextStyle(color: Colors.grey, fontSize: 14)),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurpleAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () => _yoneticiGirisAkisi(context),
                  icon: const Icon(Icons.fingerprint),
                  label: const Text('Yönetici Girişi', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.deepPurpleAccent, width: 1.5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () => _ogrenciIdGirisYapPenceresi(context),
                  icon: const Icon(Icons.person, color: Colors.deepPurpleAccent),
                  label: const Text('Öğrenci Girişi', style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 24),
              TextButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const HakkindaEkrani()),
                ),
                icon: const Icon(Icons.info_outline, size: 16),
                label: const Text('Hakkında'),
                style: TextButton.styleFrom(foregroundColor: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==========================================
// 2. YÖNETİCİ PANELİ
// ==========================================
class YoneticiPaneli extends StatefulWidget {
  const YoneticiPaneli({super.key});

  @override
  State<YoneticiPaneli> createState() => _YoneticiPaneliState();
}

class _YoneticiPaneliState extends State<YoneticiPaneli> {
  /// Öğrenci listesi stream'i.
  ///
  /// ÖNEMLİ: Bu stream `build()` içinde oluşturulursa her yeniden
  /// çizimde YENI abonelik kurulur ve eskisi atılır. Asenkron ilk veri
  /// geldiğinde yeniden çizim tetiklenir, bu da tekrar abonelik kurulması
  /// demektir — uygulama sürekli aynı veriyi yeniden ister ve akıcılık
  /// düşer. Tek sefer oluşturup saklamak bu döngüyü keser.
  late final Stream<List<Map<String, dynamic>>> _ogrencilerStream;

  @override
  void initState() {
    super.initState();

    _ogrencilerStream = FirebaseFirestore.instance
        .collection('ogrenciler')
        .snapshots()
        .map((anlik) =>
            anlik.docs.map((d) => <String, dynamic>{
                  ...d.data(),
                  // Belge kimliği `data()` içinde değil; liste anahtarı
                  // ve düzenleme/silme işlemleri için gerekiyor.
                  'id': d.id,
                }).toList());

    // Yönetici oturumu açıldı: bildirim yönlendiricisi burada da
    // bilgilendirilir. Uygulama yeniden başlatıldığında `main()` zaten
    // ayarlıyor, ama bildirimden gelerek panele geçişte buraya düşer.
    _yonlendirici.aktifKullaniciyiAyarla(
      belgeYolu: BildirimServisi.yoneticiKoleksiyon,
      belgeId: BildirimServisi.yoneticiBelge,
      yoneticiModu: true,
    );

    _bildirimTokeniniKaydet();
    _tokenDegisiminiDinle();
  }

  Future<void> _bildirimTokeniniKaydet() async {
    await _bildirim.tokeniAlVeKaydet(
      BildirimServisi.yoneticiKoleksiyon,
      BildirimServisi.yoneticiBelge,
    );
  }

  // Token yenilenirse (uygulama geri yüklenme, cihaz değişimi) yenisini kaydet.
  void _tokenDegisiminiDinle() {
    _bildirim.tokenYenilemesiniDinle(
      BildirimServisi.yoneticiKoleksiyon,
      BildirimServisi.yoneticiBelge,
    );
  }

  @override
  void dispose() {
    // Oturum değiştirirken panel sökülür; token aboneliği de düşsün,
    // yoksa her girişte bir tane daha birikir.
    _bildirim.abonelikleriIptalEt();
    super.dispose();
  }

  Future<void> _cikisYap(BuildContext context) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool('yonetici_aktif', false);
    if (context.mounted) {
      Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const GirisEkrani()), (route) => false);
    }
  }

  void _ayarPenceresiAc(BuildContext context) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    if (!context.mounted) return;
    bool biyometrikDurum = prefs.getBool('biyometrik_aktif') ?? true;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              backgroundColor: const Color(0xFF161B22),
              title: const Text('Yönetici Ayarları'),
              content: SwitchListTile(
                title: const Text('Biyometrik Giriş'),
                subtitle: const Text('Parmak izi doğrulamasını aç/kapat'),
                value: biyometrikDurum,
                onChanged: (bool yeniDeger) async {
                  setStateDialog(() => biyometrikDurum = yeniDeger);
                  await prefs.setBool('biyometrik_aktif', yeniDeger);
                },
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Kapat')),
              ],
            );
          },
        );
      },
    );
  }

  void _ogrenciEkleVeyaDuzenle(BuildContext context, {String? mevcutId, String? mevcutAd, String? mevcutResim}) {
    final TextEditingController idCtrl = TextEditingController(text: mevcutId ?? '');
    final TextEditingController adCtrl = TextEditingController(text: mevcutAd ?? '');
    String base64ResimStr = mevcutResim ?? '';
    bool isEditing = mevcutId != null;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              backgroundColor: const Color(0xFF161B22),
              title: Text(isEditing ? 'Öğrenciyi Düzenle' : 'Yeni Öğrenci Ekle'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!isEditing)
                      TextField(
                        controller: idCtrl,
                        decoration: InputDecoration(hintText: "Öğrenci ID (Örn: ogr1)", filled: true, fillColor: const Color(0xFF0D0F12), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none)),
                      ),
                    if (!isEditing) const SizedBox(height: 12),
                    TextField(
                      controller: adCtrl,
                      decoration: InputDecoration(hintText: "Adı Soyadı", filled: true, fillColor: const Color(0xFF0D0F12), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none)),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.grey.shade800, foregroundColor: Colors.white),
                      onPressed: () async {
                        final XFile? image = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 70);
                        if (image != null) {
                          List<int> bytes = await File(image.path).readAsBytes();
                          setStateDialog(() => base64ResimStr = base64Encode(bytes));
                        }
                      },
                      icon: const Icon(Icons.photo_library),
                      label: const Text('Profil Fotoğrafı Seç'),
                    ),
                    if (base64ResimStr.isNotEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 8.0),
                        child: Text("Fotoğraf Yüklendi ✓", style: TextStyle(color: Colors.greenAccent)),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('İptal', style: TextStyle(color: Colors.grey))),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurpleAccent, foregroundColor: Colors.white),
                  onPressed: () async {
                    String id = isEditing ? mevcutId : idCtrl.text.trim();
                    if (id.isNotEmpty && adCtrl.text.isNotEmpty) {
                      await FirebaseFirestore.instance.collection('ogrenciler').doc(id).set({
                        'ogrenciId': id,
                        'adSoyad': adCtrl.text.trim(),
                        'profilResmi': base64ResimStr,
                        'enlem': 0.0,
                        'boylam': 0.0,
                        'zaman': FieldValue.serverTimestamp(),
                      }, SetOptions(merge: true));
                    }
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  },
                  child: Text(isEditing ? 'Güncelle' : 'Kaydet'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _ogrenciyiSil(BuildContext context, String ogrenciId, String adSoyad) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF161B22),
          title: const Text('Öğrenciyi Sil'),
          content: Text("'$adSoyad' adlı öğrenciyi silmek istediğinize emin misiniz?"),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('İptal', style: TextStyle(color: Colors.grey))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
              onPressed: () async {
                await FirebaseFirestore.instance.collection('ogrenciler').doc(ogrenciId).delete();
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              },
              child: const Text('Sil'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Yönetici Paneli', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF161B22),
        elevation: 0,
        actions: [
          const BildirimRozeti(
            belgeYolu: BildirimServisi.yoneticiKoleksiyon,
            belgeId: BildirimServisi.yoneticiBelge,
            ogrenciGosterilsin: true,
            onayVerilebilir: true,
          ),
          IconButton(icon: const Icon(Icons.settings_outlined), onPressed: () => _ayarPenceresiAc(context)),
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'Hakkında',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const HakkindaEkrani()),
            ),
          ),
          IconButton(icon: const Icon(Icons.person_add_alt_1_outlined), onPressed: () => _ogrenciEkleVeyaDuzenle(context)),
          IconButton(icon: const Icon(Icons.logout, color: Colors.redAccent), onPressed: () => _cikisYap(context)),
        ],
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _ogrencilerStream,
        builder: (context, anlik) {
          if (anlik.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final List<Map<String, dynamic>> ogrenciler = anlik.data ?? const [];
          if (ogrenciler.isEmpty) {
            return const Center(child: Text('Henüz kayıtlı öğrenci yok.', style: TextStyle(color: Colors.grey)));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: ogrenciler.length,
            itemBuilder: (context, index) {
              final Map<String, dynamic> veri = ogrenciler[index];
              final ogrenciId = veri['id'] as String;
              final adSoyad = veri['adSoyad'] ?? 'İsimsiz';
              final profilResmi = veri['profilResmi'] ?? '';

              return Card(
                margin: const EdgeInsets.symmetric(vertical: 8),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 28,
                            backgroundColor: Colors.deepPurple,
                            child: ClipOval(
                              child: SizedBox(width: 56, height: 56, child: bulutGorselCikar(profilResmi, fit: BoxFit.cover)),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(adSoyad, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                                const SizedBox(height: 4),
                                Text("ID: $ogrenciId", style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 24, color: Colors.white10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit_outlined, color: Colors.blueAccent, size: 20),
                                onPressed: () => _ogrenciEkleVeyaDuzenle(context, mevcutId: ogrenciId, mevcutAd: adSoyad, mevcutResim: profilResmi),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                                onPressed: () => _ogrenciyiSil(context, ogrenciId, adSoyad),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              TextButton.icon(
                                style: TextButton.styleFrom(foregroundColor: Colors.tealAccent),
                                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => CanliKonumPaneli(ogrenciId: ogrenciId, ogrenciAdi: adSoyad))),
                                icon: const Icon(Icons.location_on_outlined, size: 18),
                                label: const Text('Konum'),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.deepPurpleAccent,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => OgrenciDetayPaneli(ogrenciId: ogrenciId, ogrenciAdi: adSoyad))),
                                icon: const Icon(Icons.assignment_outlined, size: 18),
                                label: const Text('Görevler'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ==========================================
// 3. CANLI KONUM PANELİ
// ==========================================
class CanliKonumPaneli extends StatefulWidget {
  final String ogrenciId;
  final String ogrenciAdi;

  const CanliKonumPaneli({super.key, required this.ogrenciId, required this.ogrenciAdi});

  @override
  State<CanliKonumPaneli> createState() => _CanliKonumPaneliState();
}

class _CanliKonumPaneliState extends State<CanliKonumPaneli> {
  /// Konum belgesinin stream'i.
  ///
  /// GPS her 10 dakikada bir güncelleme yazdığı için bu ekran sık sık
  /// yeniden çizilir. `build()` içinde kurulan stream her çizimde yeni
  /// abonelik açıp eskisini bırakıyordu; `initState`'e taşındı.
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _ogrenciStream;

  @override
  void initState() {
    super.initState();
    _ogrenciStream = FirebaseFirestore.instance
        .collection('ogrenciler')
        .doc(widget.ogrenciId)
        .snapshots();
  }

  Future<void> _haritadaAc(double enlem, double boylam) async {
    final Uri googleMapsUrl = Uri.parse("https://www.google.com/maps/search/?api=1&query=$enlem,$boylam");
    try {
      await launchUrl(googleMapsUrl, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint("Harita açılamadı: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.ogrenciAdi} - Canlı Konum'), backgroundColor: const Color(0xFF161B22)),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _ogrenciStream,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          var veri = snapshot.data!.data();
          double enlem = (veri?['enlem'] as num?)?.toDouble() ?? 0.0;
          double boylam = (veri?['boylam'] as num?)?.toDouble() ?? 0.0;
          bool konumKapali = (enlem == 0.0 && boylam == 0.0);

          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: const Color(0xFF161B22),
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: (konumKapali ? Colors.redAccent : Colors.tealAccent).withValues(alpha: 0.3), blurRadius: 20)],
                    ),
                    child: Icon(konumKapali ? Icons.location_off : Icons.navigation_rounded, size: 64, color: konumKapali ? Colors.redAccent : Colors.tealAccent),
                  ),
                  const SizedBox(height: 24),
                  Text(widget.ogrenciAdi, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(
                    konumKapali ? "Konum kapalı veya alınamadı." : "GPS Konumu Aktif",
                    style: TextStyle(fontSize: 15, color: konumKapali ? Colors.redAccent : Colors.tealAccent, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 32),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        children: [
                          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("Enlem:", style: TextStyle(color: Colors.grey)), Text(enlem.toStringAsFixed(6), style: const TextStyle(fontWeight: FontWeight.bold))]),
                          const Divider(height: 20, color: Colors.white10),
                          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("Boylam:", style: TextStyle(color: Colors.grey)), Text(boylam.toStringAsFixed(6), style: const TextStyle(fontWeight: FontWeight.bold))]),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  if (!konumKapali)
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                        onPressed: () => _haritadaAc(enlem, boylam),
                        icon: const Icon(Icons.map_rounded),
                        label: const Text('Haritada Aç & Yol Tarifi Al', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ==========================================
// 4. ÖĞRENCİ DETAY PANELİ
// ==========================================
class OgrenciDetayPaneli extends StatefulWidget {
  final String ogrenciId;
  final String ogrenciAdi;

  const OgrenciDetayPaneli({super.key, required this.ogrenciId, required this.ogrenciAdi});

  @override
  State<OgrenciDetayPaneli> createState() => _OgrenciDetayPaneliState();
}

class _OgrenciDetayPaneliState extends State<OgrenciDetayPaneli> {
  String get ogrenciId => widget.ogrenciId;
  String get ogrenciAdi => widget.ogrenciAdi;

  late final CollectionReference<Map<String, dynamic>> _gorevlerKoleksiyonu;

  /// Bildirimler öğrenci belgesinin altında tutulduğu için görev
  /// silinirken o kayıtları da bulmak gerekiyor.
  late final CollectionReference<Map<String, dynamic>> _ogrencilerKoleksiyonu;

  /// Öğrencinin görev listesi. `initState`'te bir kez kurulur; `build()`
  /// içinde kurulursa her yeniden çizimde yeniden abone olunur.
  ///
  /// Görevler stream tarafında `Gorev` modeline çevrilir: `itemBuilder`
  /// saf bir liste okur, belge ayrıştırması yapmaz. Önceden her karede
  /// `Gorev.dokumandan()` çağrılıyordu.
  late final Stream<List<Gorev>> _gorevlerStream;

  /// Onaylanmış bir görevi ve ona bağlı bildirim geçmişini siler.
  ///
  /// Görev silinince öğrencinin bildirim listesinde o göreve ait kayıtlar
  /// kalırdı; tıklandığında "görev mevcut değil" durumuna düşerdi.
  /// Bu yüzden bildirimler ve görev tek bir batch içinde birlikte silinir.
  Future<void> _goreviSil(
    BuildContext context, {
    required String gorevId,
    required String ogrenciId,
    required String baslik,
  }) async {
    final bool? onay = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        title: const Text('Ödevi Sil'),
        content: Text('"$baslik" ödevi kalıcı olarak silinecek. Emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('İptal', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );

    if (onay != true || !context.mounted) return;

    try {
      final DocumentReference<Map<String, dynamic>> gorevRef =
          _gorevlerKoleksiyonu.doc(gorevId);

      // Bildirimler görevin altında değil, öğrencinin belgesinin altında
      // durur (`ogrenciler/{id}/bildirimler`). `gorevId` alanına göre
      // sorgulanıp o göreve ait kayıtlar topluca silinir.
      final CollectionReference<Map<String, dynamic>> bildirimlerKoleksiyonu =
          _ogrencilerKoleksiyonu
              .doc(ogrenciId)
              .collection(BildirimServisi.bildirimlerAltKoleksiyon);

      final QuerySnapshot<Map<String, dynamic>> bildirimler =
          await bildirimlerKoleksiyonu
              .where('gorevId', isEqualTo: gorevId)
              .get();

      final WriteBatch batch = FirebaseFirestore.instance.batch();
      for (final QueryDocumentSnapshot<Map<String, dynamic>> b
          in bildirimler.docs) {
        batch.delete(b.reference);
      }
      batch.delete(gorevRef);
      await batch.commit();

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"$baslik" silindi.')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ödev silinemedi: $e')),
      );
    }
  }

  @override
  void initState() {
    super.initState();

    _gorevlerKoleksiyonu = FirebaseFirestore.instance.collection('gorevler');
    _ogrencilerKoleksiyonu = FirebaseFirestore.instance.collection('ogrenciler');
    _gorevlerStream = _gorevlerKoleksiyonu
        .where('ogrenciId', isEqualTo: ogrenciId)
        .snapshots()
        .map((anlik) {
      final List<Gorev> gorevler = anlik.docs.map(Gorev.dokumandan).toList();
      // Firestore sıralaması olmadan belge sırası değişebilir; en yeni
      // görev üstte kalsın diye istemci tarafında sıralanır. Bu sayede
      // ek bir Firestore index'i gerekmez.
      gorevler.sort((a, b) {
        final DateTime? aZaman = a.olusturmaZamani;
        final DateTime? bZaman = b.olusturmaZamani;
        if (aZaman == null && bZaman == null) return 0;
        if (aZaman == null) return 1;
        if (bZaman == null) return -1;
        return bZaman.compareTo(aZaman);
      });
      return gorevler;
    });
  }

  void _gorevEklePenceresi(BuildContext context) {
    final TextEditingController gorevCtrl = TextEditingController();
    final TextEditingController aciklamaCtrl = TextEditingController();
    DateTime secilenBaslangic = DateTime.now();
    DateTime secilenSon = DateTime.now();

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            String basTarih = Gorev.tarihBicimle(secilenBaslangic);
            String sonTarih = Gorev.tarihBicimle(secilenSon);

            // Bitis, baslangictan once secilirse baslangici one al:
            // boyle bir aralik olusturulamaz.
            if (secilenSon.isBefore(secilenBaslangic)) {
              sonTarih = '$basTarih (başlangıçla aynı gün)';
            }

            return AlertDialog(
              backgroundColor: const Color(0xFF161B22),
              title: Text('$ogrenciAdi için Görev Ekle'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: gorevCtrl,
                      decoration: InputDecoration(hintText: "Görev başlığı yazın", filled: true, fillColor: const Color(0xFF0D0F12), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none)),
                      autofocus: true,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: aciklamaCtrl,
                      maxLines: 2,
                      decoration: InputDecoration(hintText: "Açıklama (isteğe bağlı)", filled: true, fillColor: const Color(0xFF0D0F12), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none)),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Başlangıç', style: TextStyle(color: Colors.grey, fontSize: 12)),
                              Text(basTarih, style: const TextStyle(fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.grey.shade800, foregroundColor: Colors.white),
                          onPressed: () async {
                            DateTime? picked = await showDatePicker(
                              context: context,
                              initialDate: secilenBaslangic,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2030),
                            );
                            if (picked != null) setStateDialog(() => secilenBaslangic = picked);
                          },
                          child: const Text('Seç'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Son Tarih', style: TextStyle(color: Colors.grey, fontSize: 12)),
                              Text(sonTarih, style: const TextStyle(fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.grey.shade800, foregroundColor: Colors.white),
                          onPressed: () async {
                            DateTime? picked = await showDatePicker(
                              context: context,
                              initialDate: secilenSon,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2030),
                            );
                            if (picked != null) setStateDialog(() => secilenSon = picked);
                          },
                          child: const Text('Seç'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('İptal', style: TextStyle(color: Colors.grey))),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurpleAccent, foregroundColor: Colors.white),
                  onPressed: () async {
                    if (gorevCtrl.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Görev başlığı boş olamaz!')),
                      );
                      return;
                    }

                    // Son tarih, baslangictan once gelirse baslangiс tarihe sabitlenir.
                    final DateTime bas = secilenBaslangic;
                    final DateTime son = secilenSon.isBefore(secilenBaslangic) ? secilenBaslangic : secilenSon;

                    await _gorevlerKoleksiyonu.add({
                      GorevAlanlari.ogrenciId: ogrenciId,
                      GorevAlanlari.baslik: gorevCtrl.text.trim(),
                      GorevAlanlari.durum: GorevDurumu.atanlandi.kod,
                      GorevAlanlari.aciklama: aciklamaCtrl.text.trim(),
                      GorevAlanlari.resimYollari: <String>[],
                      GorevAlanlari.baslangicTarihi: Timestamp.fromDate(bas),
                      GorevAlanlari.sonTarihi: Timestamp.fromDate(son),
                      GorevAlanlari.zaman: FieldValue.serverTimestamp(),
                    });
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  },
                  child: const Text('Ata'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('$ogrenciAdi - Görevler'), backgroundColor: const Color(0xFF161B22)),
      body: StreamBuilder<List<Gorev>>(
        stream: _gorevlerStream,
        builder: (context, anlik) {
          if (anlik.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          final List<Gorev> gorevler = anlik.data ?? const [];
          if (gorevler.isEmpty) return const Center(child: Text('Bu öğrenciye henüz görev atanmamış.', style: TextStyle(color: Colors.grey)));

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: gorevler.length,
            itemBuilder: (context, index) {
              final Gorev gorev = gorevler[index];
              final String docId = gorev.id;
              final GorevDurumu durum = gorev.durum;
              String aciklama = gorev.aciklama;
              List<String> resimYollari = gorev.resimYollari;
              String? aralik = gorev.tarihAraligiMetni;

              Color durumRengi = Colors.orange;
              String durumMetni = "Devam Ediyor";
              if (durum == GorevDurumu.onayBekliyor) {
                durumRengi = Colors.blueAccent;
                durumMetni = "Onay Bekliyor!";
              } else if (durum == GorevDurumu.onaylandi) {
                durumRengi = Colors.greenAccent;
                durumMetni = "Onaylandı ✓";
              }

              return Card(
                margin: const EdgeInsets.symmetric(vertical: 6),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => GorevDetayEkrani(
                        gorevId: docId,
                        onGorev: gorev,
                        onayVerilebilir: true,
                      ),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(gorev.baslik, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("Durum: $durumMetni", style: TextStyle(color: durumRengi, fontWeight: FontWeight.bold)),
                                if (aralik != null) Text(aralik, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                              ],
                            ),
                          ),
                          trailing: durum == GorevDurumu.onayBekliyor
                              ? ElevatedButton(
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                                  onPressed: () => _gorevlerKoleksiyonu.doc(docId).update({'durum': GorevDurumu.onaylandi.kod}),
                                  child: const Text('Onayla'),
                                )
                              : durum == GorevDurumu.onaylandi
                                  // Silme yalnız onaylanan görevlerde: onay
                                  // bekleyen veya yapılmayan bir ödev yanlışlıkla
                                  // silinmemeli.
                                  ? IconButton(
                                      tooltip: 'Onaylanan ödevi sil',
                                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 22),
                                      onPressed: () => _goreviSil(
                                        context,
                                        gorevId: docId,
                                        ogrenciId: ogrenciId,
                                        baslik: gorev.baslik,
                                      ),
                                    )
                                  : Icon(Icons.hourglass_top, color: durumRengi),
                        ),
                        if (aciklama.isNotEmpty) ...[
                          const Divider(color: Colors.white10),
                          Text("Öğrenci Notu: $aciklama", style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.white70)),
                        ],
                        if (resimYollari.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          const Text("Gönderilen Fotoğraflar:", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                          const SizedBox(height: 6),
                          SizedBox(
                            height: 80,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              itemCount: resimYollari.length,
                              itemBuilder: (context, imgIdx) {
                                return Padding(
                                  padding: const EdgeInsets.only(right: 8.0),
                                  child: GestureDetector(
                                    onTap: () => gorseliBuyut(context, resimYollari[imgIdx]),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: SizedBox(width: 80, child: bulutGorselCikar(resimYollari[imgIdx], fit: BoxFit.cover)),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.deepPurpleAccent,
        onPressed: () => _gorevEklePenceresi(context),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}

// ==========================================
// 5. ÖĞRENCİ PANELİ
// ==========================================
class OgrenciPaneli extends StatefulWidget {
  final String ogrenciId;
  const OgrenciPaneli({super.key, required this.ogrenciId});

  @override
  State<OgrenciPaneli> createState() => _OgrenciPaneliState();
}

class _OgrenciPaneliState extends State<OgrenciPaneli> {
  final CollectionReference<Map<String, dynamic>> _gorevlerKoleksiyonu =
      FirebaseFirestore.instance.collection('gorevler');
  final CollectionReference<Map<String, dynamic>> _ogrencilerKoleksiyonu =
      FirebaseFirestore.instance.collection('ogrenciler');

  static const Duration gpsGuncellemeAraligi = Duration(minutes: 10);

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _ogrenciSubscription;

  /// Takvim renklendirmesini besleyen görev aboneliği.
  ///
  /// `_gorevlerStream` ayrıca `build()` içindeki `StreamBuilder` tarafından
  /// da dinlenir; bu ikinci abonelik kalvemi `_sonGorevler` doldurur.
  /// Kayıt tutulmadığı takdirde `dispose()` sonrası da açık kalır ve her
  /// oturum değişiminde birikiyordu — oturum değiştirme kasmasının
  /// başlıca nedeni buydu.
  StreamSubscription<List<Gorev>>? _gorevlerAbonelik;
  Timer? _gpsZamanlayici;

  /// Görev listesi — `initState`'te bir kez kurulur, `build()` içinde değil.
  ///
  /// Önceden `build()` gövdesinde oluşturuluyordu; her yeniden çizimde
  /// yeni bir Firestore aboneliği kurulup eskisi atılıyordu.
  /// Stream verisi `List<Gorev>` olarak döner: belge ayrıştırması kare
  /// başına değil, veri güncellemesi başına bir kez yapılır.
  late final Stream<List<Gorev>> _gorevlerStream;

  /// Öğrenci belgesi (ad, profil fotoğrafı, silinme durumu).
  ///
  /// Önceden hem `initState` içindeki silinme dinleyicisi hem de `build()`
  /// içindeki `StreamBuilder` aynı belgeyi ayrı ayrı dinliyordu.
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _ogrenciStream;

  DateTime secilenTarih = DateTime.now();
  late PageController _pageController;
  int _currentMonthIndex = 0;

  /// Takvimde gösterilen yıl.
  ///
  /// Önceden `secilenTarih.year`'a bağlıydı ve kullanıcı yılı
  /// değiştiremiyordu. Artık ayrı bir alan; AppBar'daki yıl başlığı
  /// açılır listeden seçim yapıyor.
  int _currentYear = DateTime.now().year;

  /// true iken görev listesi tüm görevleri gösterir (takvim gününe göre
  /// filtrelemez). Kullanıcı eski bir görevi aradığında veya bildirimden
  /// geldiğinde bu mod kullanılır.
  ///
  /// BAŞLANGIÇ DEĞERİ `false`: takvim açılışta görünür olmalıydı.
  /// Önceden `true` idi ve ekran açılır açılmaz takvim yerine
  /// "Tüm görevler gösteriliyor" bandı çıkıyordu.
  bool _tumGorevlerMi = false;

  /// Bir ayın kaç haftalık satır gerektirdiğini döner (5 veya 6).
  ///
  /// Ayın 1'i hangi güne denk geliyorsa ve kaç gün var, birlikte
  /// belirler. `DateTime.weekday` PZT=1 ... PAZ=7 olduğu için boş
  /// öndeki hücre sayısı `startWeekday - 1`'dir.
  int _takvimSatirSayisi({required int daysInMonth, required int startWeekday}) {
    final int doluHucre = daysInMonth + (startWeekday - 1);
    return (doluHucre / 7).ceil();
  }

  /// Hücrelerin en-boy oranını, ayın satır sayısına göre verir.
  ///
  /// Grid'in verilen yüksekliğe tam olarak sığması için oran
  /// kullanılabilir alandan hesaplanır. Sabit oran (ör. kare) kullanılırsa
  /// 5 satırlık ay ile 6 satırlık ay aynı hücre yüksekliğini ister ve
  /// 31 günlük ayın altıncı satırı ekranın altında kalır — gün sayıları
  /// görünmez ve aşağı kaydırma da gelmez.
  double _takvimEnBoyOrani({
    required double genislik,
    required double yukseklik,
    required int satirSayisi,
  }) {
    const double yatayBosluk = 12; // padding horizontal * 2
    const double hucereAraligi = 6.0;
    const double dikeyBosluk = 8; // padding vertical * 2

    final double hucreGenisligi =
        (genislik - yatayBosluk - hucereAraligi * 6) / 7;
    final double kullanilabilirYukseklik = yukseklik - dikeyBosluk;
    final double hucreYuksekligi =
        (kullanilabilirYukseklik - hucereAraligi * (satirSayisi - 1)) /
            satirSayisi;

    // Alan çok dar kalırsa oran sıfıra düşerdi; alt sınır koyulur ki
    // gün numarası en azından okunur bir yükseklik kazansın.
    if (hucreYuksekligi <= 0) return 1.0;

    final double oran = hucreGenisligi / hucreYuksekligi;
    return oran.clamp(0.35, 2.5);
  }

  /// Takvimde o güne düşen görev sayısını bulur.
///
/// Görevler zaten bellekte ([_gorevlerStream] son verisi) olduğu için
/// ek Firestore sorgusu yapılmaz. Gün, görevin başlangıç–son tarih
/// aralığına düşüyorsa sayılır (öğrenci o gün çalışıyor demektir).
  int _gununGorevSayisi(DateTime gun) {
    return _sonGorevler
        .where((gorev) => gorev.tarihAraliginaDahilMi(gun))
        .length;
  }

  /// Takvim hücresinin alt rengi: günün durumuna göre.
  Color _gunRengi(DateTime gun, {required bool secili}) {
    if (secili) return Colors.deepPurpleAccent;

    final int gorevSayisi = _gununGorevSayisi(gun);
    if (gorevSayisi == 0) return Colors.transparent;

    // Hepsi onaylandıysa yeşil, aksi hâlde turuncu.
    final bool tamamlandi = _sonGorevler
        .where((gorev) => gorev.tarihAraliginaDahilMi(gun))
        .every((gorev) => gorev.durum == GorevDurumu.onaylandi);
    return (tamamlandi ? Colors.greenAccent : Colors.orange).withValues(alpha: 0.22);
  }

  /// Takvim verilerinden son gelen görev listesi.
  ///
  /// Hücre renklendirmesi için gerekir; stream her güncellendiğinde
  /// [_gorevlerStream]'in dinleyicisi bunu yeniler.
  List<Gorev> _sonGorevler = const [];

  void _tumGorevleriGoster() {
    setState(() => _tumGorevlerMi = true);
  }

  void _takvimiGoster() {
    // Bugüne dön: takvime geçildiğinde bugün seçili olsun.
    final DateTime bugun = DateTime.now();
    setState(() {
      _tumGorevlerMi = false;
      _currentYear = bugun.year;
      _currentMonthIndex = bugun.month - 1;
      secilenTarih = DateTime(bugun.year, bugun.month, bugun.day);
    });

    // Sayfa geçişi, PageView yeniden ağaca girdikten SONRA yapılmalı.
    // `_tumGorevlerMi` true iken PageView hiç kurulmuyor; aynı karede
    // `jumpToPage` çağrılırsa controller'ın bağlandığı viewport henüz yok
    // ve takvim eski ayda/boş kalıyordu.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_pageController.hasClients) _pageController.jumpToPage(_currentMonthIndex);
    });
  }

  /// AppBar'daki yıl başlığına dokununca yıl seçici açılır.
  Future<void> _yilSeciciAc(BuildContext context) async {
    final DateTime simdi = DateTime.now();
    // Gelecek yıllara ve çok eski yıllara gidilmesin: ödevler
    // bugünden sonra çok uzakta olamaz, geçmişe de birkaç yıl yeter.
    final int ilkYil = simdi.year - 5;
    final int sonYil = simdi.year + 1;

    final List<int> yillar = List<int>.generate(
      sonYil - ilkYil + 1,
      (int i) => sonYil - i,
    );

    final int? secilen = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: const Color(0xFF161B22),
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: yillar
              .map((int yil) => ListTile(
                    title: Text(
                      '$yil',
                      style: TextStyle(
                        fontWeight: yil == _currentYear ? FontWeight.bold : FontWeight.normal,
                        color: yil == _currentYear ? Colors.deepPurpleAccent : Colors.white,
                      ),
                    ),
                    trailing: yil == simdi.year
                        ? const Text('bu yıl', style: TextStyle(color: Colors.grey, fontSize: 12))
                        : null,
                    onTap: () => Navigator.pop(context, yil),
                  ))
              .toList(),
        ),
      ),
    );

    if (secilen == null) return;

    setState(() {
      _currentYear = secilen;
      // Seçili gün ayın sınırını aşıyorsa (ör. 31 Şubat) en yakın
      // geçerli güne kırpılır; aksi hâde `DateTime` sessizce bir
      // sonraki aya kayar ve takvim yanlış günü seçili gösterir.
      final int gun = secilenTarih.day;
      final int sonGun = DateTime(secilen, secilenTarih.month + 1, 0).day;
      secilenTarih = DateTime(secilen, secilenTarih.month, gun > sonGun ? sonGun : gun);
    });
  }

  final List<String> aylarListesi = [
    'OCAK', 'ŞUBAT', 'MART', 'NİSAN', 'MAYIS', 'HAZİRAN',
    'TEMMUZ', 'AĞUSTOS', 'EYLÜL', 'EKİM', 'KASIM', 'ARALIK'
  ];

  @override
  void initState() {
    super.initState();
    _currentMonthIndex = secilenTarih.month - 1;
    _currentYear = secilenTarih.year;
    _pageController = PageController(initialPage: _currentMonthIndex);

    _gorevlerStream = _gorevlerKoleksiyonu
        .where('ogrenciId', isEqualTo: widget.ogrenciId)
        .snapshots()
        .map((anlik) => anlik.docs.map(Gorev.dokumandan).toList());

    _ogrenciStream =
        _ogrencilerKoleksiyonu.doc(widget.ogrenciId).snapshots();

    _gorevlerAbonelik = _gorevlerStream.listen((List<Gorev> gorevler) {
      // Takvim hücrelerinin rengi bu listeye bakar; `setState` yalnız
      // ekran görünürken yapılır (milisaniyelik gecikmesi olmaz).
      if (mounted) setState(() => _sonGorevler = gorevler);
    });

    _ogrenciSilinmeDurumunuDinle();
    _ogrenciBildirimIzniAl();
    _bildirimTokeniniKaydet();

    // Bildirimden doğrudan bu panele gelinirse (uygulama kapalıyken
    // dokunuldu) yönlendirici aktif kullanıcıyı bilmiyor olabilir.
    _yonlendirici.aktifKullaniciyiAyarla(
      belgeYolu: BildirimServisi.ogrenciKoleksiyon,
      belgeId: widget.ogrenciId,
      yoneticiModu: false,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _konumIznAlveBaslat();
    });
  }

  void _ogrenciSilinmeDurumunuDinle() {
    _ogrenciSubscription = _ogrenciStream.listen((snapshot) async {
      if (!snapshot.exists) {
        SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.remove('aktif_ogrenci_id');

        if (mounted) {
          Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const GirisEkrani()), (route) => false);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Yönetici tarafından kaydınız silindi!'), backgroundColor: Colors.redAccent));
        }
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _ogrenciSubscription?.cancel();
    _gorevlerAbonelik?.cancel();
    _gpsZamanlayici?.cancel();
    _bildirim.abonelikleriIptalEt();
    super.dispose();
  }

  Future<void> _ogrenciBildirimIzniAl() async {
    await _bildirim.izinIste();
  }

  Future<void> _bildirimTokeniniKaydet() async {
    await _bildirim.tokeniAlVeKaydet(
      BildirimServisi.ogrenciKoleksiyon,
      widget.ogrenciId,
    );
    _bildirim.tokenYenilemesiniDinle(
      BildirimServisi.ogrenciKoleksiyon,
      widget.ogrenciId,
    );
  }

  Future<void> _konumIznAlveBaslat() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _konumHatasiGoster(
          'Konum (GPS) servisiniz kapalı. Takip için açmanız gerekiyor.',
          () => Geolocator.openLocationSettings(),
          'GPS Aç',
        );
        return;
      }

      LocationPermission izin = await Geolocator.checkPermission();

      if (izin == LocationPermission.denied) {
        izin = await Geolocator.requestPermission();
      }

      if (izin == LocationPermission.denied || izin == LocationPermission.deniedForever) {
        _konumHatasiGoster(
          'Konum izni verilmedi. Ödev ve konum takibi için izin vermeniz gerekiyor.',
          () => Geolocator.openAppSettings(),
          'Ayarları Aç',
        );
        return;
      }

      _gpsZamanlayici?.cancel();
      _gpsZamanlayici = Timer.periodic(gpsGuncellemeAraligi, (_) => _konumuFirestoreYaz());
      await _konumuFirestoreYaz();
    } catch (e) {
      debugPrint("Konum hatası: $e");
    }
  }

  Future<void> _konumuFirestoreYaz() async {
    try {
      Position? konum;
      try {
        konum = await Geolocator.getCurrentPosition(
          locationSettings: LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: const Duration(seconds: 15),
          ),
        );
      } catch (e) {
        konum = await Geolocator.getLastKnownPosition();
      }

      if (konum == null) return;

      await _ogrencilerKoleksiyonu.doc(widget.ogrenciId).set({
        'enlem': konum.latitude,
        'boylam': konum.longitude,
        'zaman': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint("Konum gönderilemedi: $e");
    }
  }

  void _konumHatasiGoster(String mesaj, Future<void> Function() aksiyon, String butonMetni) {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: const Color(0xFF161B22),
          title: const Text('Konum İzni Gerekli', style: TextStyle(color: Colors.redAccent)),
          content: Text(mesaj),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Kapat', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
              onPressed: () {
                Navigator.pop(dialogContext);
                aksiyon();
              },
              child: Text(butonMetni),
            ),
          ],
        ),
      );
    });
  }

  void _odeviGonderPenceresi(BuildContext context, String docId, String mevcutBaslik) {
    final TextEditingController aciklamaCtrl = TextEditingController();
    List<String> secilenBase64Resimler = [];

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              backgroundColor: const Color(0xFF161B22),
              title: const Text('Ödevi Gönder'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text("'$mevcutBaslik' için açıklama ve 1-10 arası fotoğraf ekleyin.", style: const TextStyle(color: Colors.grey, fontSize: 13)),
                    const SizedBox(height: 12),
                    TextField(
                      controller: aciklamaCtrl,
                      decoration: InputDecoration(hintText: "Açıklama...", filled: true, fillColor: const Color(0xFF0D0F12), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none)),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.grey.shade800, foregroundColor: Colors.white),
                      onPressed: () async {
                        final List<XFile> images = await ImagePicker().pickMultiImage(imageQuality: 70);
                        if (!context.mounted) return;
                        if (images.isNotEmpty) {
                          if (secilenBase64Resimler.length + images.length > 10) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('En fazla 10 fotoğraf seçebilirsiniz!')));
                            return;
                          }
                          for (var img in images) {
                            List<int> bytes = await File(img.path).readAsBytes();
                            secilenBase64Resimler.add(base64Encode(bytes));
                          }
                          setStateDialog(() {});
                        }
                      },
                      icon: const Icon(Icons.photo_library),
                      label: Text('Fotoğraf Seç (${secilenBase64Resimler.length}/10)'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('İptal', style: TextStyle(color: Colors.grey))),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
                  onPressed: () async {
                    if (secilenBase64Resimler.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lütfen en az 1 fotoğraf seçin!')));
                      return;
                    }
                    await _gorevlerKoleksiyonu.doc(docId).update({
                      'durum': 'onay_bekliyor',
                      'aciklama': aciklamaCtrl.text.trim(),
                      'resimYollari': secilenBase64Resimler,
                    });
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  },
                  child: const Text('Onaya Gönder'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Seçili güne düşen görevleri döndürür.
///
/// Önceden bu işlem `QueryDocumentSnapshot` üzerinde yapılıyor ve her
/// çağrıda `Gorev.dokumandan()` ile belge yeniden ayrıştırılıyordu.
/// Artık model üzerinde çalışır ve kare başına parse yoktur.
List<Gorev> _gorevleriAraligaGoreFiltrele(
  List<Gorev> gorevler,
  DateTime secilenTarih,
) {
  return gorevler
      .where((gorev) => gorev.tarihAraliginaDahilMi(secilenTarih))
      .toList();
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              aylarListesi[_currentMonthIndex],
              style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2),
            ),
            // Yıl başlığı tıklanabilir: takvimde yıl değiştirilemiyordu.
            InkWell(
              onTap: () => _yilSeciciAc(context),
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$_currentYear',
                      style: const TextStyle(fontSize: 13, color: Colors.white70),
                    ),
                    const Icon(Icons.arrow_drop_down, size: 18, color: Colors.white70),
                  ],
                ),
              ),
            ),
          ],
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF161B22),
        automaticallyImplyLeading: false,
        actions: [
          // Takvim <-> tüm görevler geçişi düğmeye taşındı: önceden
          // yalnız "Takvime dön" vardı, geri dönmenin yolu belirsizdi.
          IconButton(
            tooltip: _tumGorevlerMi ? 'Takvimi göster' : 'Tüm görevleri göster',
            icon: Icon(
              _tumGorevlerMi ? Icons.event : Icons.grid_view_rounded,
              color: _tumGorevlerMi ? Colors.white : Colors.deepPurpleAccent,
            ),
            onPressed: _tumGorevlerMi ? _takvimiGoster : _tumGorevleriGoster,
          ),
          BildirimRozeti(
            belgeYolu: BildirimServisi.ogrenciKoleksiyon,
            belgeId: widget.ogrenciId,
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'Hakkında',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const HakkindaEkrani()),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: _ogrenciStream,
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const LinearProgressIndicator();
              var veri = snapshot.data!.data();
              String adSoyad = veri?['adSoyad'] ?? widget.ogrenciId;
              String profilResmi = veri?['profilResmi'] ?? '';

              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                color: const Color(0xFF161B22),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: Colors.deepPurple,
                      child: ClipOval(child: SizedBox(width: 40, height: 40, child: bulutGorselCikar(profilResmi, fit: BoxFit.cover))),
                    ),
                    const SizedBox(width: 12),
                    Text(adSoyad, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
              );
            },
          ),
          if (_tumGorevlerMi) ...[
            // Takvim gizlendiğinde hangi modda olunduğu belirtilir;
            // takvime dönmek için AppBar'daki düğme kullanılır.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  const Icon(Icons.grid_view_rounded, size: 18, color: Colors.grey),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Tüm görevler gösteriliyor — takvime dönmek için üstteki düğmeye dokun',
                      style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: ['PZT', 'SAL', 'ÇAR', 'PER', 'CUM', 'CMT', 'PAZ']
                    .map((gun) => Text(gun, style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)))
                    .toList(),
              ),
            ),
            Expanded(
              flex: 4,
              child: PageView.builder(
                controller: _pageController,
                itemCount: 12,
                onPageChanged: (index) {
                  setState(() {
                    _currentMonthIndex = index;
                    // Seçili gün korunur ama yıl `_currentYear`'a bağlanır;
                    // gün ayın sınırını aşıyorsa kırpılır (örn. 31 Şubat).
                    final int gun = secilenTarih.day;
                    final int sonGun = DateTime(_currentYear, index + 2, 0).day;
                    secilenTarih = DateTime(
                      _currentYear,
                      index + 1,
                      gun > sonGun ? sonGun : gun,
                    );
                  });
                },
itemBuilder: (context, monthIndex) {
                  final int daysInMonth = DateTime(_currentYear, monthIndex + 2, 0).day;
                  final int startWeekday = DateTime(_currentYear, monthIndex + 1, 1).weekday;
                  final DateTime bugun = DateTime.now();

                  // Takvim çizimi 5 veya 6 satıra göre ölçeklenir.
                  //
                  // Önceden hücre yüksekliği sabit `childAspectRatio: 1.0`
                  // idi; 31 günlük ayların altıncı satırı ekranın dışında
                  // kalıyordu. Sabit en-boy oranı yüzünden hücreler
                  // kısıtlanamayacağı için oran satır sayısına bağlı
                  // hesaplanır: 5 satırlık ayda büyür, 6 satırlık ayda
                  // küçülür. Böylece her ayın tamamı ekrana sığar.
                  final int satirSayisi = _takvimSatirSayisi(
                    daysInMonth: daysInMonth,
                    startWeekday: startWeekday,
                  );

                  return LayoutBuilder(
                    builder: (context, kisitlar) {
                      return GridView.builder(
                        physics: const NeverScrollableScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 7,
                          // Oran, ayın gerçekten kaç satır taşıdığına ve
                          // ekranda ne kadar yer olduğuna göre hesaplanır;
                          // böylece 31 günlük ayların alt satırı da görünür.
                          childAspectRatio: _takvimEnBoyOrani(
                            genislik: kisitlar.maxWidth,
                            yukseklik: kisitlar.maxHeight,
                            satirSayisi: satirSayisi,
                          ),
                          crossAxisSpacing: 6.0,
                          mainAxisSpacing: 6.0,
                        ),
                        itemCount: satirSayisi * 7,
                        itemBuilder: (context, index) {
                          if (index < startWeekday - 1) return const SizedBox.shrink();

                          final int dayNum = index - (startWeekday - 2);

                          // Bu ayın gün sayısını aşan hücreler boş kalır.
                          if (dayNum > daysInMonth) return const SizedBox.shrink();

                          final DateTime hucreTarihi = DateTime(_currentYear, monthIndex + 1, dayNum);

                          final bool isSelected =
                              secilenTarih.day == dayNum &&
                              secilenTarih.month == (monthIndex + 1) &&
                              secilenTarih.year == _currentYear;
                          final bool isToday =
                              bugun.day == dayNum &&
                              bugun.month == (monthIndex + 1) &&
                              bugun.year == _currentYear;

                          final int gorevSayisi = _gununGorevSayisi(hucreTarihi);

                          return GestureDetector(
                            onTap: () => setState(() => secilenTarih = hucreTarihi),
                            child: Container(
                              decoration: BoxDecoration(
                                color: _gunRengi(hucreTarihi, secili: isSelected),
                                borderRadius: BorderRadius.circular(10),
                                border: isToday && !isSelected
                                    ? Border.all(color: Colors.deepPurpleAccent, width: 1.5)
                                    : null,
                              ),
                              child: Stack(
                                children: [
                                  Center(
                                    child: Text(
                                      '$dayNum',
                                      style: TextStyle(
                                        color: isSelected ? Colors.white : Colors.white70,
                                        fontWeight: isSelected || isToday
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                  // Görev olan günlerde küçük nokta: kullanıcı
                                  // takvime bakıp o günde işi olup olmadığını
                                  // listede taramadan görür.
                                  if (gorevSayisi > 0)
                                    Positioned(
                                      bottom: 4,
                                      child: Container(
                                        width: 5,
                                        height: 5,
                                        decoration: const BoxDecoration(
                                          color: Colors.white70,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
          const Divider(height: 1, color: Colors.white10),
          Expanded(
            flex: 5,
            child: StreamBuilder<List<Gorev>>(
              stream: _gorevlerStream,
              builder: (context, anlik) {
                if (anlik.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final List<Gorev> tumGorevler = anlik.data ?? const [];

                // "Tümü" modunda aralık filtresi uygulanmaz: kullanıcı
                // her geçmişe, bildirimden gelen de her göreve ulaşabilir.
                final List<Gorev> liste = _tumGorevlerMi
                    ? tumGorevler
                    : _gorevleriAraligaGoreFiltrele(tumGorevler, secilenTarih);

                if (liste.isEmpty) {
                  return Center(
                    child: Text(
                      _tumGorevlerMi
                          ? 'Henüz görev yok.'
                          : '${secilenTarih.day} ${aylarListesi[secilenTarih.month - 1]} tarihinde görev yok.',
                      style: const TextStyle(color: Colors.grey, fontSize: 14),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: liste.length,
                  itemBuilder: (context, index) {
                    // Model stream tarafında çözülmüş gelir; burada belge
                    // ayrıştırma yapılmaz.
                    final Gorev gorev = liste[index];
                    final String docId = gorev.id;
                    final GorevDurumu durum = gorev.durum;

                    Color durumRengi = Colors.orange;
                    String durumMetni = "Yapılıyor";
                    if (durum == GorevDurumu.onayBekliyor) {
                      durumRengi = Colors.blueAccent;
                      durumMetni = "Onay Bekliyor...";
                    } else if (durum == GorevDurumu.onaylandi) {
                      durumRengi = Colors.greenAccent;
                      durumMetni = "Onaylandı ✓";
                    }

                    final String? aralik = gorev.tarihAraligiMetni;

                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => GorevDetayEkrani(
                              gorevId: docId,
                              onGorev: gorev,
                              gonderimYapilabilir: true,
                              onGonder: _odeviGonderPenceresi,
                            ),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  gorev.baslik,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    decoration: durum == GorevDurumu.onaylandi ? TextDecoration.lineThrough : TextDecoration.none,
                                  ),
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 4.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text("Durum: $durumMetni", style: TextStyle(color: durumRengi, fontWeight: FontWeight.bold, fontSize: 13)),
                                      if (aralik != null) Text(aralik, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                    ],
                                  ),
                                ),
                                trailing: (durum == GorevDurumu.atanlandi)
                                    ? ElevatedButton(
                                        style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurpleAccent, foregroundColor: Colors.white),
                                        onPressed: () => _odeviGonderPenceresi(context, docId, gorev.baslik),
                                        child: const Text('Ödevi Gönder'),
                                      )
                                    : Icon(durum == GorevDurumu.onaylandi ? Icons.check_circle : Icons.hourglass_top, color: durumRengi),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
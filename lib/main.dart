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
import 'screens/bildirimler_ekrani.dart';
import 'screens/gorev_detay_ekrani.dart';
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

  FirebaseMessaging.onBackgroundMessage(BildirimYonlendirici.arkaPlanIsleyici);

  FirebaseMessaging.onMessage.listen(_yonlendirici.onMesaj);
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

  runApp(GorevTakipUygulamasi(baslangicEkrani: baslangicEkrani));

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

// Yardımcı: Base64 görsel gösterici
Widget bulutGorselCikar(String base64Str, {double? width, double? height, BoxFit fit = BoxFit.cover}) {
  if (base64Str.isEmpty) {
    return const Icon(Icons.person, size: 40, color: Colors.white70);
  }
  try {
    if (base64Str.startsWith('http')) {
      return Image.network(base64Str, width: width, height: height, fit: fit, errorBuilder: (c, o, s) => const Icon(Icons.error));
    }
    return Image.memory(base64Decode(base64Str), width: width, height: height, fit: fit);
  } catch (e) {
    return const Icon(Icons.broken_image);
  }
}

// Görseli Büyütme (Dialog) Fonksiyonu
void gorseliBuyut(BuildContext context, String base64Str) {
  showDialog(
    context: context,
    builder: (context) => Dialog(
      backgroundColor: Colors.black,
      child: InteractiveViewer(
        child: bulutGorselCikar(base64Str, fit: BoxFit.contain),
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
  @override
  void initState() {
    super.initState();
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
    final CollectionReference<Map<String, dynamic>> ogrencilerKoleksiyonu =
        FirebaseFirestore.instance.collection('ogrenciler');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Yönetici Paneli', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF161B22),
        elevation: 0,
        actions: [
          StreamBuilder<int>(
            stream: _bildirim.okunmamisSayisi(
              BildirimServisi.yoneticiKoleksiyon,
              BildirimServisi.yoneticiBelge,
            ),
            builder: (context, snapshot) {
              int okunmamis = snapshot.data ?? 0;
              return Stack(
                alignment: Alignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.notifications_outlined),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const BildirimlerEkrani(
                          belgeYolu: BildirimServisi.yoneticiKoleksiyon,
                          belgeId: BildirimServisi.yoneticiBelge,
                          onayVerilebilir: true,
                        ),
                      ),
                    ),
                  ),
                  if (okunmamis > 0)
                    Positioned(
                      right: 10,
                      top: 10,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
                        child: Text('$okunmamis', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                    ),
                ],
              );
            },
          ),
          IconButton(icon: const Icon(Icons.settings_outlined), onPressed: () => _ayarPenceresiAc(context)),
          IconButton(icon: const Icon(Icons.person_add_alt_1_outlined), onPressed: () => _ogrenciEkleVeyaDuzenle(context)),
          IconButton(icon: const Icon(Icons.logout, color: Colors.redAccent), onPressed: () => _cikisYap(context)),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: ogrencilerKoleksiyonu.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(child: Text('Henüz kayıtlı öğrenci yok.', style: TextStyle(color: Colors.grey)));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final veri = docs[index].data();
              final ogrenciId = docs[index].id;
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
class CanliKonumPaneli extends StatelessWidget {
  final String ogrenciId;
  final String ogrenciAdi;

  const CanliKonumPaneli({super.key, required this.ogrenciId, required this.ogrenciAdi});

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
      appBar: AppBar(title: Text('$ogrenciAdi - Canlı Konum'), backgroundColor: const Color(0xFF161B22)),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('ogrenciler').doc(ogrenciId).snapshots(),
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
                  Text(ogrenciAdi, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
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
class OgrenciDetayPaneli extends StatelessWidget {
  final String ogrenciId;
  final String ogrenciAdi;

  const OgrenciDetayPaneli({super.key, required this.ogrenciId, required this.ogrenciAdi});

  void _gorevEklePenceresi(BuildContext context) {
    final TextEditingController gorevCtrl = TextEditingController();
    final TextEditingController aciklamaCtrl = TextEditingController();
    DateTime secilenBaslangic = DateTime.now();
    DateTime secilenSon = DateTime.now();
    final CollectionReference gorevlerKoleksiyonu = FirebaseFirestore.instance.collection('gorevler');

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

                    await gorevlerKoleksiyonu.add({
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
    final CollectionReference<Map<String, dynamic>> gorevlerKoleksiyonu =
        FirebaseFirestore.instance.collection('gorevler');

    return Scaffold(
      appBar: AppBar(title: Text('$ogrenciAdi - Görevler'), backgroundColor: const Color(0xFF161B22)),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: gorevlerKoleksiyonu.where('ogrenciId', isEqualTo: ogrenciId).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) return const Center(child: Text('Bu öğrenciye henüz görev atanmamış.', style: TextStyle(color: Colors.grey)));

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final Gorev gorev = Gorev.dokumandan(docs[index]);
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
                                  onPressed: () => gorevlerKoleksiyonu.doc(docId).update({'durum': GorevDurumu.onaylandi.kod}),
                                  child: const Text('Onayla'),
                                )
                              : Icon(durum == GorevDurumu.onaylandi ? Icons.check_circle : Icons.hourglass_top, color: durumRengi),
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

  StreamSubscription<DocumentSnapshot>? _ogrenciSubscription;
  Timer? _gpsZamanlayici;

  DateTime secilenTarih = DateTime.now();
  late PageController _pageController;
  int _currentMonthIndex = 0;

  /// true iken görev listesi tüm görevleri gösterir (takvim gününe göre
  /// filtrelemez). Kullanıcı eski bir görevi aradığında veya bildirimden
  /// geldiğinde bu mod kullanılır.
  bool _tumGorevlerMi = true;

  void _seciliGuneGoreGoster() {
    setState(() {
      _tumGorevlerMi = false;
      // Bugune don: bu gune ait olmayan bir tarih secili kalmis olabilir.
      final DateTime bugun = DateTime.now();
      secilenTarih = DateTime(bugun.year, bugun.month, bugun.day);
      _currentMonthIndex = bugun.month - 1;
      _pageController.jumpToPage(_currentMonthIndex);
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
    _pageController = PageController(initialPage: _currentMonthIndex);
    
    _ogrenciSilinmeDurumunuDinle();
    _ogrenciBildirimIzniAl();
    _bildirimTokeniniKaydet();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _konumIznAlveBaslat();
    });
  }

  void _ogrenciSilinmeDurumunuDinle() {
    _ogrenciSubscription = _ogrencilerKoleksiyonu.doc(widget.ogrenciId).snapshots().listen((snapshot) async {
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
    _gpsZamanlayici?.cancel();
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

  // Ödevin ait olduğu tarih aralığına göre görevler filtrelenir.
// Başlangıç ve son tarih arasındaki HER gün listelenir; eski kayıtlarda
// başlangıç tarihi olmadığı için tek tarih (son tarih) kullanılır.
List<QueryDocumentSnapshot<Map<String, dynamic>>> _gorevleriAraligaGoreFiltrele(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  DateTime secilenTarih,
) {
  final DateTime hedef = DateTime(secilenTarih.year, secilenTarih.month, secilenTarih.day);

  return docs.where((doc) {
    final Gorev gorev = Gorev.dokumandan(doc);

    final DateTime? bas = gorev.baslangicTarihi ?? gorev.sonTarihi;
    final DateTime? son = gorev.sonTarihi ?? gorev.baslangicTarihi;

    // Tarih tanimli olmayan gorev hicbir gunde gosterilmez.
    if (bas == null || son == null) return false;

    final DateTime basGun = DateTime(bas.year, bas.month, bas.day);
    final DateTime sonGun = DateTime(son.year, son.month, son.day);

    return !hedef.isBefore(basGun) && !hedef.isAfter(sonGun);
  }).toList();
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(aylarListesi[_currentMonthIndex], style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2)),
        centerTitle: true,
        backgroundColor: const Color(0xFF161B22),
        automaticallyImplyLeading: false,
        actions: [
          StreamBuilder<int>(
            stream: _bildirim.okunmamisSayisi(
              BildirimServisi.ogrenciKoleksiyon,
              widget.ogrenciId,
            ),
            builder: (context, snapshot) {
              int okunmamis = snapshot.data ?? 0;
              return Stack(
                alignment: Alignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.notifications_outlined),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => BildirimlerEkrani(
                          belgeYolu: BildirimServisi.ogrenciKoleksiyon,
                          belgeId: widget.ogrenciId,
                        ),
                      ),
                    ),
                  ),
                  if (okunmamis > 0)
                    Positioned(
                      right: 10,
                      top: 10,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
                        child: Text('$okunmamis', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: _ogrencilerKoleksiyonu.doc(widget.ogrenciId).snapshots(),
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
            // Takvim gizlendiginde yerine goruntuleme secenekleri gosterilir.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Tüm görevler gösteriliyor',
                      style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                    ),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: Colors.deepPurpleAccent),
                    onPressed: _seciliGuneGoreGoster,
                    icon: const Icon(Icons.event, size: 18),
                    label: const Text('Takvime dön'),
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
                    secilenTarih = DateTime(secilenTarih.year, index + 1, 1);
                  });
                },
                itemBuilder: (context, monthIndex) {
                  int daysInMonth = DateTime(secilenTarih.year, monthIndex + 2, 0).day;
                  int startWeekday = DateTime(secilenTarih.year, monthIndex + 1, 1).weekday;

                  return GridView.builder(
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 7,
                      childAspectRatio: 1.0,
                      crossAxisSpacing: 6.0,
                      mainAxisSpacing: 6.0,
                    ),
                    itemCount: daysInMonth + (startWeekday - 1),
                    itemBuilder: (context, index) {
                      if (index < startWeekday - 1) return const SizedBox.shrink();
                      int dayNum = index - (startWeekday - 2);
                      bool isSelected = secilenTarih.day == dayNum && secilenTarih.month == (monthIndex + 1);
                      bool isToday = DateTime.now().day == dayNum && DateTime.now().month == (monthIndex + 1) && DateTime.now().year == secilenTarih.year;

                      return GestureDetector(
                        onTap: () => setState(() => secilenTarih = DateTime(secilenTarih.year, monthIndex + 1, dayNum)),
                        child: Container(
                          decoration: BoxDecoration(
                            color: isSelected ? Colors.deepPurpleAccent : (isToday ? Colors.grey.shade800 : Colors.transparent),
                            borderRadius: BorderRadius.circular(10),
                            border: isToday && !isSelected ? Border.all(color: Colors.deepPurpleAccent, width: 1.5) : null,
                          ),
                          child: Center(
                            child: Text(
                              '$dayNum',
                              style: TextStyle(
                                color: isSelected ? Colors.white : Colors.white70,
                                fontWeight: isSelected || isToday ? FontWeight.bold : FontWeight.normal,
                                fontSize: 14,
                              ),
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
          const Divider(height: 1, color: Colors.white10),
          Expanded(
            flex: 5,
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _gorevlerKoleksiyonu.where('ogrenciId', isEqualTo: widget.ogrenciId).snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                final docs = snapshot.data?.docs ?? [];

                // "Tümü" modunda aralik filtresi uygulanmaz: kullanici
                // her gecmise, bildirimden gelen de her goreve ulasabilir.
                final List<QueryDocumentSnapshot<Map<String, dynamic>>> liste = _tumGorevlerMi
                    ? docs
                    : _gorevleriAraligaGoreFiltrele(docs, secilenTarih);

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
                    final Gorev gorev = Gorev.dokumandan(liste[index]);
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
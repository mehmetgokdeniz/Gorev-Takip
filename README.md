# Çoklu Öğrenci Takip Sistemi

Yönetici ödev atar, öğrenci ödevi fotoğrafla gönderir, yönetici onaylar.
Push bildirimleri cihazda düşer ve **dokununca doğrudan ilgili ödevi açar** —
ödevin başlığı, durumu, başlangıç ve son tarihi tek ekranda görünür.

Flutter (mobil) + Firebase (Firestore, Cloud Messaging, Cloud Functions).

---

## Hızlı başlangıç

### 1) Bağımlılıklar

```bash
flutter pub get
cd functions && npm install && cd ..
```

### 2) Gizli ayarlar

`.env` dosyaları Git'a **girmez**. Kopyalarını oluşturun:

```bash
# Proje kökü
cp .env.example .env

# Cloud Functions
cp functions/.env.example functions/.env
```

`.env` içindeki `YONETICI_SIFRE_OZET` değerini kendi şifrenize göre üretin:

```bash
node -e "console.log(require('crypto').createHash('sha256').update('YENI_SIFREN','utf8').digest('hex'))"
```

> Orijinal şifre hiçbir yere yazılmaz — sadece bu özet saklanır.
> Şifrenizi unutursanız Functions üzerinden sıfırlamanız gerekir.

### 3) Derleme

```bash
node scripts/dart_define_uret.js --build
```

Bu komut `.env` içindeki değerleri okur ve `--dart-define` bayraklarını
otomatik ekleyerek release APK'yı üretir. Çıktı:

```
build/app/outputs/flutter-apk/app-release.apk
```

### 4) Functions deploy

```bash
firebase deploy --only functions
```

Deploy sonrası Cloud Function adresini `.env` içine yazın:

```
YONETICI_DOGRULAMA_URL=https://<region>-<proje-id>.cloudfunctions.net/yoneticiSifresiDogrula
```

Ayrıca Firebase Console → Functions → Environment variables bölümüne
aynı `YONETICI_SIFRE_OZET` değerini tanımlayın (canlı ortam `.env`
dosyasını okumaz).

---

## Bildirim akışı

| Durum | Kime | `tur` |
|---|---|---|
| Yönetici ödev atadı | Öğrenci | `gorev_atanldi` |
| Öğrenci onaya gönderdi | Yönetici | `onay_bekliyor` |
| Yönetici onayladı | Öğrenci | `onaylandi` |

Her bildirim iki yere yazılır:

1. **Push** — FCM üzerinden anında bildirim
2. **Uygulama içi kayıt** — `{koleksiyon}/{belge}/bildirimler/` altına

İkincisi sayesinde bildirim geçmişi kalıcıdır; cihaz değişse bile liste
korunur ve zil ikonundaki okunmamış rozeti gerçek bir bildirim
sayısından gelir.

**Dokunma davranışı** (`lib/services/bildirim_yonlendirici.dart`):

- Uygulama ön plandayken → SnackBar çıkar, "Aç" ile göreve gidilir
- Arka plandayken dokunuldu → doğrudan görev detayı açılır
- Uygulama kapalıyken dokunuldu → ilk karede otomatik açılır

Hedef ekran `lib/screens/gorev_detay_ekrani.dart`'dir.

---

## Proje yapısı

```
lib/
├── main.dart                     # Giriş ekranı, yönetici paneli, öğrenci paneli
├── firebase_options.dart         # Firebase yapılandırması (üretilmiş)
├── config/
│   └── uygulama_ayarlari.dart    # Şifre özeti, ortam değişkenleri
├── models/
│   ├── gorev.dart                # Görev + durum + tarih aralığı
│   └── bildirim.dart             # Bildirim + türleri
├── services/
│   ├── bildirim_servisi.dart     # Token kaydı, bildirim listesi
│   └── bildirim_yonlendirici.dart# Dokunma → ekran yönlendirmesi
└── screens/
    ├── bildirimler_ekrani.dart   # Uygulama içi bildirim listesi
    └── gorev_detay_ekrani.dart   # Ödev + başlangıç/son tarih

functions/
├── index.js                      # Firestore trigger'ları, bildirim gönderimi
├── sifre_dogrula.js              # Şifre doğrulama (sadece özet karşılaştırır)
├── ortam.js                      # .env okuyucu (bağımlılıksız)
└── .env.example                  # Şablon

scripts/
├── ortam_yardimci.js             # Script'ler için ortak .env okuyucu
├── dart_define_uret.js           # Derleme komutu üretir / derler
├── sifre_testi.js                # Şifre doğrulama testleri
├── apk_sizinti_taramasi.js       # APK sızıntı taraması
└── functions_kontrol.js          # Trigger varlık kontrolü
```

---

## Veri modeli

### `gorevler/{gorevId}`

| Alan | Tip | Açıklama |
|---|---|---|
| `ogrenciId` | string | Öğrenci kimliği |
| `baslik` | string | Ödev başlığı |
| `durum` | string | `atanlandi` / `onay_bekliyor` / `onaylandi` |
| `aciklama` | string | Öğrenci notu |
| `resimYollari` | string[] | Fotoğraflar (base64) |
| `baslangicTarihi` | timestamp | **Başlangıç tarihi** |
| `sonTarih` | timestamp | **Son tarih** |
| `zaman` | timestamp | Oluşturma zamanı |

### `ogrenciler/{ogrenciId}`

`adSoyad`, `profilResmi`, `enlem`, `boylam`, `zaman`

Alt koleksiyonlar: `tokens/` (FCM), `bildirimler/` (geçmiş)

### `ayarlar/yonetici`

Alt koleksiyonlar: `tokens/`, `bildirimler/`

---

## Yönetici girişi

Şifre **hiçbir yerde düz metin saklanmaz**. Akış:

1. Kullanıcı şifreyi yazar
2. Uygulama SHA-256 özetini hesaplar
3. Cloud Function (`yoneticiSifresiDogrula`) özeti **kendi** özetiyle
   karşılaştırır (zamanlama sızıntısına karşı `timingSafeEqual`)
4. HTTP 200 → yönetici, 401 → red

Cloud Function erişilemezse uygulama `--dart-define` ile gömülü özete
düşer (internet yok senaryosu).

**Önemli:** `--dart-define` ile verilen değer APK'nın içine gömülür ve
decompile edildiğinde görünür. Bu yüzden:

- Gerçek sırlar için `--dart-define` **kullanmayın**
- `YONETICI_SIFRE_OZET` yalnızca Functions tarafında tutulur
- Boş bırakılırsa fonksiyon 503 döner ve **kimse** yönetici giremez
  (güvenli varsayılan)

---

## Test ve doğrulama

```bash
flutter analyze                     # statik analiz
flutter test                        # Dart testleri (20 test)
node scripts/sifre_testi.js         # şifre doğrulama (12 kontrol)
node scripts/functions_kontrol.js  # trigger'lar yüklü mü
node scripts/apk_sizinti_taramasi.js  # APK sızıntı taraması
```

Sızıntı taraması iki yönü doğrular:

- Şifre **özeti** APK'da **bulunmalı** (çevrimdışı giriş çalışsın)
- Şifre **metni** APK'da **bulunmamalı**

---

## Git'e göndermeden önce

`.env` dosyaları `.gitignore` içindedir ve commit edilmez. Doğrulamak için:

```bash
git status --short          # .env görünmemeli
git check-ignore -v .env    # hangi kuralın tuttuğunu gösterir
```

Ajan araçlarının hafızası (`.commandcode/`) da ignore edilir; içinde
proje değeri barındırabilir.

---

## Bilinen sınırlar

- **Firestore kuralları kapalı.** `firestore.rules` tüm istemci erişimini
  reddediyor; uygulama yalnızca Firebase Authentication eklendikten sonra
  çalışabilir. Kuralların yorumlu hâli dosyanın içinde hazır bekliyor.
- **Öğrenci girişi kimlik doğrulaması değil.** Öğrenci ID'sini bilen kişi
  o öğrencinin verisine erişir. Gerçek koruma için `firebase_auth` gerekir.
- Fotoğraflar Firestore'da base64 olarak saklanır (belge limiti 1 MB).
  Çok fotoğraflı gönderimlerde bu sınıra dikkat edilmelidir.
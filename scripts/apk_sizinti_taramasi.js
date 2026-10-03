// APK icin gizli bilgi sizinti taramasi.
//
// Kontrol edilenler:
//   1) Yonetici sifresinin SHA-256 ozeti (dogru yon)
//   2) Yonetici sifresinin dogrudan metni (yanlis yon)
//   3) Diger gizli dosya kalintiari (.env, anahtar dosyalari)
//
// Beklentiler:
//   - Sifre OZETI APK icinde BULUNMALI (cevrimdisi giris calismali)
//   - Sifre METNI APK icinde BULUNMAMALI
//   - .env / anahtar dosyasi APK icinde OLMAMALI
//
// Sifre ozeti kaynak kodda degil, .env dosyasindan okunur.
//
// Kullanim: node scripts/apk_sizinti_taramasi.js
const fs = require("fs");
const path = require("path");
const { execFileSync } = require("child_process");

const { KOK, yoneticiOzeti, kokEnvOku } = require("./ortam_yardimci");

const APK = path.join(KOK, "build", "app", "outputs", "flutter-apk", "app-release.apk");

if (!fs.existsSync(APK)) {
  console.error("APK bulunamadi. Once `flutter build apk --release` calistirin.");
  process.exit(1);
}

// .env okunamazsa tarama anlamsizdir: ne aranacagi bilinmez.
const sifreOzeti = yoneticiOzeti();
if (!sifreOzeti) {
  console.error("HATA: YONETICI_SIFRE_OZET okunamadi (.env dosyasini kontrol edin).");
  process.exit(1);
}

console.log("APK taraniyor:", APK);
console.log("Boyut:", (fs.statSync(APK).size / 1024 / 1024).toFixed(1), "MB");
console.log("Aranan ozet:", sifreOzeti.slice(0, 16) + "...\n");

// APK bir ZIP dosyasidir. ZIP icerigini PowerShell ile geziyoruz;
// kabuk kacis sorunu olmamasi icin yol tek tirnak icinde verilir.
function zipTara(basamak) {
  const betik = `
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$z=[System.IO.Compression.ZipFile]::OpenRead('${APK}')
foreach($e in $z.Entries){
  if($e.Length -eq 0){continue}
  try{
    $s=$e.Open()
    $ms=New-Object System.IO.MemoryStream
    $s.CopyTo($ms)
    $s.Close()
    ${basamak}
    $ms.Dispose()
  }catch{}
}
$z.Dispose()
`;
  return execFileSync(
    "powershell",
    ["-NoProfile", "-Command", betik],
    { encoding: "utf8", maxBuffer: 1024 * 1024 * 64 }
  );
}

// 1) Sifre OZETI icinde mi? (dogru yon)
const ozetSonuc = zipTara(`
$txt=[System.Text.Encoding]::ASCII.GetString($ms.ToArray())
if($txt.Contains('${sifreOzeti}')){ Write-Output $e.FullName }
`);

// 2) Gercek sifre METNI icinde mi? (yanlis yon)
//
// DIKKAT: "123456", "password" gibi KISA diziler APK'da her zaman
// bulunur (Firebase SDK, proto dosyalari, derleyici sablonlari).
// Bunlari taramak yanlis pozitif uretir, bu yuzden TARANMAZ.
//
// Bunun yerine .env dosyasindaki YONETICI_SIFRE_ADI taranir:
// siz gercek sifrenizi bu degere yazarsaniz tarama onu arar.
// (Bu deger sadece yerel tarama icindir; sunucuya hic gitmez.)
const gercekSifre = (kokEnvOku().YONETICI_SIFRE_ADI || "").trim();

const metinBulunanlar = [];
if (gercekSifre.length >= 4) {
  const r = zipTara(`
$txt=[System.Text.Encoding]::ASCII.GetString($ms.ToArray())
if($txt.Contains('${gercekSifre}')){ Write-Output $e.FullName }
`);
  if ((r || "").trim()) metinBulunanlar.push(r.trim());
}

// 3) Gizli dosya kaliplari
const zipAdlar = zipTara("Write-Output $e.FullName");

let hata = 0;

const ozetBulundu = (ozetSonuc || "").trim().length > 0;
if (ozetBulundu) {
  console.log("[OK] Sifre ozeti APK icinde mevcut (cevrimdisi giris calisir).");
} else {
  console.error("[BASARISIZ] Sifre ozeti APK icinde YOK - yonetici girisi calismayacak!");
  console.error("  Cozum: --dart-define=YONETICI_SIFRE_HASH=" + sifreOzeti);
  console.error("  Veya:   node scripts/dart_define_uret.js --build");
  hata++;
}

if (metinBulunanlar.length > 0) {
  console.error("[BASARISIZ] Sifre METNI APK icinde bulundu:");
  metinBulunanlar.forEach((m) => console.error("  " + m));
  console.error("  Sifre metni kaynak koda gomulmus demektir. .env'deki YONETICI_SIFRE_OZET degerini kullanin.");
  hata++;
} else if (gercekSifre.length >= 4) {
  console.log("[OK] Sifre metni APK icinde bulunamadi.");
} else {
  console.log("[ATLANDI] Sifre metni taramasi icin .env'de YONETICI_SIFRE_ADI tanimli degil.");
  console.log("       (Bu deger sadece yerel taramadir; APK'ya gomulmez.)");
}

const yasakli = [
  ".env",
  "google-services.json",
  "GoogleService-Info.plist",
  ".jks",
  ".keystore",
  "key.properties",
  "serviceAccount",
  "private_key",
];

const adlar = (zipAdlar || "").toLowerCase();
const bulunanYasakli = yasakli.filter((y) => adlar.includes(y.toLowerCase()));

if (bulunanYasakli.length > 0) {
  console.error("[BASARISIZ] APK icinde gizli dosya kaliplari:", bulunanYasakli);
  hata++;
} else {
  console.log("[OK] APK icinde gizli dosya kalinti bulunamadi.");
}

console.log("");
if (hata > 0) {
  console.error(hata + " sizinti tespit edildi.");
  process.exit(1);
}

console.log("APK sizinti taramasi temiz.");
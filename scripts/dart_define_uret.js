// Flutter APK derleme komutunu .env degerleriyle uretir.
//
// Sifre ozeti kaynak kodda degil .env dosyasindadir. Bu script
// `--dart-define` bayraklarini hazirlayip ekrana yazar; boylece
// degeri terminale elle yazmaniza gerek kalmaz.
//
// Kullanim:
//   node scripts/dart_define_uret.js
//   node scripts/dart_define_uret.js --build            (release APK)
//   node scripts/dart_define_uret.js --build web

const { dartDefineDegerleri } = require("./ortam_yardimci");

const args = process.argv.slice(2);
const derleMi = args.includes("--build");

// --build verildiginde hemen ardindaki deger hedef olur (apk, appbundle, web).
// Verilmezse varsayilan apk'tir.
let hedef = "apk";
if (derleMi) {
  const sonraki = args[args.indexOf("--build") + 1];
  if (sonraki && !sonraki.startsWith("--")) hedef = sonraki;
}

const degerler = dartDefineDegerleri();

if (!degerler.YONETICI_SIFRE_HASH) {
  console.error("HATA: .env icinde YONETICI_SIFRE_HASH tanimli degil.");
  console.error("Kok .env dosyasini olusturun veya ornekten kopyalayin.");
  process.exit(1);
}

const bayraklar = [
  `--dart-define=YONETICI_SIFRE_HASH=${degerler.YONETICI_SIFRE_HASH}`,
  `--dart-define=YONETICI_DOGRULAMA_URL=${degerler.YONETICI_DOGRULAMA_URL || ""}`,
];

const flutterArgs =
  hedef === "apk"
    ? ["build", "apk", "--release", ...bayraklar]
    : ["build", hedef, "--release", ...bayraklar];

const komut = `flutter ${flutterArgs.join(" ")}`;

console.log("# .env degerlerinden uretilen derleme komutu:\n");
console.log(komut);

if (!derleMi) {
  console.log("\n# Derlemek icin: node scripts/dart_define_uret.js --build");
  process.exit(0);
}

console.log("\n# Derleme basliyor...");
const { execFileSync } = require("child_process");

try {
  execFileSync("flutter", flutterArgs, { stdio: "inherit", shell: true });
  console.log("\nDerleme tamamlandi.");
} catch (hata) {
  console.error("\nDerleme basarisiz:", hata.message);
  process.exit(1);
}
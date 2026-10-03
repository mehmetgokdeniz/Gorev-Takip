// Functions dosyasini gercekten yukleyip trigg'leri kontrol eder.
// Kullanım: node scripts/functions_kontrol.js
process.env.FUNCTIONS_EMULATOR = "false";

const functions = require("../functions/index.js");

const beklenen = [
  "ogrenciyeGorevAtandi",
  "onayaGonderildi",
  "gorevOnaylandi",
];

const mevcut = Object.keys(functions);
console.log("Yuklenen fonksiyonlar:", mevcut);

const eksikler = beklenen.filter((ad) => !mevcut.includes(ad));
if (eksikler.length > 0) {
  console.error("EKSIK FONKSIYONLAR:", eksikler);
  process.exit(1);
}

console.log("Tum beklenen trigger'lar mevcut.");
// Ortam degiskeni okuyucu.
//
// Amac: gizli degerleri kaynak koda gommeden tutmak.
// `functions/.env` dosyasi okunur ve process.env icine yazilir.
// Bir anahtar zaten process.env icinde varsa (.env dosyasi DEGIL,
// gercek ortam degiskeni onceliklidir) .env degeri EZILMEZ.
//
// Not: Bu dosya `node_modules` gerektirmez; ek paket kullanilmaz.
// Deploy sirasinda .env dosyasi yuklenmez. Canli ortamda degeri
// Firebase Console > Functions > Environment variables bolumunden
// tanimlayin (bkz. README.md).

const fs = require("fs");
const path = require("path");

const ENV_DOSYASI = path.join(__dirname, ".env");

// .env satirini KEY=DEGER olarak ayristirir.
//   - # ile baslayan satirlar yorumdur
//   - bos satirlar atlanir
//   - tirnak icindeki degerler kirpilmadan alinir
function satiriAyikla(satir) {
  const temiz = satir.trim();
  if (temiz === "" || temiz.startsWith("#")) return null;

  const ayirac = temiz.indexOf("=");
  if (ayirac < 1) return null;

  const anahtar = temiz.slice(0, ayirac).trim();
  if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(anahtar)) return null;

  let deger = temiz.slice(ayirac + 1).trim();

  if (
    (deger.startsWith('"') && deger.endsWith('"') && deger.length >= 2) ||
    (deger.startsWith("'") && deger.endsWith("'") && deger.length >= 2)
  ) {
    deger = deger.slice(1, -1);
  }

  return { anahtar, deger };
}

// .env dosyasini yukler. Dosya yoksa sessizce gecer.
// Donus: { anahtar: deger } sozlugu.
function envOku(dosyaYolu = ENV_DOSYASI) {
  const sonuc = {};
  if (!fs.existsSync(dosyaYolu)) return sonuc;

  const icerik = fs.readFileSync(dosyaYolu, "utf8");
  for (const satir of icerik.split(/\r?\n/)) {
    const ayiklanmis = satiriAyikla(satir);
    if (ayiklanmis) sonuc[ayiklanmis.anahtar] = ayiklanmis.deger;
  }
  return sonuc;
}

// process.env gercek ortam degiskenlerine oncelik verir.
// Yalnizca eksik anahtarlar .env dosyasindan doldurulur.
function yukle(dosyaYolu = ENV_DOSYASI) {
  const dosyaDegerleri = envOku(dosyaYolu);

  for (const [anahtar, deger] of Object.entries(dosyaDegerleri)) {
    if (process.env[anahtar] === undefined || process.env[anahtar] === "") {
      process.env[anahtar] = deger;
    }
  }

  return process.env;
}

module.exports = { yukle, envOku, satiriAyikla, ENV_DOSYASI };
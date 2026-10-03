// Ortam degiskenlerini okumak icin ortak yardimci.
// Kaynak kodda gizli deger TUTULMAZ; her sey .env dosyasindan okunur.
const path = require("path");
const ortam = require("../functions/ortam");

const KOK = path.join(__dirname, "..");

// Kok .env dosyasini okur. Dosya yoksa {} doner.
function kokEnvOku() {
  return ortam.envOku(path.join(KOK, ".env"));
}

/**
 * Yonetici sifresinin SHA-256 ozetini dondurur.
 *
 * Oncelik sirasi:
 *   1) Gercek ortam degiskeni (process.env)
 *   2) Kok .env dosyasi
 *   3) functions/.env dosyasi
 *
 * Hicbiri yoksa null doner; cagiran taraf bunu hata olarak ele almalidir.
 */
function yoneticiOzeti() {
  const deger =
    process.env.YONETICI_SIFRE_OZET ||
    kokEnvOku().YONETICI_SIFRE_OZET ||
    ortam.envOku().YONETICI_SIFRE_OZET ||
    "";

  const temiz = String(deger).trim().toLowerCase();
  if (!/^[a-f0-9]{64}$/.test(temiz)) return null;
  return temiz;
}

/** Derleme icin gomulecek --dart-define degerlerini dondurur. */
function dartDefineDegerleri() {
  const kok = kokEnvOku();
  return {
    YONETICI_SIFRE_HASH: process.env.YONETICI_SIFRE_HASH || kok.YONETICI_SIFRE_HASH || "",
    YONETICI_DOGRULAMA_URL: process.env.YONETICI_DOGRULAMA_URL || kok.YONETICI_DOGRULAMA_URL || "",
  };
}

/**
 * Turkce karakterleri ASCII karsiliklarina indirger.
 *
 * PowerShell'e gecirilecek desenlerde Turkce harflerden kacinmak icin
 * gereklidir; aksi halde karsilastirma sessizce basarisiz olur.
 */
function asciiyeCevir(metin) {
  return String(metin)
    .replace(/ç/g, "c").replace(/Ç/g, "C")
    .replace(/ğ/g, "g").replace(/Ğ/g, "G")
    .replace(/ı/g, "i").replace(/İ/g, "I")
    .replace(/ö/g, "o").replace(/Ö/g, "O")
    .replace(/ş/g, "s").replace(/Ş/g, "S")
    .replace(/ü/g, "u").replace(/Ü/g, "U");
}

module.exports = {
  KOK,
  kokEnvOku,
  yoneticiOzeti,
  dartDefineDegerleri,
  asciiyeCevir,
};
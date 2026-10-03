// Yonetici sifresi dogrulama fonksiyonu.
// Sifre DOGRULANMAZ, yalnizca SHA-256 ozeti karsilastirilir.
// Gercek sifre ne uygulamada ne de bu dosyada tutulur.
//
// Beklenen ortam degiskeni: YONETICI_SIFRE_OZET
//   - Lokal: functions/.env dosyasindan okunur (ortam.js)
//   - Canli: Firebase Console > Functions > Environment variables

const { createHash, timingSafeEqual } = require("crypto");

const { logger } = require("firebase-functions");

require("./ortam").yukle();

// Bos sifrenin SHA-256 ozeti. Bir yonetici sifresi bu degere
// esittiyse bos birakilmis demektir ve oyle kalsabilir: herkes
// yonetici olabilirdi. Bu yuzden bu deger ASLA kabul edilmez.
const BOS_SIFRE_OZETI =
  "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855";

function beklenenOzetiGetir() {
  const ham = (process.env.YONETICI_SIFRE_OZET || "").trim().toLowerCase();
  if (!/^[a-f0-9]{64}$/.test(ham)) return "";
  return ham;
}

function guvenliKarsilastir(a, b) {
  if (typeof a !== "string" || typeof b !== "string") return false;

  // Hex ozetler her zaman ayni uzunluktadir (64 karakter), bu yuzden
  // once uzunluk kontrolu yapip ardindan timingSafeEqual kullanilir.
  // Bu, uzunluk farkini sifrelemeden once kontrol ederek
  // karsilastirmayi zamanlama sizintisindan korur.
  if (a.length !== b.length) return false;

  const bufA = Buffer.from(a, "utf8");
  const bufB = Buffer.from(b, "utf8");

  return timingSafeEqual(bufA, bufB);
}

exports.dogrula = async (req, res) => {
  if (req.method !== "POST") {
    return res.status(405).json({ hata: "Yalnizca POST desteklenir." });
  }

  // Yonetici sifresi tanimlanmamissa kimse giremez. Sessizce
  // bos hash ile gecmeye calismak yerine hata dondurulur.
  const beklenen = beklenenOzetiGetir();
  if (!beklenen || beklenen === BOS_SIFRE_OZETI) {
    logger.error(
      "YONETICI_SIFRE_OZETI tanimli degil veya bos birakilmis. " +
        "Firebase Console > Functions > Environment variables bolumunu ayarlayin.",
    );
    return res.status(503).json({ hata: "Yapilandirma hatasi." });
  }

  const ham = (req.body && req.body.sifreOzeti) || "";

  if (typeof ham !== "string") {
    return res.status(400).json({ hata: "Gecersiz istek." });
  }

  // SHA-256 ozeti hex encoding'dir; buyuk/kucuk harf ayni ozeti
  // temsil eder. Kullanici/istemci buyuk harf gonderirse reddetmek
  // dogru davranis degil, once normalize ediyoruz.
  const ozet = ham.trim().toLowerCase();

  if (!/^[a-f0-9]{64}$/.test(ozet)) {
    return res.status(400).json({ hata: "Gecersiz istek." });
  }

  // Bos sifre korumasi: bos sifrenin ozeti sabit bir deger oldugu
  // icin, sunucudaki hash bu deger ile esitse herkes yonetici
  // olabilirdi.
  if (ozet === BOS_SIFRE_OZETI) {
    return res.status(401).json({ ok: false });
  }

  if (guvenliKarsilastir(ozet, beklenen)) {
    return res.status(200).json({ ok: true });
  }

  return res.status(401).json({ ok: false });
};
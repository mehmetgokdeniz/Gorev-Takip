// Sifre dogrulama fonksiyonunun mantigini test eder.
// Gercek Firebase bagimligi olmadan, dogrulama algoritmasini dogrular.
//
// Dogru sifre ozeti kaynak kodda TUTULMAZ; .env dosyasindan okunur.
// .env okunamazsa testler dogru ozeti bilemedigi icin atlanir.
//
// Kullanim: node scripts/sifre_testi.js

const path = require("path");
const Module = require("module");

const { yoneticiOzeti } = require("./ortam_yardimci");

// Dogrulama fonksiyonu process.env.YONETICI_SIFRE_OZET okur;
// ortam.js bu degiskeni .env dosyasindan doldurur.
const sifreDogrula = require(path.join(__dirname, "..", "functions", "sifre_dogrula.js"));

function sahteYanit() {
  return {
    durum: null,
    govde: null,
    status(kod) {
      this.durum = kod;
      return this;
    },
    json(veri) {
      this.govde = veri;
      return this;
    },
  };
}

async function dogrula(istek) {
  const req = { method: istek.method || "POST", body: istek.body };
  const res = sahteYanit();
  await sifreDogrula.dogrula(req, res);
  return res;
}

(async () => {
  const dogruOzet = yoneticiOzeti();

  if (!dogruOzet) {
    console.error("HATA: YONETICI_SIFRE_OZET .env dosyasinda bulunamadi.");
    console.error("Kok .env dosyasina dogru 64 karakterlik hex ozeti yazin.");
    process.exit(1);
  }

  const yanlisOzet = "a".repeat(64);
  let hata = 0;
  const gecti = [];

  function kontrol(ad, kosul, mesaj) {
    if (kosul) {
      console.log("OK: " + ad);
      gecti.push(ad);
    } else {
      console.error("HATA: " + ad + " -> " + mesaj);
      hata++;
    }
  }

  // 1) Dogru ozet kabul edilmeli
  let r = await dogrula({ body: { sifreOzeti: dogruOzet } });
  kontrol("dogru sifre kabul edildi (200)", r.durum === 200, "durum " + r.durum);

  // 2) Yanlis ozet reddedilmeli
  r = await dogrula({ body: { sifreOzeti: yanlisOzet } });
  kontrol("yanlis sifre reddedildi (401)", r.durum === 401, "durum " + r.durum);

  // 3) Bos/eksik veri reddedilmeli
  r = await dogrula({ body: {} });
  kontrol("bos istek reddedildi (400)", r.durum === 400, "durum " + r.durum);

  // 4) Hatali bicim (kisa/uzun olmayan) reddedilmeli
  r = await dogrula({ body: { sifreOzeti: "kisa" } });
  kontrol("gecersiz bicim reddedildi (400)", r.durum === 400, "durum " + r.durum);

  // 5) GET metodu reddedilmeli
  r = await dogrula({ method: "GET", body: { sifreOzeti: dogruOzet } });
  kontrol("GET reddedildi (405)", r.durum === 405, "durum " + r.durum);

  // 6) Buyuk/kucuk harf duyarsiz olmali
  r = await dogrula({ body: { sifreOzeti: dogruOzet.toUpperCase() } });
  kontrol("buyuk/kucuk harf duyarsiz (200)", r.durum === 200, "durum " + r.durum);

  // 7) Bos string sifreOzeti reddedilmeli
  r = await dogrula({ body: { sifreOzeti: "" } });
  kontrol("bos string reddedildi (400)", r.durum === 400, "durum " + r.durum);

  // 8) Bos sifrenin ozeti ASLA kabul edilmemeli.
  r = await dogrula({
    body: {
      sifreOzeti: "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
    },
  });
  kontrol("bos sifre reddedildi (401)", r.durum === 401, "durum " + r.durum);

  // 9) Gecersiz hex reddedilmeli
  r = await dogrula({ body: { sifreOzeti: "z".repeat(64) } });
  kontrol("gecersiz hex reddedildi (400)", r.durum === 400, "durum " + r.durum);

  // 10) Hatali/eksik YONETICI_SIFRE_OZET taniminda kimse girememeli.
  //
  // Bu, gomulu hash yerine yalnizca ortam degiskeni kullanmanin
  // dogrulamasidir: defer hatali tanimlanirsa fonksiyon 503 doner.
  //
  // NOT: Bos string KULLANILMAZ; ortam yukleyici (.env) bos degeri
  // .env dosyasindan tekrar doldurur ve test yaniltici olur.
  // Bunun yerine BOZUK (gecersiz bicimli) degerler denenir; bunlar
  // .env'den ezilmez ve beklenen 503 doner.
  const bozukDegerler = [
    ["gecersiz bicimli ozet", "kisa-deger"],
    ["bosluk karakterli ozet", "   "],
    ["bos sifrenin ozeti", "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"],
  ];

  const fonksiyonYolu = path.join(__dirname, "..", "functions", "sifre_dogrula.js");

  for (const [ad, bozukDeger] of bozukDegerler) {
    const kaydedilmis = process.env.YONETICI_SIFRE_OZET;
    process.env.YONETICI_SIFRE_OZET = bozukDeger;

    delete require.cache[require.resolve(fonksiyonYolu)];
    const bozukOrtamli = require(fonksiyonYolu);

    const bozukRes = sahteYanit();
    await bozukOrtamli.dogrula(
      { method: "POST", body: { sifreOzeti: dogruOzet } },
      bozukRes
    );

    kontrol(
      ad + " taniminda giris reddedildi (503)",
      bozukRes.durum === 503,
      "durum " + bozukRes.durum
    );

    if (kaydedilmis) process.env.YONETICI_SIFRE_OZET = kaydedilmis;
  }

  delete require.cache[require.resolve(fonksiyonYolu)];

  console.log("");
  if (hata > 0) {
    console.error(hata + " test basarisiz.");
    process.exit(1);
  }

  console.log("Tum sifre dogrulama testleri gecti (" + gecti.length + "/" + gecti.length + ").");
})();
const { onDocumentCreated, onDocumentUpdated } = require("firebase-functions/v2/firestore");
const { onRequest } = require("firebase-functions/v2/https");
const { logger } = require("firebase-functions");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");

require("./ortam").yukle();

initializeApp();

const db = getFirestore();

// Bildirim hedefleri: yonetici sabit bir belgede, ogrenci kendi belgesinde.
const YONETICI_KOLEKSIYON = "ayarlar";
const YONETICI_BELGE = "yonetici";
const OGRENCI_KOLEKSIYON = "ogrenciler";

// Uygulama icinde gosterilecek bildirim turleri.
// Uygulamadaki `BildirimTuru` enum ile birebir eslesmelidir.
const TUR = {
  GOREV_ATANDI: "gorev_atanldi",
  ONAYA_GONDERILDI: "onay_bekliyor",
  ONAYLANDI: "onaylandi",
};

const sifreDogrula = require("./sifre_dogrula");

// Yonetici sifresini dogrular. Uygulama sadece SHA-256 ozetini gonderir.
exports.yoneticiSifresiDogrula = onRequest(
  { cors: true },
  sifreDogrula.dogrula
);

// Bir kullanıcının bildirim token'larını toplar.
// Hem dizi alanından hem de tokens alt koleksiyonundan okur,
// böylece birden fazla cihazda çalışan kullanıcılar desteklenir.
async function tokenlariGetir(koleksiyonYolu, belgeId) {
  const tokenler = new Set();

  const belgeRef = db.doc(`${koleksiyonYolu}/${belgeId}`);
  const belge = await belgeRef.get();
  if (belge.exists) {
    const dizi = belge.data().bildirimTokenleri;
    if (Array.isArray(dizi)) {
      dizi.forEach((t) => {
        if (typeof t === "string" && t.length > 0) tokenler.add(t);
      });
    }
  }

  const alt = await belgeRef.collection("tokens").get();
  alt.docs.forEach((d) => tokenler.add(d.id));

  return Array.from(tokenler);
}

// Geçersiz token'ları iki yerden de temizler.
// Alan yoksa update() hata verir; bu yüzden her iki adım da
// bağımsız olarak korunur.
async function tokenlariTemizle(koleksiyonYolu, belgeId, gecersizler) {
  if (gecersizler.length === 0) return;

  const belgeRef = db.doc(`${koleksiyonYolu}/${belgeId}`);

  try {
    await belgeRef.update({
      bildirimTokenleri: FieldValue.arrayRemove(...gecersizler),
    });
  } catch (hata) {
    logger.warn("Dizi alanindan token temizlenemedi.", {
      belge: `${koleksiyonYolu}/${belgeId}`,
      hata: String(hata),
    });
  }

  try {
    const batch = db.batch();
    gecersizler.forEach((token) =>
      batch.delete(belgeRef.collection("tokens").doc(token))
    );
    await batch.commit();
  } catch (hata) {
    logger.warn("Alt koleksiyondan token temizlenemedi.", {
      belge: `${koleksiyonYolu}/${belgeId}`,
      hata: String(hata),
    });
  }

  logger.info(`${gecersizler.length} geçersiz token temizlendi: ${koleksiyonYolu}/${belgeId}`);
}

// Token'lara bildirim gönderir. Hatalı/geçersiz token'ları temizler.
async function bildirimGonder(tokenler, baslik, govde, veri) {
  if (tokenler.length === 0) {
    logger.warn("Gönderilecek token yok, bildirim atlandı.", { baslik });
    return;
  }

  const gonderilen = [];
  const gecersizler = [];

  for (const token of tokenler) {
    try {
      await getMessaging().send({
        token: token,
        notification: { title: baslik, body: govde },
        data: veri,
        android: {
          priority: "high",
          notification: { channelId: "gorev_bildirimleri", icon: "ic_notification" },
        },
        apns: {
          payload: { aps: { sound: "default", badge: 1 } },
        },
      });
      gonderilen.push(token);
    } catch (hata) {
      const kod = hata.code || "";
      const mesaj = hata.message || "";

      if (
        kod === "messaging/registration-token-not-registered" ||
        kod === "messaging/invalid-registration-token" ||
        mesaj.includes("registration-token-not-registered") ||
        mesaj.includes("InvalidRegistrationToken")
      ) {
        gecersizler.push(token);
      } else {
        logger.error("Bildirim gönderilemedi.", { token, hata: mesaj });
      }
    }
  }

  logger.info("Bildirim gönderildi.", { baslik, basarili: gonderilen.length, hatali: gecersizler.length });

  return { gonderilen, gecersizler };
}

// Uygulama içi bildirim listesinin kaynağı.
// Push bildirim kaliciye girmeden once buraya yazilir; boylece
// uygulama icinde "hangi bildirimler var" sorusu Firestore'dan
// yanitlanabilir ve cihaz degistiginde gecmis kaybolmaz.
async function bildirimKaydet({
  hedefKoleksiyon,
  hedefBelge,
  tur,
  baslik,
  govde,
  gorevId,
  ogrenciId,
}) {
  try {
    await db.collection(hedefKoleksiyon).doc(hedefBelge).collection("bildirimler").add({
      tur,
      baslik,
      govde,
      gorevId: gorevId || "",
      ogrenciId: ogrenciId || "",
      okundu: false,
      zaman: FieldValue.serverTimestamp(),
    });
  } catch (hata) {
    // Bildirim geçmişi yazılamazsa push bildirimi yine de gider.
    logger.error("Bildirim kaydı yazılamadı.", { tur, hata: String(hata) });
  }
}

// Hem push gönderir hem uygulama içi kayıt yazar.
async function bildir({ hedefKoleksiyon, hedefBelge, tur, baslik, govde, gorevId, ogrenciId }) {
  await bildirimKaydet({
    hedefKoleksiyon,
    hedefBelge,
    tur,
    baslik,
    govde,
    gorevId,
    ogrenciId,
  });

  const tokenler = await tokenlariGetir(hedefKoleksiyon, hedefBelge);
  const sonuc = await bildirimGonder(tokenler, baslik, govde, {
    tur,
    gorevId: gorevId || "",
    ogrenciId: ogrenciId || "",
  });

  if (sonuc) await tokenlariTemizle(hedefKoleksiyon, hedefBelge, sonuc.gecersizler);
}

// Yöneticiye bildirim (öğrenci ödevi onaya gönderdiğinde).
async function yoneticiyeBildir(baslik, govde, veri) {
  return bildir({
    hedefKoleksiyon: YONETICI_KOLEKSIYON,
    hedefBelge: YONETICI_BELGE,
    baslik,
    govde,
    gorevId: veri.gorevId,
    ogrenciId: veri.ogrenciId,
  });
}

// Öğrenciye bildirim (görev atandığında veya ödev onaylandığında).
async function ogrenciyeBildir(ogrenciId, baslik, govde, veri) {
  return bildir({
    hedefKoleksiyon: OGRENCI_KOLEKSIYON,
    hedefBelge: ogrenciId,
    tur: veri.tur,
    baslik,
    govde,
    gorevId: veri.gorevId,
    ogrenciId,
  });
}

// Yönetici yeni görev atadığında öğrenciye bildirim gider.
exports.ogrenciyeGorevAtandi = onDocumentCreated("gorevler/{gorevId}", async (event) => {
  const gorev = event.data?.data();
  if (!gorev) return;

  const ogrenciId = gorev.ogrenciId;
  if (!ogrenciId) {
    logger.warn("Görevde ogrenciId yok, bildirim atlandı.");
    return;
  }

  const ogrenciBelge = await db.doc(`${OGRENCI_KOLEKSIYON}/${ogrenciId}`).get();
  const adSoyad = ogrenciBelge.data()?.adSoyad || "";

  await ogrenciyeBildir(
    ogrenciId,
    "Yeni Görev Atandı",
    `${adSoyad ? adSoyad + " için" : "Sana"} yeni bir görev atandı: ${gorev.baslik || ""}`.trim(),
    {
      tur: TUR.GOREV_ATANDI,
      gorevId: event.params.gorevId,
      ogrenciId: ogrenciId,
    }
  );
});

// Öğrenci ödevi onaya gönderdiğinde yöneticiye bildirim gider.
exports.onayaGonderildi = onDocumentUpdated("gorevler/{gorevId}", async (event) => {
  const sonraki = event.data?.after.data();
  const onceki = event.data?.before.data();
  if (!sonraki || !onceki) return;

  if (sonraki.durum !== "onay_bekliyor" || onceki.durum === "onay_bekliyor") return;

  const ogrenciId = sonraki.ogrenciId;
  let adSoyad = "";

  if (ogrenciId) {
    const ogrenciBelge = await db.doc(`${OGRENCI_KOLEKSIYON}/${ogrenciId}`).get();
    adSoyad = ogrenciBelge.data()?.adSoyad || "";
  }

  const gonderen = adSoyad ? adSoyad : "Bir öğrenci";
  await yoneticiyeBildir(
    "Ödev Onaya Gönderildi",
    `${gonderen} "${sonraki.baslik || "görev"}" ödevini onaya gönderdi.`,
    {
      tur: TUR.ONAYA_GONDERILDI,
      gorevId: event.params.gorevId,
      ogrenciId: ogrenciId || "",
    }
  );
});

// Yönetici ödevi onayladığında öğrenciye bildirim gider.
exports.gorevOnaylandi = onDocumentUpdated("gorevler/{gorevId}", async (event) => {
  const sonraki = event.data?.after.data();
  const onceki = event.data?.before.data();
  if (!sonraki || !onceki) return;

  if (sonraki.durum !== "onaylandi" || onceki.durum === "onaylandi") return;

  const ogrenciId = sonraki.ogrenciId;
  if (!ogrenciId) return;

  await ogrenciyeBildir(
    ogrenciId,
    "Ödevin Onaylandı!",
    `"${sonraki.baslik || "Görev"}" ödevin onaylandı. Tebrikler!`,
    {
      tur: TUR.ONAYLANDI,
      gorevId: event.params.gorevId,
      ogrenciId: ogrenciId,
    }
  );
});
// Uygulama ikonunu üretir: SVG -> PNG (Android/iOS/web boyutları)
// Kullanım: node scripts/ikon_uret.js
const fs = require("fs");
const path = require("path");
const sharp = require("sharp");

const KOK = path.join(__dirname, "..");
const SVG = `
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <defs>
    <linearGradient id="arka" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0%" stop-color="#1A1030"/>
      <stop offset="55%" stop-color="#2D1B4E"/>
      <stop offset="100%" stop-color="#0D0F12"/>
    </linearGradient>
    <linearGradient id="vurgu" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0%" stop-color="#BA68C8"/>
      <stop offset="100%" stop-color="#7C3AED"/>
    </linearGradient>
    <linearGradient id="nokta" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0%" stop-color="#00E676"/>
      <stop offset="100%" stop-color="#00A152"/>
    </linearGradient>
  </defs>

  <rect width="1024" height="1024" rx="230" fill="url(#arka)"/>

  <!-- kontrol listesi formu -->
  <rect x="248" y="216" width="440" height="592" rx="54" fill="#0B0D10" opacity="0.74"/>
  <rect x="248" y="216" width="440" height="88" rx="54" fill="url(#vurgu)"/>
  <rect x="248" y="276" width="440" height="28" fill="url(#vurgu)"/>
  <circle cx="310" cy="260" r="19" fill="#FFFFFF" opacity="0.95"/>
  <circle cx="376" cy="260" r="19" fill="#FFFFFF" opacity="0.6"/>
  <circle cx="442" cy="260" r="19" fill="#FFFFFF" opacity="0.35"/>

  <!-- onayli satirlar -->
  <g>
    <rect x="300" y="356" width="68" height="68" rx="19" fill="url(#nokta)"/>
    <path d="M321 390 L335 404 L352 373" stroke="#0B0D10" stroke-width="17" stroke-linecap="round" stroke-linejoin="round" fill="none"/>
    <rect x="398" y="374" width="242" height="32" rx="16" fill="#FFFFFF" opacity="0.82"/>
  </g>
  <g>
    <rect x="300" y="464" width="68" height="68" rx="19" fill="url(#vurgu)"/>
    <path d="M321 498 L335 512 L352 481" stroke="#FFFFFF" stroke-width="17" stroke-linecap="round" stroke-linejoin="round" fill="none"/>
    <rect x="398" y="482" width="200" height="32" rx="16" fill="#FFFFFF" opacity="0.55"/>
  </g>
  <g>
    <rect x="300" y="572" width="68" height="68" rx="19" fill="none" stroke="#FFFFFF" stroke-width="11" opacity="0.38"/>
    <rect x="398" y="590" width="218" height="32" rx="16" fill="#FFFFFF" opacity="0.3"/>
  </g>

  <!-- konum pini (formun disinda, sag alt) -->
  <g transform="translate(716 700)">
    <path d="M0 96 C-58 -34 -110 -96 -110 -158 C-110 -228 -60 -278 0 -278 C60 -278 110 -228 110 -158 C110 -96 58 -34 0 96 Z" fill="#0D0F12" opacity="0.45" transform="translate(6 10)"/>
    <path d="M0 96 C-58 -34 -110 -96 -110 -158 C-110 -228 -60 -278 0 -278 C60 -278 110 -228 110 -158 C110 -96 58 -34 0 96 Z" fill="url(#nokta)"/>
    <circle cx="0" cy="-158" r="44" fill="#0D0F12"/>
  </g>
</svg>`;

const HEDEFLER = [
  { dosya: "android/app/src/main/res/mipmap-mdpi/ic_launcher.png", boyut: 48 },
  { dosya: "android/app/src/main/res/mipmap-hdpi/ic_launcher.png", boyut: 72 },
  { dosya: "android/app/src/main/res/mipmap-xhdpi/ic_launcher.png", boyut: 96 },
  { dosya: "android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png", boyut: 144 },
  { dosya: "android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png", boyut: 192 },
  { dosya: "android/app/src/main/res/drawable/ic_notification.png", boyut: 192 },
  { dosya: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png", boyut: 1024 },
  { dosya: "web/icons/Icon-192.png", boyut: 192 },
  { dosya: "web/icons/Icon-512.png", boyut: 512 },
  { dosya: "web/favicon.png", boyut: 32 },
];

// Adaptive icon foreground: arka plan saydam, cografi 66dp guvenli alana ortalanir.
// Ana ikon 1024 tabanli oldugu icin 1024 * (66/108) = 626 olarak olceklenir.
const FOREGROUND_SVG = `
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <defs>
    <linearGradient id="vurgu" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0%" stop-color="#BA68C8"/>
      <stop offset="100%" stop-color="#7C3AED"/>
    </linearGradient>
    <linearGradient id="nokta" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0%" stop-color="#00E676"/>
      <stop offset="100%" stop-color="#00A152"/>
    </linearGradient>
  </defs>

  <g transform="translate(512 512) scale(0.55) translate(-512 -512)">
    <rect x="248" y="216" width="440" height="592" rx="54" fill="#0B0D10" opacity="0.82"/>
    <rect x="248" y="216" width="440" height="88" rx="54" fill="url(#vurgu)"/>
    <rect x="248" y="276" width="440" height="28" fill="url(#vurgu)"/>
    <circle cx="310" cy="260" r="19" fill="#FFFFFF" opacity="0.95"/>
    <circle cx="376" cy="260" r="19" fill="#FFFFFF" opacity="0.6"/>
    <circle cx="442" cy="260" r="19" fill="#FFFFFF" opacity="0.35"/>

    <rect x="300" y="356" width="68" height="68" rx="19" fill="url(#nokta)"/>
    <path d="M321 390 L335 404 L352 373" stroke="#0B0D10" stroke-width="17" stroke-linecap="round" stroke-linejoin="round" fill="none"/>
    <rect x="398" y="374" width="242" height="32" rx="16" fill="#FFFFFF" opacity="0.82"/>

    <rect x="300" y="464" width="68" height="68" rx="19" fill="url(#vurgu)"/>
    <path d="M321 498 L335 512 L352 481" stroke="#FFFFFF" stroke-width="17" stroke-linecap="round" stroke-linejoin="round" fill="none"/>
    <rect x="398" y="482" width="200" height="32" rx="16" fill="#FFFFFF" opacity="0.55"/>

    <rect x="300" y="572" width="68" height="68" rx="19" fill="none" stroke="#FFFFFF" stroke-width="11" opacity="0.38"/>
    <rect x="398" y="590" width="218" height="32" rx="16" fill="#FFFFFF" opacity="0.3"/>

    <g transform="translate(716 700)">
      <path d="M0 96 C-58 -34 -110 -96 -110 -158 C-110 -228 -60 -278 0 -278 C60 -278 110 -228 110 -158 C110 -96 58 -34 0 96 Z" fill="url(#nokta)"/>
      <circle cx="0" cy="-158" r="44" fill="#0D0F12"/>
    </g>
  </g>
</svg>`;

// Adaptive foreground her yogunluk icin 108dp olmali.
const FOREGROUND_HEDEFLER = [
  { dosya: "android/app/src/main/res/mipmap-mdpi/ic_launcher_foreground.png", dp: 108 },
  { dosya: "android/app/src/main/res/mipmap-hdpi/ic_launcher_foreground.png", dp: 162 },
  { dosya: "android/app/src/main/res/mipmap-xhdpi/ic_launcher_foreground.png", dp: 216 },
  { dosya: "android/app/src/main/res/mipmap-xxhdpi/ic_launcher_foreground.png", dp: 324 },
  { dosya: "android/app/src/main/res/mipmap-xxxhdpi/ic_launcher_foreground.png", dp: 432 },
];

(async () => {
  const svgBuffer = Buffer.from(SVG);

  for (const hedef of HEDEFLER) {
    const tamYol = path.join(KOK, hedef.dosya);
    fs.mkdirSync(path.dirname(tamYol), { recursive: true });
    await sharp(svgBuffer, { density: 384 })
      .resize(hedef.boyut, hedef.boyut, { fit: "fill" })
      .png()
      .toFile(tamYol);
    console.log("okundu:", hedef.dosya, hedef.boyut + "px");
  }

  const foregroundBuffer = Buffer.from(FOREGROUND_SVG);
  for (const hedef of FOREGROUND_HEDEFLER) {
    const tamYol = path.join(KOK, hedef.dosya);
    fs.mkdirSync(path.dirname(tamYol), { recursive: true });
    await sharp(foregroundBuffer, { density: 384 })
      .resize(hedef.dp, hedef.dp, { fit: "fill" })
      .png()
      .toFile(tamYol);
    console.log("okundu:", hedef.dosya, hedef.dp + "px (adaptive foreground)");
  }

  console.log("Ikonlar uretildi.");
})();
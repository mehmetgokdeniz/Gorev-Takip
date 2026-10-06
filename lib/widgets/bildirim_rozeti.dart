import 'package:flutter/material.dart';

import '../screens/bildirimler_ekrani.dart';
import '../services/bildirim_servisi.dart';

/// AppBar'daki bildirim düğmesi ve okunmamış rozeti.
///
/// Zil ikonu iki ayrı ekranda (yönetici ve öğrenci paneli) tekrar
/// edilmişti; ikisi de aynı sayacı dinliyordu. Burada tek yerden
/// üretiliyor.
///
/// Sayı 9'dan büyükse `9+` gösterilir: rozet genişleyip AppBar'ı
/// kaydırmasın.
class BildirimRozeti extends StatelessWidget {
  final String belgeYolu;
  final String belgeId;

  /// Rozetten sonuç olarak öğrenci adını gösterecek mi?
  final bool ogrenciGosterilsin;

  /// Yönetici, listeden görev onaylayabilir mi?
  final bool onayVerilebilir;

  const BildirimRozeti({
    super.key,
    required this.belgeYolu,
    required this.belgeId,
    this.ogrenciGosterilsin = false,
    this.onayVerilebilir = false,
  });

  @override
  Widget build(BuildContext context) {
    final BildirimServisi servis = BildirimServisi.instance;

    return StreamBuilder<int>(
      stream: servis.okunmamisSayisi(belgeYolu, belgeId),
      builder: (context, anlik) {
        final int okunmamis = anlik.data ?? 0;

        return Stack(
          alignment: Alignment.center,
          children: [
            IconButton(
              tooltip: 'Bildirimler',
              icon: const Icon(Icons.notifications_outlined),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => BildirimlerEkrani(
                    belgeYolu: belgeYolu,
                    belgeId: belgeId,
                    ogrenciGosterilsin: ogrenciGosterilsin,
                    onayVerilebilir: onayVerilebilir,
                  ),
                ),
              ),
            ),
            if (okunmamis > 0)
              Positioned(
                right: 10,
                top: 10,
                child: IgnorePointer(
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.redAccent,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      okunmamis > 9 ? '9+' : '$okunmamis',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Bildirim listesini açan yardımcı.
///
/// [BildirimYonlendirici] de aynı ekranı açabilir; ayarları tek
/// yerde toplamak için burada merkezileştiriliyor.
Future<void> bildirimEkraniniAc(
  BuildContext context, {
  required String belgeYolu,
  required String belgeId,
  bool ogrenciGosterilsin = false,
  bool onayVerilebilir = false,
}) {
  return Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => BildirimlerEkrani(
        belgeYolu: belgeYolu,
        belgeId: belgeId,
        ogrenciGosterilsin: ogrenciGosterilsin,
        onayVerilebilir: onayVerilebilir,
      ),
    ),
  );
}
import 'package:flutter/material.dart';

import '../models/bildirim.dart';
import '../models/gorev.dart';
import '../services/bildirim_servisi.dart';
import 'gorev_detay_ekrani.dart';

/// Uygulama içi bildirim geçmişi.
///
/// Push bildirimlerin kalıcı kaydı Cloud Functions tarafından
/// `bildirimler` alt koleksiyonuna yazılır; bu ekran o kaydı okur.
/// Böylece bildirim cihazda kaybolsa bile liste korunur ve
/// kullanıcı eski bildirimlere geri dönebilir.
class BildirimlerEkrani extends StatelessWidget {
  /// Bildirimlerin ait olduğu belge (`ayarlar/yonetici` veya `ogrenciler/{id}`).
  final String belgeYolu;
  final String belgeId;

  /// Bildirimin ait olduğu öğrenciyi göster (yönetici ekranı).
  final bool ogrenciGosterilsin;

  /// Yönetici, bildirimden görevi onaylayabilsin.
  final bool onayVerilebilir;

  const BildirimlerEkrani({
    super.key,
    required this.belgeYolu,
    required this.belgeId,
    this.ogrenciGosterilsin = false,
    this.onayVerilebilir = false,
  });

  @override
  Widget build(BuildContext context) {
    final BildirimServisi servis = BildirimServisi.instance;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bildirimler', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF161B22),
        actions: [
          IconButton(
            tooltip: 'Tümünü okundu işaretle',
            icon: const Icon(Icons.mark_email_read_outlined),
            onPressed: () => servis.tumunuOkunduIsaretle(belgeYolu, belgeId),
          ),
        ],
      ),
      body: StreamBuilder<List<Bildirim>>(
        stream: servis.bildirimleriIzle(belgeYolu, belgeId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final List<Bildirim> bildirimler = snapshot.data ?? const [];
          if (bildirimler.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.notifications_off_outlined, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('Henüz bildirim yok.', style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: bildirimler.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final Bildirim bildirim = bildirimler[index];
              return _BildirimKarti(
                bildirim: bildirim,
                ogrenciGosterilsin: ogrenciGosterilsin,
                onayVerilebilir: onayVerilebilir,
                onTiklandi: () => _bildirimiAc(context, bildirim),
              );
            },
          );
        },
      ),
    );
  }

  /// Bildirime dokununca: okundu işaretle ve görev detayını aç.
  Future<void> _bildirimiAc(BuildContext context, Bildirim bildirim) async {
    final BildirimServisi servis = BildirimServisi.instance;
    await servis.okunduIsaretle(belgeYolu, belgeId, bildirim);

    if (!context.mounted) return;

    final String? gorevYolu = bildirim.gorevYolu;
    if (gorevYolu == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bu bildirim bir göreve bağlı değil.')),
      );
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => GorevDetayEkrani(
          gorevId: bildirim.gorevId,
          onayVerilebilir: onayVerilebilir,
        ),
      ),
    );
  }
}

class _BildirimKarti extends StatelessWidget {
  final Bildirim bildirim;
  final bool ogrenciGosterilsin;
  final bool onayVerilebilir;
  final VoidCallback onTiklandi;

  const _BildirimKarti({
    required this.bildirim,
    required this.ogrenciGosterilsin,
    required this.onayVerilebilir,
    required this.onTiklandi,
  });

  @override
  Widget build(BuildContext context) {
    final Color vurguRengi = _turRengi(bildirim.tur);

    return Card(
      color: bildirim.okundu ? const Color(0xFF161B22) : const Color(0xFF1E2430),
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: bildirim.okundu ? Colors.transparent : vurguRengi.withValues(alpha: 0.5),
        ),
      ),
      child: InkWell(
        onTap: onTiklandi,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: vurguRengi.withValues(alpha: 0.2),
                child: Icon(_turIkonu(bildirim.tur), color: vurguRengi, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            bildirim.baslik,
                            style: TextStyle(
                              fontWeight: bildirim.okundu ? FontWeight.w500 : FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        if (!bildirim.okundu)
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(color: vurguRengi, shape: BoxShape.circle),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      bildirim.govde,
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: vurguRengi.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            bildirim.tur.etiket,
                            style: TextStyle(color: vurguRengi, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const Spacer(),
                        if (bildirim.zaman != null)
                          Text(
                            _zamanBicimle(bildirim.zaman!),
                            style: const TextStyle(color: Colors.grey, fontSize: 11),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Color _turRengi(BildirimTuru tur) => switch (tur) {
        BildirimTuru.gorevAtanldi => Colors.orange,
        BildirimTuru.onayaGonderildi => Colors.blueAccent,
        BildirimTuru.onaylandi => Colors.greenAccent,
      };

  static IconData _turIkonu(BildirimTuru tur) => switch (tur) {
        BildirimTuru.gorevAtanldi => Icons.assignment_outlined,
        BildirimTuru.onayaGonderildi => Icons.hourglass_top_rounded,
        BildirimTuru.onaylandi => Icons.check_circle_outline,
      };

  static String _zamanBicimle(DateTime zaman) {
    final DateTime simdi = DateTime.now();
    final Duration fark = simdi.difference(zaman);

    if (fark.inMinutes < 1) return 'az önce';
    if (fark.inHours < 1) return '${fark.inMinutes} dk önce';
    if (fark.inDays < 1) return '${fark.inHours} sa önce';
    if (fark.inDays < 7) return '${fark.inDays} gün önce';
    return Gorev.tarihBicimle(zaman);
  }
}
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
class BildirimlerEkrani extends StatefulWidget {
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
  State<BildirimlerEkrani> createState() => _BildirimlerEkraniState();
}

class _BildirimlerEkraniState extends State<BildirimlerEkrani> {
  /// `null` → tüm bildirimler, aksi hâlde yalnız seçili tür.
  ///
  /// Yönetici ekranında varsayılan "onay bekleyenler"e daraltılır:
  /// yöneticinin işi onay bekleyen bildirimleri görmek, filtre zaten
  /// hazır geldiği için açılışta yükü değildir. Öğrenci ekranında filtre
  /// gösterilmez — hepsi kendi görevleriyle ilgili.
  BildirimTuru? _suzgec;

  @override
  void initState() {
    super.initState();
    if (widget.onayVerilebilir) _suzgec = BildirimTuru.onayaGonderildi;
  }

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
            onPressed: () => servis.tumunuOkunduIsaretle(
              widget.belgeYolu,
              widget.belgeId,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (widget.onayVerilebilir) _suzgecSeridi(),
          Expanded(
            child: StreamBuilder<List<Bildirim>>(
              stream: servis.bildirimleriIzle(
                widget.belgeYolu,
                widget.belgeId,
                // Yöneticiye yazan tek bildirim onaya-göndermedir; `tur`
                // alanı eksik olan eski kayıtlar da o türe sayılır.
                turVarsayilan: widget.onayVerilebilir ? BildirimTuru.onayaGonderildi : null,
              ),
              builder: (context, anlik) {
                if (anlik.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final List<Bildirim> tumu = anlik.data ?? const [];
                final List<Bildirim> bildirimler = _suzgec == null
                    ? tumu
                    : tumu.where((b) => b.tur == _suzgec).toList();

                if (tumu.isEmpty) return const _BosListe();
                if (bildirimler.isEmpty) return const _SuzgecBos();

                return ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: bildirimler.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final Bildirim bildirim = bildirimler[index];
                    return _BildirimKarti(
                      bildirim: bildirim,
                      ogrenciGosterilsin: widget.ogrenciGosterilsin,
                      onayVerilebilir: widget.onayVerilebilir,
                      onTiklandi: () => _bildirimiAc(context, bildirim),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _suzgecSeridi() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      color: const Color(0xFF161B22),
      child: Row(
        children: [
          _SuzgecCipi(
            etiket: 'Tümü',
            secili: _suzgec == null,
            vurguRengi: Colors.deepPurpleAccent,
            onTiklandi: () => setState(() => _suzgec = null),
          ),
          const SizedBox(width: 8),
          _SuzgecCipi(
            etiket: 'Onay bekleyen',
            secili: _suzgec == BildirimTuru.onayaGonderildi,
            vurguRengi: Colors.blueAccent,
            onTiklandi: () =>
                setState(() => _suzgec = BildirimTuru.onayaGonderildi),
          ),
          const SizedBox(width: 8),
          _SuzgecCipi(
            etiket: 'Onaylanan',
            secili: _suzgec == BildirimTuru.onaylandi,
            vurguRengi: Colors.greenAccent,
            onTiklandi: () => setState(() => _suzgec = BildirimTuru.onaylandi),
          ),
        ],
      ),
    );
  }

  /// Bildirime dokununca: okundu işaretle ve görev detayını aç.
  Future<void> _bildirimiAc(BuildContext context, Bildirim bildirim) async {
    final BildirimServisi servis = BildirimServisi.instance;
    await servis.okunduIsaretle(widget.belgeYolu, widget.belgeId, bildirim);

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
          onayVerilebilir: widget.onayVerilebilir,
        ),
      ),
    );
  }
}

class _SuzgecCipi extends StatelessWidget {
  final String etiket;
  final bool secili;
  final Color vurguRengi;
  final VoidCallback onTiklandi;

  const _SuzgecCipi({
    required this.etiket,
    required this.secili,
    required this.vurguRengi,
    required this.onTiklandi,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTiklandi,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: secili
                ? vurguRengi.withValues(alpha: 0.18)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: secili ? vurguRengi : Colors.white12,
            ),
          ),
          child: Text(
            etiket,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: secili ? FontWeight.bold : FontWeight.normal,
              color: secili ? vurguRengi : Colors.white60,
            ),
          ),
        ),
      ),
    );
  }
}

class _BosListe extends StatelessWidget {
  const _BosListe();

  @override
  Widget build(BuildContext context) {
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
}

class _SuzgecBos extends StatelessWidget {
  const _SuzgecBos();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.filter_alt_off_outlined, size: 64, color: Colors.grey),
          SizedBox(height: 16),
          Text('Bu filtreye uyan bildirim yok.', style: TextStyle(color: Colors.grey)),
        ],
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
                        // Yönetici bildirimde kimden geldiğini görsün.
                        if (ogrenciGosterilsin && bildirim.ogrenciId.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.white10,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                bildirim.ogrenciId,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        ],
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
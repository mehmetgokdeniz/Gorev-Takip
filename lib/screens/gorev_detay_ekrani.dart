import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/gorev.dart';
import '../services/gorsel_onbellek.dart';

/// Fotoğraf gösterir.
///
/// Önceden `Image.memory(base64Decode(...))` her karede yeniden decode
/// ediyordu; detay ekranı bir `StreamBuilder` içinde olduğu için her veri
/// gelişinde tüm fotoğraflar tekrar çözülüyordu. Artık çözüm bir kez
/// yapılıp önbelleğe yazılıyor.
Widget _gorsel(String yol, {BoxFit fit = BoxFit.cover}) {
  if (yol.isEmpty) return const Icon(Icons.broken_image);
  return OnbellekliGorsel(yol: yol, fit: fit);
}

/// Tek bir görevin tüm ayrıntıları.
///
/// Bildirimden, öğrenci takviminden veya yönetici listesinden
/// buraya geçilir. Başlangıç ve son tarih, durum, öğrenci notu ve
/// gönderilen fotoğraflar tek ekranda toplanır.
class GorevDetayEkrani extends StatefulWidget {
  final String gorevId;

  /// Görüntülenecek görev hazırsa (bildirimden gelirken) verilir.
  /// Boş bırakılırsa Firestore'dan dinlenerek çekilir.
  final Gorev? onGorev;

  /// Yönetici, görevi bu ekrandan onaylayabilir.
  final bool onayVerilebilir;

  /// Onay tamamlandığında çağrılır (yönetici paneli için).
  final VoidCallback? onaylandi;

  /// Öğrenci, görevi bu ekrandan onaya gönderebilir.
  final bool gonderimYapilabilir;

  final void Function(BuildContext context, String gorevId, String baslik)? onGonder;

  const GorevDetayEkrani({
    super.key,
    required this.gorevId,
    this.onGorev,
    this.onayVerilebilir = false,
    this.onaylandi,
    this.gonderimYapilabilir = false,
    this.onGonder,
  });

  @override
  State<GorevDetayEkrani> createState() => _GorevDetayEkraniState();
}

class _GorevDetayEkraniState extends State<GorevDetayEkrani> {
  /// Görev belgesinin stream'i.
  ///
  /// `build()` içinde kurulursa her yeniden çizimde yeni abonelik
  /// yapılır ve görev güncellendiğinde tekrar tetiklenir — döngü.
  /// `onGorev` verilmişse hiç kurulmaz.
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _gorevStream;

  @override
  void initState() {
    super.initState();
    _gorevStream = FirebaseFirestore.instance
        .collection('gorevler')
        .doc(widget.gorevId)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    final Gorev? onGorev = widget.onGorev;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Görev Detayı', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF161B22),
      ),
      body: onGorev != null
          ? _detayGovdesi(context, onGorev)
          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: _gorevStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || !snapshot.data!.exists) {
                  return const _BosDurum(
                    mesaj: 'Bu görev artık mevcut değil.',
                    ikon: Icons.search_off_rounded,
                  );
                }
                return _detayGovdesi(context, Gorev.dokumandan(snapshot.data!));
              },
            ),
    );
  }

  Widget _detayGovdesi(BuildContext context, Gorev gorev) {
    final Color durumRengi = _durumRengi(gorev.durum);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  gorev.baslik.isEmpty ? 'Başlıksız görev' : gorev.baslik,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: durumRengi.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: durumRengi, width: 1),
                  ),
                  child: Text(
                    gorev.durum.etiket,
                    style: TextStyle(color: durumRengi, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _tarihKarti(gorev),
        if (gorev.aciklama.isNotEmpty) ...[
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Öğrenci Notu', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(gorev.aciklama, style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.white70)),
                ],
              ),
            ),
          ),
        ],
        if (gorev.resimYollari.isNotEmpty) ...[
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Gönderilen Fotoğraflar (${gorev.resimYollari.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    itemCount: gorev.resimYollari.length,
                    itemBuilder: (context, index) {
                      final String yol = gorev.resimYollari[index];
                      return GestureDetector(
                        onTap: () => _gorseliBuyut(context, yol),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: _gorsel(yol),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
        if (gorev.sonTarihGecti && gorev.durum != GorevDurumu.onaylandi) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.redAccent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.redAccent),
            ),
            child: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
                SizedBox(width: 12),
                Expanded(child: Text('Son tarih geçti!', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold))),
              ],
            ),
          ),
        ],
        const SizedBox(height: 24),
        if (widget.onayVerilebilir && gorev.durum == GorevDurumu.onayBekliyor)
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: () async {
              await FirebaseFirestore.instance.collection('gorevler').doc(gorev.id).update({'durum': 'onaylandi'});
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ödev onaylandı.'), backgroundColor: Colors.green));
              widget.onaylandi?.call();
              Navigator.pop(context);
            },
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('Ödevi Onayla', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        if (widget.gonderimYapilabilir && gorev.durum == GorevDurumu.atanlandi)
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurpleAccent,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: () => widget.onGonder?.call(context, gorev.id, gorev.baslik),
            icon: const Icon(Icons.cloud_upload_outlined),
            label: const Text('Ödevi Gönder', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
      ],
    );
  }

  Widget _tarihKarti(Gorev gorev) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Tarihler', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _tarihSatiri(
                    ikon: Icons.play_circle_outline,
                    etiket: 'Başlangıç Tarihi',
                    tarih: gorev.baslangicTarihi,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _tarihSatiri(
                    ikon: Icons.flag_outlined,
                    etiket: 'Son Tarih',
                    tarih: gorev.sonTarihi,
                    vurgu: gorev.sonTarihGecti,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _tarihSatiri({
    required IconData ikon,
    required String etiket,
    required DateTime? tarih,
    bool vurgu = false,
  }) {
    final Color renk = vurgu ? Colors.redAccent : Colors.deepPurpleAccent;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0F12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: vurgu ? Colors.redAccent : Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(ikon, size: 16, color: renk),
              const SizedBox(width: 6),
              Expanded(child: Text(etiket, style: const TextStyle(color: Colors.grey, fontSize: 12))),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            tarih == null ? 'Belirtilmedi' : Gorev.tarihBicimle(tarih),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: tarih == null ? Colors.grey : Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  void _gorseliBuyut(BuildContext context, String yol) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.black,
        child: InteractiveViewer(child: _gorsel(yol, fit: BoxFit.contain)),
      ),
    );
  }

  static Color _durumRengi(GorevDurumu durum) => switch (durum) {
        GorevDurumu.atanlandi => Colors.orange,
        GorevDurumu.onayBekliyor => Colors.blueAccent,
        GorevDurumu.onaylandi => Colors.greenAccent,
      };
}

class _BosDurum extends StatelessWidget {
  final String mesaj;
  final IconData ikon;

  const _BosDurum({required this.mesaj, required this.ikon});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(ikon, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(mesaj, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}
import 'package:flutter/material.dart';

import '../config/uygulama_bilgisi.dart';

/// Hakkında ekranı.
///
/// Uygulamanın kimliği, geliştirici bilgisi ve kullandığı açık kaynaklı
/// kütüphaneler burada listelenir.
class HakkindaEkrani extends StatelessWidget {
  const HakkindaEkrani({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Hakkında',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF161B22),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // --- Uygulama kimliği ---
          Center(
            child: Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: const Color(0xFF161B22),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.deepPurpleAccent.withValues(alpha: 0.3),
                    blurRadius: 24,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: const Icon(
                Icons.school_rounded,
                size: 60,
                color: Colors.deepPurpleAccent,
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            UygulamaBilgisi.uygulamaAdi,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            'Sürüm ${UygulamaBilgisi.surum} (${UygulamaBilgisi.yapimNumarasi})',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey, fontSize: 13),
          ),
          const SizedBox(height: 16),
          Text(
            UygulamaBilgisi.aciklama,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 24),

          // --- Geliştirici ---
          Card(
            child: ListTile(
              leading: const Icon(
                Icons.person_outline,
                color: Colors.deepPurpleAccent,
              ),
              title: const Text('Geliştiren'),
              subtitle: Text(
                UygulamaBilgisi.gelistiren,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // --- Açık kaynaklı kütüphaneler ---
          const Text(
            'Açık Kaynaklı Kütüphaneler',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            'Bu uygulama aşağıdaki açık kaynaklı kütüphaneleri kullanır.',
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
          const SizedBox(height: 12),
          ...UygulamaBilgisi.kutuphaneler.map(
            (Kutuphane k) => Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: ListTile(
                dense: true,
                title: Text(
                  k.ad,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      k.aciklama,
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.deepPurpleAccent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        k.lisans,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.deepPurpleAccent,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: Text(
              '© ${DateTime.now().year} ${UygulamaBilgisi.gelistiren}',
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
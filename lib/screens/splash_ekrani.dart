import 'package:flutter/material.dart';

import '../config/uygulama_bilgisi.dart';
import 'hakkinda_ekrani.dart';

/// Uygulama açılış ekranı.
///
/// Firebase başlatma, oturum geri yükleme ve bildirim kanalı kurulumu
/// `main()` içinde `runApp`'den önce tamamlandığı için bu ekran yalnız
/// kısa bir geçiş gösterir; ardından asıl başlangıç ekranına geçilir.
class SplashEkrani extends StatefulWidget {
  /// Splash sonrasında açılacak ekran.
  final Widget baslangicEkrani;

  const SplashEkrani({super.key, required this.baslangicEkrani});

  @override
  State<SplashEkrani> createState() => _SplashEkraniState();
}

class _SplashEkraniState extends State<SplashEkrani>
    with SingleTickerProviderStateMixin {
  /// Logo hafifçe büyüyerek belirir.
  late final AnimationController _kontrolcu;
  late final Animation<double> _buyume;

  @override
  void initState() {
    super.initState();

    _kontrolcu = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _buyume = CurvedAnimation(parent: _kontrolcu, curve: Curves.easeOutBack);

    // Sabit süre sonra asıl ekrana geç.
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => widget.baslangicEkrani),
      );
    });
  }

  @override
  void dispose() {
    _kontrolcu.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0F12),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ScaleTransition(
                scale: _buyume,
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xFF161B22),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.deepPurpleAccent.withValues(alpha: 0.35),
                        blurRadius: 28,
                        spreadRadius: 6,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.school_rounded,
                    size: 72,
                    color: Colors.deepPurpleAccent,
                  ),
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                UygulamaBilgisi.uygulamaAdi,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Sürüm ${UygulamaBilgisi.surum}',
                style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 28),
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: Colors.deepPurpleAccent,
                ),
              ),
              const Spacer(),
              Text(
                'Geliştiren: ${UygulamaBilgisi.gelistiren}',
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const HakkindaEkrani(),
                  ),
                ),
                icon: const Icon(Icons.info_outline, size: 16),
                label: const Text('Hakkında'),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.deepPurpleAccent,
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
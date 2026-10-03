import 'package:flutter_test/flutter_test.dart';
import 'package:gorev_takibi/main.dart';

void main() {
  testWidgets('Uygulama acilis testi', (WidgetTester tester) async {
    // Uygulamamızı başlangıç ekranı (Giriş Ekranı) parametresi ile başlatıyoruz
    await tester.pumpWidget(const GorevTakipUygulamasi(baslangicEkrani: GirisEkrani()));

    // Giriş ekranındaki rol seçim yazısının ekranda olduğunu doğruluyoruz
    expect(find.text('Devam etmek için rolünüzü seçin'), findsOneWidget);
  });
}
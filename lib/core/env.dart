/// Konfigurasi lingkungan.
///
/// Nilai default di sini adalah kredensial **publik** milik Rumipang:
/// URL Supabase dan **anon key**. Anon key memang dirancang untuk dipasang di
/// klien - keamanannya dijaga RLS di Supabase, bukan dengan menyembunyikannya.
///
/// Yang TIDAK BOLEH ada di berkas ini (atau di mana pun dalam APK):
///   * SUPABASE_SERVICE_ROLE_KEY  -> bypass seluruh RLS
///   * MIDTRANS_SERVER_KEY        -> bisa membuat transaksi atas nama toko
///   * PRINT_DEVICE_TOKEN         -> aplikasi kasir sudah punya identitas staff
///
/// Semua nilai bisa ditimpa saat build tanpa mengubah kode:
///
/// ```bash
/// flutter build apk --release \
///   --dart-define=API_BASE_URL=https://rumipang.vercel.app \
///   --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
///   --dart-define=SUPABASE_ANON_KEY=eyJhbG...
/// ```
class Env {
  const Env._();

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://rumipang.vercel.app',
  );

  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://jenpnmmcpwnygiluefyw.supabase.co',
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImplbnBubW1jcHdueWdpbHVlZnl3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzgxMzE4MjUsImV4cCI6MjA5MzcwNzgyNX0.gFqZNJavIq4W3gKmquu1AsrinY3NXcHlMyPWUpfDQeE',
  );

  /// Interval polling cadangan saat websocket realtime putus (SPEC §7).
  static const Duration boardPollInterval = Duration(seconds: 15);

  /// Interval loop klaim job cetak (SPEC §8.3: 3-5 detik).
  static const Duration printPollInterval = Duration(seconds: 4);

  /// Jumlah job yang diklaim sekali jalan.
  static const int printClaimLimit = 3;

  static const Duration requestTimeout = Duration(seconds: 20);
}

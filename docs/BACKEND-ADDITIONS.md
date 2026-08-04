# Yang perlu ditambahkan di repo web + Supabase

Dokumen ini untuk **agent yang mengurus repo web (Next.js) dan Supabase**.
Aplikasi kasir Flutter sudah ditulis terhadap kontrak di bawah ini; selama
endpoint-endpoint ini belum ada, layar-layar baru akan tampil kosong atau
menampilkan pesan error.

Aturan yang tidak berubah: **aplikasi tidak pernah menulis ke tabel Supabase
langsung.** Semua perubahan lewat REST API supaya logika bisnis tetap satu
tempat. Supabase SDK di aplikasi hanya untuk login dan realtime.

---

## 0. Prasyarat yang memblokir SEMUANYA

Sebelum satu pun fitur di bawah bisa dipakai, `BACKEND-PREREQ.md` harus selesai:
API harus menerima **`Authorization: Bearer <JWT>`**, bukan hanya cookie sesi.

Aplikasi mengirim header itu di setiap request ([api_client.dart:135-143](../lib/core/api_client.dart#L135-L143)).
Selama backend masih cookie-only, seluruh endpoint staff membalas 401 dan
aplikasi mentok di layar login. Ini bukan pekerjaan tambahan dari dokumen ini —
ini pekerjaan yang sudah tertunda sejak awal.

---

## 1. HPP per menu

**Keputusan pemilik:** HPP diisi manual per menu, **bukan** dihitung dari resep
bahan baku. Konsekuensinya stok bahan tidak berkurang otomatis saat ada
penjualan (lihat §4).

### Perubahan tabel `menu_items`

```sql
alter table menu_items
  add column cost_price integer not null default 0;

comment on column menu_items.cost_price is
  'HPP per porsi dalam rupiah, diisi manual oleh owner. 0 = belum diisi.';
```

### Perubahan tabel `order_items` — PENTING

```sql
alter table order_items
  add column cost_price_snapshot integer not null default 0;
```

Isi kolom ini dengan `menu_items.cost_price` **pada saat order dibuat**, sama
seperti `menu_item_price` yang sudah disimpan sebagai snapshot.

Alasannya: tanpa snapshot, menaikkan HPP hari ini akan mengubah laba bulan lalu.
Laporan jadi tidak bisa dipercaya dan angka historis bergerak sendiri. Ini
kesalahan yang mahal untuk diperbaiki belakangan karena data lamanya sudah
hilang.

---

## 2. Menu bisa ditambah & harga bisa diubah

Aplikasi butuh CRUD menu. Endpoint `GET /api/menu` sudah ada; tambahkan
`cost_price` ke responsnya.

### `POST /api/menu`

```jsonc
// request
{
  "name": "Roti Coklat",
  "price": 15000,
  "cost_price": 6000,
  "category_id": "uuid-atau-null",
  "description": "opsional",
  "is_available": true
}
// response 201: objek menu_items lengkap (bentuk sama dengan GET /api/menu)
```

### `PATCH /api/menu/:id`

Terima sebagian field saja (partial update):

```jsonc
{ "price": 17000 }
{ "cost_price": 6500 }
{ "is_available": false }
{ "is_sold_out": true }
```

Response 200 dengan objek menu terbaru.

**Validasi yang diharapkan server:** `price >= 0`, `cost_price >= 0`. Kalau
`cost_price > price`, tetap terima tapi kembalikan field peringatan — margin
negatif itu keputusan bisnis, bukan error teknis. Aplikasi menampilkannya merah.

### `DELETE /api/menu/:id`

Lebih disarankan **soft delete** (`is_active = false`) daripada hapus baris,
supaya `order_items` lama tidak kehilangan referensi. Kalau memang dihapus
keras, pastikan `order_items` sudah menyimpan `menu_item_name` sebagai snapshot
(sudah, lihat model yang ada).

---

## 3. Laporan menu terlaris & kurang laku

### `GET /api/reports/menu-sales?from=<ISO8601>&to=<ISO8601>`

```jsonc
// response 200
{
  "from": "2026-07-01T00:00:00Z",
  "to": "2026-07-31T23:59:59Z",
  "items": [
    {
      "menu_item_id": "uuid",
      "menu_item_name": "Es Kopi Susu",
      "qty_sold": 412,
      "revenue": 6180000,        // jumlah subtotal
      "cost": 2472000,           // jumlah cost_price_snapshot * quantity
      "gross_profit": 3708000    // revenue - cost
    }
  ]
}
```

Hitung **hanya dari order yang `payment_status = 'PAID'` dan
`status != 'CANCELLED'`**. Order batal atau belum bayar tidak boleh masuk
laporan penjualan.

Urutan tidak perlu diatur server — aplikasi menyortir sendiri untuk menampilkan
"terlaris" dan "kurang laku" dari daftar yang sama.

Menu yang **tidak pernah terjual** dalam rentang itu sebaiknya tetap muncul
dengan `qty_sold: 0`. Justru menu inilah yang paling ingin dilihat owner di
daftar "kurang laku" — kalau dihilangkan, menu mati jadi tak terlihat.

---

## 4. Stok bahan baku + alert

**Catatan penting:** karena HPP diisi manual dan tidak ada resep, **server tidak
bisa mengurangi stok otomatis saat ada penjualan.** Sistem tidak tahu satu roti
coklat menghabiskan berapa gram tepung. Semua perubahan stok adalah input
manual dari aplikasi.

### Tabel baru `ingredients`

```sql
create table ingredients (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  unit text not null default 'pcs',        -- 'kg', 'gram', 'liter', 'pcs', ...
  stock_qty numeric not null default 0,
  alert_threshold numeric not null default 20,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
```

`alert_threshold` default 20 sesuai permintaan, tapi dibuat per bahan supaya
bisa beda — 20 kg tepung dan 20 pcs kemasan bukan tingkat urgensi yang sama.

### Tabel baru `stock_movements` (jejak audit)

```sql
create table stock_movements (
  id uuid primary key default gen_random_uuid(),
  ingredient_id uuid not null references ingredients(id) on delete cascade,
  delta numeric not null,                  -- positif = masuk, negatif = pakai
  reason text not null,                    -- 'PURCHASE' | 'USAGE' | 'WASTE' | 'CORRECTION'
  note text,
  actor_email text,
  created_at timestamptz not null default now()
);
```

Tanpa tabel ini, stok cuma satu angka yang berubah tanpa jejak dan selisih
tidak akan pernah bisa ditelusuri.

### Endpoint

| Method | Path | Isi |
|---|---|---|
| `GET` | `/api/ingredients` | daftar bahan aktif + `stock_qty`, `alert_threshold` |
| `POST` | `/api/ingredients` | `{name, unit, stock_qty, alert_threshold}` |
| `PATCH` | `/api/ingredients/:id` | partial: `name`, `unit`, `alert_threshold`, `is_active` |
| `POST` | `/api/ingredients/:id/movements` | `{delta, reason, note}` → server update `stock_qty` **dan** catat movement dalam satu transaksi |

Perubahan stok **wajib** lewat `/movements`, bukan `PATCH stock_qty` langsung.
Dua kasir yang menyesuaikan stok bersamaan dengan `PATCH` akan saling menimpa;
dengan `delta` keduanya terakumulasi benar.

---

## 5. Jatah makan karyawan

**Aturan:** 3 karyawan, masing-masing berhak **1 kali makan per hari**.

### Tabel baru `staff_meals`

```sql
create table staff_meals (
  id uuid primary key default gen_random_uuid(),
  staff_id uuid not null references staff(id),
  meal_date date not null default current_date,
  menu_item_id uuid references menu_items(id),
  cost_snapshot integer not null default 0,   -- cost_price saat dicatat
  note text,
  created_at timestamptz not null default now(),
  unique (staff_id, meal_date)                -- inilah yang menegakkan 1x/hari
);
```

Constraint `unique (staff_id, meal_date)` adalah tempat aturan "1 kali sehari"
ditegakkan. Jangan andalkan pengecekan di aplikasi saja — dua tablet bisa
mencatat bersamaan dan keduanya lolos.

Saat constraint dilanggar, balas **409 Conflict** dengan
`{"error": "Karyawan ini sudah mengambil jatah makan hari ini"}`. Aplikasi
menampilkan pesan itu apa adanya.

`cost_snapshot` diisi dari `menu_items.cost_price` saat pencatatan — alasannya
sama dengan §1: biaya jatah makan bulan lalu tidak boleh berubah saat HPP
diperbarui.

### Endpoint

| Method | Path | Isi |
|---|---|---|
| `GET` | `/api/staff-meals?date=YYYY-MM-DD` | jatah makan pada tanggal itu |
| `GET` | `/api/staff-meals?from=&to=` | rekap rentang, untuk laporan biaya |
| `POST` | `/api/staff-meals` | `{staff_id, menu_item_id?, note?}` — `meal_date` = hari ini di server |
| `DELETE` | `/api/staff-meals/:id` | koreksi salah input |

Juga dibutuhkan **`GET /api/staff`** (daftar karyawan aktif: `id`, `name`,
`email`, `role`) supaya aplikasi bisa menampilkan tiga nama untuk dipilih.

---

## 6. Tema event (aplikasi **dan** web ikut berubah)

Owner memilih tema dari aplikasi kasir; web membaca nilai yang sama.

### Tabel baru `app_settings`

```sql
create table app_settings (
  key text primary key,
  value jsonb not null,
  updated_at timestamptz not null default now(),
  updated_by text
);

insert into app_settings (key, value)
values ('theme', '{"preset":"NORMAL"}');
```

Bentuk key-value dipilih supaya pengaturan berikutnya (jam buka, pesan promo)
tidak perlu migrasi tabel lagi.

### Endpoint

| Method | Path | Isi |
|---|---|---|
| `GET` | `/api/settings/theme` | `{"preset": "NATAL"}` |
| `PATCH` | `/api/settings/theme` | `{"preset": "NATAL"}` → balas objek terbaru |

`PATCH`, bukan `PUT` — klien REST di aplikasi hanya mengenal GET/POST/PATCH/DELETE
([api_client.dart:41-50](../lib/core/api_client.dart#L41-L50)), dan menambah verb
baru hanya untuk satu endpoint tidak sepadan.

`GET` harus **boleh diakses publik** (tanpa login) — web pengunjung perlu
membacanya juga. `PATCH` khusus role owner/admin.

### Nilai preset yang disepakati

| `preset` | Nama tampil | Warna utama |
|---|---|---|
| `NORMAL` | Normal | `#7B3F00` cokelat kopi (warna asli) |
| `NATAL` | Natal | `#C62828` merah + `#1B7F4B` hijau |
| `RAMADAN` | Ramadan | `#00695C` hijau tosca + emas |
| `KEMERDEKAAN` | Kemerdekaan | `#C62828` merah + putih |
| `IMLEK` | Imlek | `#B71C1C` merah + `#D4AF37` emas |

Daftar ini dipakai identik di aplikasi ([shared/app_theme_preset.dart](../lib/shared/app_theme_preset.dart))
dan harus dipakai identik di web. Kalau web menambah preset baru, aplikasi akan
jatuh ke `NORMAL` — tidak error, tapi temanya tidak ikut berubah sampai
aplikasi diperbarui.

Realtime opsional: kalau `app_settings` ikut dipublikasikan lewat Supabase
realtime, tema berubah di semua perangkat tanpa perlu muat ulang.

---

## 7. Alur dapur dihapus

**Keputusan pemilik:** order cukup masuk, tanpa langkah proses manual. Layar
dapur beserta tombol ETA / "mulai proses" / "sudah diantar" dihapus dari
aplikasi.

Yang perlu dilakukan server: **set `status = 'SERVED'` saat order dibuat**,
bukan `QUEUED`.

Alasannya, aturan pengarsipan yang sudah ada mensyaratkan order berstatus
`SERVED` **dan** lunas sebelum boleh diarsipkan
([order.dart:172](../lib/models/order.dart#L172)). Kalau order berhenti di
`QUEUED` selamanya, order lunas tidak akan pernah bisa diarsipkan dan board
kasir akan menumpuk tanpa batas.

Endpoint `start-processing` dan `mark-served` boleh tetap ada — aplikasi hanya
berhenti memanggilnya. Kalau web masih memakainya, tidak ada yang rusak.

---

## 8. Ringkasan RLS

Tabel baru semuanya berisi data operasional toko, bukan data pelanggan:

- `ingredients`, `stock_movements`, `staff_meals` → hanya role staff/owner.
  Tidak ada alasan pengunjung web membacanya.
- `app_settings` → **baca publik**, tulis khusus owner. Web pengunjung perlu
  membaca tema.

Karena semua akses dari aplikasi lewat REST API dengan JWT staff, RLS berperan
sebagai lapisan pertahanan kedua, bukan yang pertama.

---

## Urutan pengerjaan yang disarankan

1. **`BACKEND-PREREQ.md` (Bearer auth)** — tanpa ini tidak ada yang bisa diuji
2. `cost_price` + `cost_price_snapshot` — kolom, karena data historis mulai
   terkumpul sejak hari dipasang
3. `PATCH/POST /api/menu` — fitur paling sering dipakai
4. `app_settings` + tema — kecil, cepat, hasilnya langsung terlihat
5. `ingredients` + `stock_movements`
6. `staff_meals` + `GET /api/staff`
7. `GET /api/reports/menu-sales` — paling akhir karena butuh data dari nomor 2

Nomor 2 sengaja ditaruh di awal meski fiturnya belum dipakai: setiap hari
kolom itu belum ada adalah satu hari data laba yang hilang permanen.

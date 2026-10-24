# Absensi Siswa Online

Aplikasi web React + Vite + Supabase untuk absensi siswa. Antarmuka responsif untuk HP/laptop, panel admin, data siswa, kode/QR siswa, absensi hadir/terlambat/izin, dan ekspor CSV.

## Fitur
- Admin: kelola data siswa (kode, nama, kelas X/XI/XII, jurusan), atur jam mulai, lihat laporan per tanggal, unduh CSV, buat dan unduh QR siswa.
- Siswa: daftar dengan kode yang sudah disediakan Admin, login email/password, catat hadir atau izin dengan alasan, lihat riwayat pribadi.
- Status hadir/terlambat dan waktu absensi dihitung di fungsi database menggunakan waktu server zona Asia/Jakarta, bukan jam perangkat.
- Satu catatan absensi per siswa per tanggal. Jika siswa mengirim ulang, catatan hari itu diperbarui.
- Row Level Security (RLS) untuk membatasi data berdasarkan peran.

## Prasyarat
- Node.js 20+ dan npm.
- Akun Supabase.
- Akun Cloudflare untuk deploy (opsional, paket gratis memiliki batas pemakaian).

## 1. Buat database Supabase
1. Buat project baru di Supabase.
2. Buka **SQL Editor** lalu jalankan seluruh isi `supabase.sql`.
3. Buka **Project Settings → API** (atau Connect) dan salin Project URL serta publishable/anon key. Jangan gunakan `service_role` key di frontend.
4. Buat akun admin lewat **Authentication → Users → Add user** dengan email dan password yang kamu tentukan. Jika membuat akun lewat menu tersebut, jalankan SQL berikut di SQL Editor untuk menjadikannya admin:

```sql
update public.profiles
set role = 'admin'
where id = (select id from auth.users where email = 'EMAIL_ADMIN_KAMU');
```

Ganti `EMAIL_ADMIN_KAMU` dengan email admin. Trigger database membuat profil default saat akun dibuat. Jika akun admin sudah ada sebelum SQL dipasang, buat baris profil manual:

```sql
insert into public.profiles(id, full_name, role)
select id, coalesce(raw_user_meta_data->>'full_name', split_part(email,'@',1)), 'admin'
from auth.users where email = 'EMAIL_ADMIN_KAMU'
on conflict (id) do update set role = 'admin';
```

## 2. Jalankan di komputer
1. Ekstrak ZIP.
2. Salin `.env.example` menjadi `.env`.
3. Isi nilainya:

```env
VITE_SUPABASE_URL=https://PROJECT_ID.supabase.co
VITE_SUPABASE_ANON_KEY=KEY_PUBLISHABLE_ATAU_ANON
```

4. Di folder project, jalankan:

```bash
npm install
npm run dev
```

Vite akan menampilkan alamat lokal. Untuk pengujian dari HP lain di Wi-Fi yang sama, gunakan alamat Network yang ditampilkan Vite; komputer harus tetap menyala. Untuk penggunaan internet publik, deploy ke Cloudflare Pages.

## 3. Tambahkan siswa dan gunakan aplikasi
1. Login sebagai admin.
2. Buka **Data Siswa** dan buat kode unik untuk tiap siswa, misalnya `TKJ001`.
3. Klik **QR** untuk membuat dan mengunduh QR kode siswa. QR ini berisi kode siswa, bukan bukti absensi; siswa tetap perlu login.
4. Siswa pilih **Daftar Siswa**, isi nama, kode yang diberikan, email, dan password.
5. Jika konfirmasi email aktif di Supabase, siswa harus mengonfirmasi email sebelum login. Untuk kelas tertutup, kamu bisa mengatur kebijakan konfirmasi email di Supabase Authentication sesuai kebutuhan.
6. Admin dapat memilih tanggal laporan lalu mengunduh CSV. File CSV dapat dibuka di Excel/Google Sheets.

## 4. Deploy gratis ke Cloudflare Pages
Cara termudah:
1. Unggah project ke repositori GitHub milikmu (jangan commit file `.env`).
2. Di Cloudflare Dashboard, buka **Workers & Pages → Create → Pages → Connect to Git**.
3. Pilih repositori. Build command: `npm run build`; output directory: `dist`.
4. Tambahkan environment variables `VITE_SUPABASE_URL` dan `VITE_SUPABASE_ANON_KEY` pada pengaturan build/deployment.
5. Deploy. URL `*.pages.dev` gratis akan diberikan. Tambahkan domain sendiri jika sudah punya; domain kustom biasanya perlu dibeli kecuali kamu sudah memilikinya.
6. Di Supabase Authentication → URL Configuration, set **Site URL** ke URL Pages kamu dan tambahkan URL tersebut ke **Redirect URLs**.

## Penting / batasan
- Paket gratis dapat digunakan untuk demo dan skala kecil, tetapi tidak berarti layanan gratis tanpa batas atau dijamin selamanya. Supabase/Cloudflare menerapkan kuota dan kebijakan paket gratis yang dapat berubah.
- CSV adalah format rekap spreadsheet (bukan CV). Ekspor hanya mencakup baris yang sedang dimuat: admin berdasarkan tanggal yang dipilih; siswa berdasarkan riwayat yang dimuat.
- Fitur QR pada versi ini menghasilkan QR untuk kode siswa. Belum ada kamera pemindai QR atau verifikasi lokasi/geofence.
- Akun admin harus dibuat oleh pengelola. Jangan berikan hak admin ke akun siswa.
- Jangan menyimpan data sensitif berlebihan. Gunakan password kuat, backup data, dan uji RLS sebelum digunakan untuk data siswa sungguhan.
- Untuk produksi, sebaiknya tambahkan validasi sekolah, log audit, reset password, pengelolaan akun nonaktif, serta kebijakan retensi data.

# Z-Link v10 — GitHub backup dan restore

Disesuaikan untuk server kajian.mim.id: Ubuntu 24.04, service zlink-test, SQLite 322039808 bytes, repo zaldyrs/zlink-v10.

## Isi backup

- /root/zlink-test/zlink-server-smoke-test: aplikasi, data SQLite dan WAL/SHM, secrets, firmware, pyproject.toml, deployment files.
- /var/www/zlink-dashboard
- /etc/systemd/system/zlink-test.service
- /etc/nginx/sites-available/zlink-dashboard
- /etc/nginx/sites-enabled/zlink-dashboard (file biasa pada server Anda)

Moodle dan konfigurasi global Nginx tidak ditulis oleh script. Restore reload Nginx bersama, sehingga konfigurasi global harus valid. TLS certificates, OS packages, firewall, DNS, crontab dan HBLink pada server lain tidak termasuk. Jika EnvironmentFile atau database berada di luar aplikasi, tambahkan path ke common.sh sebelum backup.

## Setup sekali

Upload ZIP ke /root lalu:

```bash
apt-get update
apt-get install -y python3 git gnupg rsync unzip
unzip /root/ZLink_V10_Backup_Restore.zip -d /root
chmod 700 /root/zlink-v10-tools/*.sh
install -d -m 700 /root/.config/zlink-backup
```

Buat key hanya jika belum ada, jangan mengganti key lama:

```bash
if [ ! -e /root/.config/zlink-backup/passphrase ]; then
  (umask 077; head -c 48 /dev/urandom | base64 > /root/.config/zlink-backup/passphrase)
fi
chmod 600 /root/.config/zlink-backup/passphrase
```

Simpan salinan key di password manager/offline. Jangan upload ke GitHub/chat. Restore memerlukan key yang sama dengan snapshot.

Pastikan SSH GitHub root sudah diizinkan membaca dan menulis repo zaldyrs/zlink-v10. Uji:

```bash
git ls-remote git@github.com:zaldyrs/zlink-v10.git HEAD
```

Jika permission denied, daftarkan public SSH key server pada GitHub dengan izin write. Jangan membagikan private key. Verifikasi fingerprint host GitHub saat pertama kali tersambung. Script tidak mengatur credential/token dan tidak mengubah visibility repo; private repo disarankan. Jika commit meminta identitas, isi git user.name/user.email Anda pada repo setelah clone.

Script memakai clone terpisah /root/zlink-v10-backup. Tidak memodifikasi source pada branch repo; hanya menambahkan encrypted-snapshots pada branch default yang di-clone. Tidak ada force-push/auto-merge. Branch protected membutuhkan workflow PR terpisah.

## Backup satu command

```bash
/root/zlink-v10-tools/backup.sh
```

Service zlink-test berhenti selama pengarsipan untuk konsistensi SQLite dan dimulai kembali sebelum enkripsi/push. Semua penulis lain ke database ini juga harus berhenti; script hanya mengelola zlink-test berdasarkan service yang ditemukan. Hindari import manual selama backup. Moodle tidak dihentikan.

Arsip lengkap dikompresi, dienkripsi GPG AES256, lalu dibagi menjadi bagian 45 MiB. Ukuran akhir terkompresi belum diketahui; tidak ada data database yang dibuang. Checksum per bagian dan SQLite quick_check salinan dijalankan sebelum push. Enkripsi GPG juga memverifikasi integritas saat dekripsi.

Siapkan setidaknya beberapa GB ruang kosong pada /var/tmp, /root dan /var/backups. Arsip plaintext sementara dilindungi permission root dan dihapus saat script selesai atau menerima INT/TERM; hard power-off/SIGKILL dapat meninggalkan file /var/tmp/zlink-*. Hapus setelah memastikan tidak ada job aktif.

Jika push gagal, snapshot dan commit lokal tetap tersedia. Perbaiki auth/network lalu:

```bash
git -C /root/zlink-v10-backup push origin HEAD
```

Snapshot baru menambah ukuran Git history. Chunking mengatasi ukuran file individual, bukan total repo. Untuk backup sering atau pertumbuhan besar, gunakan object storage dengan retention. Script tidak menghapus history atau snapshot lama otomatis. Jangan memakai GitHub sebagai satu-satunya salinan backup.

## Restore: preview lalu apply

Pada server baru: install runtime/dependency aplikasi yang sesuai pyproject.toml dan service, Nginx, TLS, dan DNS; salin tools dan key asli. Paket ini bukan image OS dan belum memiliki installer runtime otomatis. Konfigurasi service menggunakan path absolut server lama.

Clone repo jika belum tersedia:

```bash
git clone git@github.com:zaldyrs/zlink-v10.git /root/zlink-v10-backup
```

Bila sudah ada, jalankan git pull --ff-only di repo tersebut. Pilih snapshot:

```bash
ls /root/zlink-v10-backup/encrypted-snapshots
```

Ganti TIMESTAMP dengan nama folder hasil backup:

```bash
/root/zlink-v10-tools/restore.sh /root/zlink-v10-backup/encrypted-snapshots/TIMESTAMP
/root/zlink-v10-tools/restore.sh /root/zlink-v10-backup/encrypted-snapshots/TIMESTAMP --apply
```

Preview memverifikasi seluruh bagian, mendekripsi dan memeriksa cakupan arsip tanpa mengubah aplikasi. Apply menghentikan zlink-test, menyimpan file lama ke /var/backups/zlink-v10/TIMESTAMP/before-restore.tar.gz, menghapus sidecar SQLite lama, menyalin snapshot, daemon-reload, memeriksa/reload Nginx, dan memulai kembali service yang sebelumnya aktif. VPS baru: install dependency dahulu lalu systemctl enable --now zlink-test.

Rollback lokal tidak terenkripsi, permission root. Restore menimpa file snapshot tetapi tidak menghapus file tambahan (kecuali SQLite WAL/SHM lama). Restore bukan transaksi: jika copy/nginx gagal, dapat terjadi restore parsial. File lama tersedia; script mencoba memulai kembali service sebelumnya, tidak menerapkan rollback otomatis. Untuk rollback manual, hentikan zlink-test, periksa arsip before-restore, lalu ekstrak ke / dengan tar -xzf dan lakukan daemon-reload/nginx -t sebelum restart. File baru yang tidak ada di rollback tidak terhapus otomatis.

## Validasi hasil

```bash
systemctl status zlink-test --no-pager
journalctl -u zlink-test -n 60 --no-pager
nginx -t
```

Cek dashboard: contacts, APRS stations, devices, firmware dan live stream. Periksa Moodle setelah Nginx reload. Restore ke VPS pengganti harus dikoordinasikan dengan pemadaman service server lama agar tidak menjalankan dua instance beridentitas sama.

## Pengujian paket

Syntax Bash dan round-trip split/reassembly/checksum diuji lokal. Uji GPG lokal terhalang gpg-agent yang gagal dijalankan; enkripsi/dekripsi perlu diverifikasi pada VPS. Backup database server asli, autentikasi GitHub, stop/start service dan restore live belum dijalankan. Uji disaster recovery pada VPS terpisah sebelum mengandalkan paket ini untuk pemulihan.

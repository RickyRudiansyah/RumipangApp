<#
    bootstrap.ps1 - lengkapi scaffolding native Android yang hanya bisa dibuat Flutter SDK.

    Repo ini berisi seluruh kode aplikasi (lib/, pubspec.yaml, AndroidManifest.xml),
    tapi TIDAK berisi berkas biner hasil `flutter create` (gradle wrapper jar, res/,
    MainActivity.kt, .metadata). Script ini membuatnya, lalu mengembalikan berkas
    milik kita yang mungkin tertimpa.

    Jalankan sekali saja, dari folder ini:
        powershell -ExecutionPolicy Bypass -File .\bootstrap.ps1
#>

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
Set-Location $root

function Info($m) { Write-Host "[bootstrap] $m" -ForegroundColor Cyan }
function Warn($m) { Write-Host "[bootstrap] $m" -ForegroundColor Yellow }

# --- 0. Pastikan Flutter ada -------------------------------------------------
$flutter = Get-Command flutter -ErrorAction SilentlyContinue
if (-not $flutter) {
    Write-Host "Flutter SDK tidak ditemukan di PATH." -ForegroundColor Red
    Write-Host "Pasang dulu: https://docs.flutter.dev/get-started/install/windows"
    exit 1
}
Info "Flutter: $($flutter.Source)"

# --- 1. Backup berkas milik kita --------------------------------------------
$backup = Join-Path $env:TEMP "rumipang-bootstrap-$(Get-Date -Format yyyyMMddHHmmss)"
New-Item -ItemType Directory -Force -Path $backup | Out-Null
Info "Backup sementara: $backup"

$guard = @(
    'pubspec.yaml',
    'analysis_options.yaml',
    'android\app\src\main\AndroidManifest.xml'
)
foreach ($rel in $guard) {
    if (Test-Path $rel) {
        $dest = Join-Path $backup $rel
        New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
        Copy-Item $rel $dest -Force
    }
}
if (Test-Path 'lib') { Copy-Item 'lib' (Join-Path $backup 'lib') -Recurse -Force }

# --- 2. Generate scaffolding native -----------------------------------------
Info "Menjalankan flutter create (mengisi gradle wrapper, res/, MainActivity)..."
& flutter create . --platforms=android --org com.rumipang --project-name rumipang_kasir
if ($LASTEXITCODE -ne 0) { Write-Host "flutter create gagal." -ForegroundColor Red; exit 1 }

# --- 3. Kembalikan berkas milik kita ----------------------------------------
Info "Mengembalikan berkas proyek yang mungkin tertimpa..."
foreach ($rel in $guard) {
    $src = Join-Path $backup $rel
    if (Test-Path $src) {
        New-Item -ItemType Directory -Force -Path (Split-Path $rel) | Out-Null
        Copy-Item $src $rel -Force
    }
}
if (Test-Path (Join-Path $backup 'lib')) {
    if (Test-Path 'lib') { Remove-Item 'lib' -Recurse -Force }
    Copy-Item (Join-Path $backup 'lib') 'lib' -Recurse -Force
}
# flutter create menaruh widget_test.dart bawaan yang mereferensikan MyApp -> tidak ada di sini.
if (Test-Path 'test\widget_test.dart') { Remove-Item 'test\widget_test.dart' -Force }

# --- 4. Patch minSdk / targetSdk --------------------------------------------
# SPEC §2: minSdk 26 (print_bluetooth_thermal + foreground service butuh >= 26),
#          targetSdk 34.
$gradleCandidates = @('android\app\build.gradle.kts', 'android\app\build.gradle')
$gradle = $gradleCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $gradle) {
    Warn "android/app/build.gradle(.kts) tidak ditemukan - set minSdk 26 & targetSdk 34 manual."
} else {
    Info "Patch $gradle -> minSdk 26, targetSdk 34"
    $text = Get-Content $gradle -Raw
    $before = $text

    # KTS: minSdk = flutter.minSdkVersion   |   Groovy: minSdkVersion flutter.minSdkVersion
    $text = $text -replace 'minSdk\s*=\s*flutter\.minSdkVersion', 'minSdk = 26'
    $text = $text -replace 'minSdkVersion\s+flutter\.minSdkVersion', 'minSdkVersion 26'
    $text = $text -replace 'targetSdk\s*=\s*flutter\.targetSdkVersion', 'targetSdk = 34'
    $text = $text -replace 'targetSdkVersion\s+flutter\.targetSdkVersion', 'targetSdkVersion 34'

    if ($text -eq $before) {
        Warn "Pola minSdk/targetSdk tidak cocok (template Flutter berubah)."
        Warn "Buka $gradle dan set minSdk = 26, targetSdk = 34 manual."
    } else {
        Set-Content $gradle -Value $text -Encoding utf8
    }
}

# --- 5. Ambil dependency -----------------------------------------------------
Info "flutter pub get..."
& flutter pub get
if ($LASTEXITCODE -ne 0) { Write-Host "pub get gagal - cek pesan di atas." -ForegroundColor Red; exit 1 }

Remove-Item $backup -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "Selesai. Langkah berikutnya:" -ForegroundColor Green
Write-Host "  1. Sambungkan tablet (USB debugging aktif) -> flutter devices"
Write-Host "  2. flutter run --release            (kredensial default sudah tertanam)"
Write-Host ""
Write-Host "  Emulator TIDAK punya Bluetooth Classic - modul printer wajib diuji di tablet fisik."

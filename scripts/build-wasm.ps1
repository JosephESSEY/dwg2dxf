<#
.SYNOPSIS
Script de compilation de LibreDWG en WebAssembly pour Windows en utilisant CMake.

.DESCRIPTION
Ce script utilise CMake (natif sous Windows) et Emscripten pour compiler 
LibreDWG, éliminant ainsi le besoin de MSYS2 ou WSL.

Prérequis :
- CMake installé et dans le PATH
- Emscripten (emsdk) installé, activé, et dans le PATH (emcmake, emcc, etc.)
- Python installé (souvent requis par Emscripten/CMake)
#>

$ErrorActionPreference = "Stop"

Write-Host "=== Vérification des outils ===" -ForegroundColor Cyan
if (-not (Get-Command cmake -ErrorAction SilentlyContinue)) {
    Write-Error "CMake n'est pas installé ou n'est pas dans le PATH."
    exit 1
}
if (-not (Get-Command emcmake -ErrorAction SilentlyContinue)) {
    Write-Error "emcmake (Emscripten) n'est pas dans le PATH. Pensez à exécuter emsdk_env.bat."
    exit 1
}

Write-Host "=== Clonage de LibreDWG ===" -ForegroundColor Cyan
if (-not (Test-Path "libredwg")) {
    git clone --depth 1 --recurse-submodules https://github.com/LibreDWG/libredwg.git
}
# S'assurer que les sous-modules (jsmn) sont bien récupérés
Push-Location libredwg
$oldAction = $ErrorActionPreference
$ErrorActionPreference = "Continue"
git submodule update --init --recursive 2>$null
$ErrorActionPreference = $oldAction
Pop-Location

Write-Host "=== Configuration du build CMake avec Emscripten ===" -ForegroundColor Cyan
Push-Location libredwg

# Nettoyage du cache précédent
if (Test-Path "build") {
    Remove-Item -Recurse -Force "build"
}
New-Item -ItemType Directory -Name "build" | Out-Null
Push-Location build

# -DDISABLE_WERROR=ON             -> option officielle de LibreDWG pour ne PAS ajouter -Werror
# -DLIBREDWG_LIBONLY=ON           -> ne compile que la bibliothèque, pas les exécutables
# -DLIBREDWG_DISABLE_JSON=ON      -> désactive le support JSON (évite la dépendance jsmn)
# -DHAVE_C_FSTACK_*:BOOL=OFF      -> désactive les flags de sécurité non supportés par emcc
# -DCMAKE_C_FLAGS=-w               -> supprime TOUS les warnings (bibliothèque tierce, on s'en fiche)
emcmake cmake .. `
    "-DBUILD_SHARED_LIBS=OFF" `
    "-DDISABLE_WERROR=ON" `
    "-DLIBREDWG_LIBONLY=ON" `
    "-DLIBREDWG_DISABLE_JSON=ON" `
    "-DHAVE_C_FSTACK_CLASH_PROTECTION:BOOL=OFF" `
    "-DHAVE_C_FSTACK_PROTECTOR_STRONG:BOOL=OFF" `
    "-DHAVE_C_FCF_PROTECTION:BOOL=OFF" `
    "-DCMAKE_C_FLAGS=-w"

if ($LASTEXITCODE -ne 0) {
    Write-Error "Échec de la configuration CMake."
    Pop-Location; Pop-Location
    exit 1
}

Write-Host "=== Compilation de la bibliothèque LibreDWG ===" -ForegroundColor Cyan
cmake --build . --config Release

if ($LASTEXITCODE -ne 0) {
    Write-Error "Échec de la compilation de LibreDWG."
    Pop-Location; Pop-Location
    exit 1
}

Pop-Location  # sort de build
Pop-Location  # sort de libredwg

Write-Host "=== Compilation du wrapper WebAssembly ===" -ForegroundColor Cyan
# Cherche le fichier .a généré (l'emplacement dépend du générateur CMake)
$libPath = $null
$candidates = @(
    "libredwg\build\libredwg.a",
    "libredwg\build\src\libredwg.a",
    "libredwg\build\src\Release\libredwg.a",
    "libredwg\build\libredwg.bc",
    "libredwg\build\src\libredwg.bc",
    "libredwg\build\libredwg.a",
    "libredwg\build\liblibredwg.a",
    "libredwg\build\libredwg.a"
)
foreach ($candidate in $candidates) {
    if (Test-Path $candidate) {
        $libPath = $candidate
        break
    }
}
if (-not $libPath) {
    Write-Host "=== Recherche du fichier .a dans le dossier build ===" -ForegroundColor Yellow
    Get-ChildItem -Path "libredwg\build" -Recurse -Include "*.a","*.bc" | ForEach-Object { Write-Host $_.FullName }
    Write-Error "Fichier libredwg.a introuvable ! La compilation de la bibliothèque a probablement échoué."
    exit 1
}
Write-Host "Bibliothèque trouvée : $libPath" -ForegroundColor Green

# Créer le dossier wasm s'il n'existe pas
if (-not (Test-Path "wasm")) {
    New-Item -ItemType Directory -Name "wasm" | Out-Null
}

emcc scripts\wrapper.c $libPath `
    -I libredwg\include `
    -I libredwg\src `
    -I libredwg\build\src `
    -O2 `
    -s MODULARIZE=1 `
    -s EXPORT_NAME='LibreDWG' `
    -s ALLOW_MEMORY_GROWTH=1 `
    -s EXPORTED_FUNCTIONS="['_convert_dwg_to_dxf', '_malloc', '_free']" `
    -s EXPORTED_RUNTIME_METHODS="['ccall', 'cwrap', 'FS']" `
    -o wasm\libredwg.js

if ($LASTEXITCODE -ne 0) {
    Write-Error "Échec de la compilation du wrapper WebAssembly."
    exit 1
}

Write-Host "=== Compilation WebAssembly terminée avec succès ! ===" -ForegroundColor Green
Write-Host "Fichiers générés :" -ForegroundColor Green
Write-Host "  - wasm\libredwg.js" -ForegroundColor Green
Write-Host "  - wasm\libredwg.wasm" -ForegroundColor Green

#!/bin/bash
set -e

echo "=== Vérification des outils ==="
if ! command -v cmake &> /dev/null; then
    echo "Erreur : cmake n'est pas installé."
    exit 1
fi
if ! command -v emcmake &> /dev/null; then
    echo "Erreur : emcmake n'est pas trouvé (Emscripten non activé)."
    exit 1
fi

echo "=== Clonage de LibreDWG ==="
if [ ! -d "libredwg" ]; then
    git clone --depth 1 --recurse-submodules https://github.com/LibreDWG/libredwg.git
fi

# S'assurer que les sous-modules (jsmn) sont bien récupérés
cd libredwg
git submodule update --init --recursive
cd ..

echo "=== Configuration du build CMake avec Emscripten ==="
cd libredwg
rm -rf build
mkdir -p build
cd build

emcmake cmake .. \
    -DBUILD_SHARED_LIBS=OFF \
    -DDISABLE_WERROR=ON \
    -DLIBREDWG_LIBONLY=ON \
    -DLIBREDWG_DISABLE_JSON=ON \
    -DHAVE_C_FSTACK_CLASH_PROTECTION:BOOL=OFF \
    -DHAVE_C_FSTACK_PROTECTOR_STRONG:BOOL=OFF \
    -DHAVE_C_FCF_PROTECTION:BOOL=OFF \
    -DCMAKE_C_FLAGS=-w

echo "=== Compilation de la bibliothèque LibreDWG ==="
cmake --build . --config Release

cd ../..

echo "=== Compilation du wrapper WebAssembly ==="
LIB_PATH=""
CANDIDATES=(
    "libredwg/build/libredwg.a"
    "libredwg/build/src/libredwg.a"
    "libredwg/build/src/Release/libredwg.a"
    "libredwg/build/libredwg.bc"
    "libredwg/build/src/libredwg.bc"
    "libredwg/build/liblibredwg.a"
)

for candidate in "${CANDIDATES[@]}"; do
    if [ -f "$candidate" ]; then
        LIB_PATH="$candidate"
        break
    fi
done

if [ -z "$LIB_PATH" ]; then
    echo "=== Recherche du fichier .a dans le dossier build ==="
    find libredwg/build -name "*.a" -o -name "*.bc"
    echo "Erreur : Fichier libredwg.a introuvable !"
    exit 1
fi

echo "Bibliothèque trouvée : $LIB_PATH"

mkdir -p wasm

emcc scripts/wrapper.c "$LIB_PATH" \
    -I libredwg/include \
    -I libredwg/src \
    -I libredwg/build/src \
    -O2 \
    -s MODULARIZE=1 \
    -s EXPORT_NAME='LibreDWG' \
    -s ALLOW_MEMORY_GROWTH=1 \
    -s EXPORTED_FUNCTIONS="['_convert_dwg_to_dxf', '_malloc', '_free']" \
    -s EXPORTED_RUNTIME_METHODS="['ccall', 'cwrap', 'FS']" \
    -o wasm/libredwg.js

echo "=== Compilation WebAssembly terminée avec succès ! ==="
echo "Fichiers générés :"
echo "  - wasm/libredwg.js"
echo "  - wasm/libredwg.wasm"

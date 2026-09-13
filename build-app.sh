#!/bin/zsh
# Compila em release e monta build/Marcado.app.
#   ./build-app.sh            só monta o .app
#   ./build-app.sh --install  monta, copia para /Applications e abre
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Marcado.app"

swift build -c release
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Marcado "$APP/Contents/MacOS/Marcado"
cp Resources/Info.plist "$APP/Contents/"
cp -R Resources/web "$APP/Contents/Resources/web"
if [[ -f Resources/AppIcon.icns ]]; then
  cp Resources/AppIcon.icns "$APP/Contents/Resources/"
fi
# Assinatura ad hoc: o app não pede permissão de privacidade, então não precisa de certificado.
codesign --force --deep --sign - "$APP"
echo "OK: $APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x Marcado 2>/dev/null || true
  sleep 0.3
  rm -rf /Applications/Marcado.app
  cp -R "$APP" /Applications/
  # Registra o app no Launch Services para o "Abrir com" do Finder enxergar os tipos .md
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/Marcado.app || true
  open /Applications/Marcado.app
  echo "Instalado em /Applications/Marcado.app e aberto."
fi

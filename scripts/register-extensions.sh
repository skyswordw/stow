#!/bin/zsh
# Registers a built Stow.app and its extensions with Launch Services and PlugInKit, so Finder and
# Quick Look use this build (ad-hoc signatures change on every build). Default: the Debug build.
set -e
cd "${0:a:h}/.."
app=${1:-build/Build/Products/Debug/Stow.app}
app=${app:a}
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f -R -trusted "$app"
for ext in "$app"/Contents/PlugIns/*.appex; do
  pluginkit -a "$ext"
  pluginkit -e use -i "$(defaults read "$ext/Contents/Info" CFBundleIdentifier)"
done
qlmanage -r >/dev/null 2>&1 || true
pluginkit -m -v | grep app.stow || true

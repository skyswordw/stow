#!/bin/zsh
# Rebuilds the disk-image test fixtures in Tests/Fixtures (committed; hdiutil can't run inside the
# sandboxed test host). Each holds a tiny ad-hoc-signed app built from a one-line C program, a
# background picture, a volume icon and the usual "Applications" shortcut.
set -e
cd "${0:a:h}/.."
out=Tests/Fixtures
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$out" "$work/vol/.background" "$work/vol/Fixture Tool.app/Contents/MacOS"
print 'int main(void) { return 0; }' > "$work/main.c"
clang -Os -arch arm64 -mmacosx-version-min=26.0 -o "$work/vol/Fixture Tool.app/Contents/MacOS/Fixture Tool" "$work/main.c"
cat > "$work/vol/Fixture Tool.app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Fixture Tool</string>
<key>CFBundleIdentifier</key><string>app.stow.fixture.tool</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
</dict></plist>
PLIST
codesign --force --sign - "$work/vol/Fixture Tool.app"
print -n 'PNG' > "$work/vol/.background/background.png"
print -n 'icns' > "$work/vol/.VolumeIcon.icns"
ln -s /Applications "$work/vol/Applications"
xattr -cr "$work/vol"
hdiutil create -quiet -ov -volname "Fixture Tool" -srcfolder "$work/vol" -fs HFS+ -format UDZO "$out/Fixture-HFS.dmg"
hdiutil create -quiet -ov -volname "Fixture Tool" -srcfolder "$work/vol" -fs APFS -format ULFO "$out/Fixture-APFS.dmg"
ls -l "$out"

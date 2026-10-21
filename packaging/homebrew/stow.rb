# Homebrew cask for Stow — a TEMPLATE. scripts/render-cask.sh fills @VERSION@ and @SHA256@ from a
# GitHub release's DMG (see packaging/homebrew/README.md). Do not hand-edit version or checksum.
cask "stow" do
  version "@VERSION@"
  sha256 "@SHA256@"

  url "https://github.com/skyswordw/stow/releases/download/v#{version}/Stow-#{version}.dmg"
  name "Stow"
  desc "Archive utility to browse, preview, extract and pack 30+ formats"
  homepage "https://skyswordw.github.io/stow/"

  livecheck do
    url :url
    strategy :github_latest
  end

  # Uncomment once Sparkle updates ship (#35): Homebrew then leaves upgrades to the app.
  # auto_updates true
  depends_on macos: :tahoe

  app "Stow.app"

  uninstall quit: "app.stow.Stow"

  zap trash: [
    "~/Library/Application Scripts/app.stow.Stow",
    "~/Library/Application Scripts/app.stow.Stow.Engine",
    "~/Library/Application Scripts/app.stow.Stow.FinderSync",
    "~/Library/Application Scripts/app.stow.Stow.QuickLook",
    "~/Library/Containers/app.stow.Stow",
    "~/Library/Containers/app.stow.Stow.Engine",
    "~/Library/Containers/app.stow.Stow.FinderSync",
    "~/Library/Containers/app.stow.Stow.QuickLook",
  ]
end

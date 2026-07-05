cask "docking" do
  version "0.0.2"
  sha256 "923360ac37536d7b6c4675952039677a93889be7281e12b829b637ecd46498dc"

  url "https://github.com/sk-226/docking/releases/download/v#{version}/Docking-#{version}-macos26.dmg"
  name "Docking"
  desc "Overlay dock with calendar and weather widgets"
  homepage "https://github.com/sk-226/docking"

  depends_on macos: :tahoe

  app "Docking.app"

  zap trash: [
    "~/Library/Application Support/Docking",
    "~/Library/Caches/app.docking.docking",
    "~/Library/Preferences/app.docking.docking.plist",
    "~/Library/Saved Application State/app.docking.docking.savedState",
  ]
end

cask "docking" do
  version "0.0.5"
  sha256 "a0f3013cf337a49b399b74b9bb099988458c1abf552a7fb8e193fbe186027cdd"

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

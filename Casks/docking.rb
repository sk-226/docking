cask "docking" do
  version "0.0.2"
  sha256 "1351e7e1a4795dc1445dd93495634254a0623085657eeaf440f64e1fdb9f2392"

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

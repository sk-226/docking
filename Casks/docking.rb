cask "docking" do
  version "0.0.3"
  sha256 "cea82c01faef0c6c7dceb4f10aefb1b81e65f15fc31805f75ee7fc16d3619bf9"

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

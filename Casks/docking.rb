cask "docking" do
  version "0.0.1"
  sha256 "c673f3d2cb485b0bbd0f78de3a4546e690720798eec9cd381c55272ce4fe0be8"

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

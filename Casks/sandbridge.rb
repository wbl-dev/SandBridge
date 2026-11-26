cask "sandbridge" do
  version "1.0.2"
  sha256 :no_check

  url "https://github.com/wbl-dev/SandBridge/releases/download/v#{version}/SandBridge-#{version}.dmg"
  name "SandBridge"
  desc "Lightweight native macOS iOS physical device sandbox manager powered by devicectl"
  homepage "https://github.com/wbl-dev/SandBridge"

  depends_on macos: ">= :ventura"

  app "SandBridge.app"

  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-cr", "#{appdir}/SandBridge.app"],
                   sudo: false
  end

  zap trash: [
    "~/Library/Caches/SandBridgeIcons",
    "~/Library/Preferences/com.sandbridge.app.plist",
  ]
end

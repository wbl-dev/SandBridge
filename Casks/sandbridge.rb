cask "sandbridge" do
  version "1.0.3"
  sha256 "0ade5b6894032c198a87f3def0364a676d03021566bd8b8291d837923844ecfc"

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

require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))

Pod::Spec.new do |s|
  s.name         = "RnVietmapTrackingPlugin"
  s.version      = package["version"]
  s.summary      = package["description"]
  s.homepage     = package["homepage"]
  s.license      = package["license"]
  s.authors      = package["author"]

  s.platforms    = { :ios => min_ios_version_supported }
  s.source       = { :git => "https://github.com/vietmap-company/rn_vietmap_tracking_plugin.git", :tag => "#{s.version}" }

  s.source_files = "ios/**/*.{swift,m,h}"
  s.private_header_files = "ios/**/*.h"

  # Core Location framework for GPS tracking
  s.frameworks = "CoreLocation"

  # Swift support
  s.swift_version = "5.0"

  install_modules_dependencies(s)
end

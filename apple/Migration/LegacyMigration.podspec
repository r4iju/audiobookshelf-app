# Local pod for the legacy CocoaPods app (ios/App), so the export action links this module
# against the app's own build. Consumed by path only; never published.
Pod::Spec.new do |s|
  s.name = 'LegacyMigration'
  s.version = '1.0.0'
  s.summary = 'Credential-free legacy Audiobookshelf migration archive and migrator.'
  s.homepage = 'https://github.com/advplyr/audiobookshelf-app'
  s.license = { :type => 'GPL-3.0' }
  s.author = 'audiobookshelf'
  s.source = { :path => '.' }
  s.ios.deployment_target = '14.0'
  s.swift_version = '5.9'
  s.source_files = 'Sources/LegacyMigration/**/*.swift'
  s.frameworks = 'CryptoKit'
end

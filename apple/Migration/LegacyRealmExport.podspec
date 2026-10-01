# Local pod for the legacy CocoaPods app (ios/App). It uses the app's own RealmSwift pod, so the
# export reads the database with the same Realm build that wrote it. Consumed by path only.
Pod::Spec.new do |s|
  s.name = 'LegacyRealmExport'
  s.version = '1.0.0'
  s.summary = 'Reads the schema-21 legacy Realm and writes the migration archive inside the legacy app.'
  s.homepage = 'https://github.com/advplyr/audiobookshelf-app'
  s.license = { :type => 'GPL-3.0' }
  s.author = 'audiobookshelf'
  s.source = { :path => '.' }
  s.ios.deployment_target = '14.0'
  s.swift_version = '5.9'
  s.source_files = 'LegacyRealm/Sources/LegacyRealmExport/**/*.swift'
  s.dependency 'LegacyMigration'
  s.dependency 'RealmSwift', '~> 10.54'
end

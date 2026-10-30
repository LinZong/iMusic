#!/usr/bin/env ruby
require 'xcodeproj'
Dir.chdir(File.expand_path('..', __dir__))
project = Xcodeproj::Project.new('iMusic.xcodeproj')
project.root_object.attributes['LastUpgradeCheck'] = '2630'
project.root_object.development_region = 'en'
project.root_object.known_regions = ['en', 'zh-Hans', 'zh-Hant']
project.root_object.attributes['BuildIndependentTargetsInParallel'] = 'YES'
config_group = project.main_group.new_group('Config', 'Config')
base = config_group.new_file('Base.xcconfig')
Dir.glob('Config/*').reject { |p| p.end_with?('Base.xcconfig') }.each { |p| config_group.new_file(File.basename(p)) }
app_group = project.main_group.new_group('Apps', 'Apps')
shared = app_group.new_group('Shared', 'Shared').new_file('iMusicApp.swift')
local_package = project.new(Xcodeproj::Project::Object::XCLocalSwiftPackageReference)
local_package.relative_path = '.'
project.root_object.package_references << local_package
[['iMusic', :ios, '17.0'], ['iMusicMac', :osx, '14.0']].each do |name, platform, minimum|
  target = project.new_target(:application, name, platform, minimum)
  target.source_build_phase.add_file_reference(shared)
  assets = app_group.new_file('Resources/Assets.xcassets')
  target.resources_build_phase.add_file_reference(assets)
  info_strings = app_group.new_variant_group('InfoPlist.strings', 'Resources')
  ['en', 'zh-Hans', 'zh-Hant'].each { |language| reference = info_strings.new_file(language + '.lproj/InfoPlist.strings'); reference.name = language }
  target.resources_build_phase.add_file_reference(info_strings)
  dependency = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
  dependency.product_name = 'iMusicKit'
  dependency.package = local_package
  target.package_product_dependencies << dependency
  build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
  build_file.product_ref = dependency
  target.frameworks_build_phase.files << build_file
  privacy = app_group.new_file('../Sources/iMusicKit/Resources/PrivacyInfo.xcprivacy')
  target.resources_build_phase.add_file_reference(privacy)
  %w[CloudDebug CarPlayDebug FullDebug FullRelease].each { |config| type = config.end_with?('Release') ? :release : :debug; target.add_build_configuration(config, type); project.add_build_configuration(config, type) }
  target.build_configurations.each do |config|
    config.base_configuration_reference = base
    os = platform == :ios ? 'iOS' : 'macOS'
    settings = config.build_settings
    settings.delete('ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME')
    settings['GENERATE_INFOPLIST_FILE'] = 'NO'
    settings['ASSETCATALOG_COMPILER_APPICON_NAME'] = 'AppIcon'
    settings['INFOPLIST_FILE'] = "Config/#{os}-Info.plist"
    settings['PRODUCT_BUNDLE_IDENTIFIER'] = "$(IMUSIC_BUNDLE_PREFIX).#{platform == :ios ? 'ios' : 'mac'}"
    settings['CODE_SIGN_ENTITLEMENTS'] = "Config/#{os}.entitlements"
    settings['IMUSIC_CLOUD_CONTAINER'] = '' unless ['CloudDebug', 'FullDebug', 'FullRelease'].include?(config.name)
    settings['IMUSIC_CLOUD_ENVIRONMENT'] = config.name.end_with?('Release') ? 'Production' : 'Development'
    settings['IMUSIC_APS_ENVIRONMENT'] = config.name.end_with?('Release') ? 'production' : 'development'
    settings['SWIFT_EMIT_LOC_STRINGS'] = 'YES'
    settings['ENABLE_HARDENED_RUNTIME'] = 'YES' if platform == :osx
    settings['TARGETED_DEVICE_FAMILY'] = '1,2' if platform == :ios
    settings['SUPPORTS_MACCATALYST'] = 'NO' if platform == :ios
    settings['SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD'] = 'NO' if platform == :ios
    settings['COMBINE_HIDPI_IMAGES'] = 'YES' if platform == :osx
    if config.name == 'CloudDebug'
      settings['CODE_SIGN_ENTITLEMENTS'] = "Config/#{os}-Cloud.entitlements"
      settings['INFOPLIST_FILE'] = 'Config/iOS-Cloud-Info.plist' if platform == :ios
    elsif config.name.start_with?('Full')
      settings['CODE_SIGN_ENTITLEMENTS'] = platform == :ios ? 'Config/iOS-Full.entitlements' : 'Config/macOS-Cloud.entitlements'
      if platform == :ios
        settings['INFOPLIST_FILE'] = 'Config/iOS-Full-Info.plist'
        settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = '$(inherited) IMUSIC_CARPLAY'
      end
    elsif config.name == 'CarPlayDebug' && platform == :ios
      settings['INFOPLIST_FILE'] = 'Config/iOS-CarPlay-Info.plist'
      settings['CODE_SIGN_ENTITLEMENTS'] = 'Config/iOS-CarPlay.entitlements'
      settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = '$(inherited) DEBUG IMUSIC_CARPLAY'
    end
  end
  {'Debug'=>name, 'CloudDebug'=>name+' Cloud', 'CarPlayDebug'=>name+' CarPlay', 'FullDebug'=>name+' Full'}.each do |configuration, scheme_name|
    next if platform == :osx && configuration == 'CarPlayDebug'
    scheme = Xcodeproj::XCScheme.new
    scheme.add_build_target(target)
    scheme.set_launch_target(target)
    scheme.launch_action.build_configuration = configuration
    scheme.test_action.build_configuration = configuration
    scheme.archive_action.build_configuration = configuration == 'FullDebug' ? 'FullRelease' : 'Release'
    scheme.save_as('iMusic.xcodeproj', scheme_name, true)
  end
end
project.build_configurations.each { |config| config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = '14.0'; config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0' }
project.save
puts 'Generated iMusic.xcodeproj'

#!/usr/bin/env ruby
require 'xcodeproj'

# Shared by full project generation and the one-time addition to an existing checkout.
def configure_ui_tests(project)
  return if project.targets.any? { |target| target.name == 'iMusicUITests' }
  app_group = project.main_group['Apps']
  shared = app_group['Shared']['iMusicApp.swift']
  base = project.main_group['Config']['Base.xcconfig']
  local_package = project.root_object.package_references.find do |package|
    package.isa == 'XCLocalSwiftPackageReference' && package.relative_path == '.'
  end
  # Keep automated UI runs in a separate install and container on both simulators and devices.
  host = project.new_target(:application, 'iMusicUITestHost', :ios, '17.0')
  host.source_build_phase.add_file_reference(shared)
  testing_group = app_group.new_group('Testing', 'Testing')
  Dir.glob('Apps/Testing/*.swift').sort.each do |path|
    host.source_build_phase.add_file_reference(testing_group.new_file(File.basename(path)))
  end
  host.resources_build_phase.add_file_reference(app_group.new_file('Resources/Assets.xcassets'))
  product = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
  product.product_name = 'iMusicKit'
  product.package = local_package
  host.package_product_dependencies << product
  build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
  build_file.product_ref = product
  host.frameworks_build_phase.files << build_file
  host.build_configurations.each do |config|
    config.base_configuration_reference = base
    config.build_settings.merge!({
      'PRODUCT_NAME' => 'iMusicUITestHost',
      'PRODUCT_BUNDLE_IDENTIFIER' => '$(IMUSIC_BUNDLE_PREFIX).uitesting.ios',
      'GENERATE_INFOPLIST_FILE' => 'YES',
      'INFOPLIST_KEY_CFBundleDisplayName' => 'iMusic UI Tests',
      'INFOPLIST_KEY_UIApplicationSceneManifest_Generation' => 'YES',
      'INFOPLIST_KEY_UILaunchScreen_Generation' => 'YES',
      'INFOPLIST_KEY_UISupportedInterfaceOrientations' => 'UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight',
      'SWIFT_ACTIVE_COMPILATION_CONDITIONS' => '$(inherited) IMUSIC_UI_TESTING',
      'ASSETCATALOG_COMPILER_APPICON_NAME' => 'AppIcon',
      'ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME' => '',
      'TARGETED_DEVICE_FAMILY' => '1,2',
      'SUPPORTS_MACCATALYST' => 'NO',
      'SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD' => 'NO',
      'IMUSIC_CLOUD_CONTAINER' => ''
    })
  end
  ui_tests = project.new_target(:ui_test_bundle, 'iMusicUITests', :ios, '17.0')
  ui_tests.add_dependency(host)
  tests_group = project.main_group.new_group('UITests', 'UITests')
  ui_group = tests_group.new_group('iMusicUITests', 'iMusicUITests')
  Dir.glob('UITests/iMusicUITests/*.swift').sort.each do |path|
    ui_tests.source_build_phase.add_file_reference(ui_group.new_file(File.basename(path)))
  end
  ui_tests.build_configurations.each do |config|
    config.base_configuration_reference = base
    config.build_settings.merge!({
      'PRODUCT_NAME' => 'iMusicUITests',
      'PRODUCT_BUNDLE_IDENTIFIER' => '$(IMUSIC_BUNDLE_PREFIX).uitesting.tests',
      'GENERATE_INFOPLIST_FILE' => 'YES',
      'TEST_TARGET_NAME' => 'iMusicUITestHost',
      'TARGETED_DEVICE_FAMILY' => '1,2',
      'SUPPORTS_MACCATALYST' => 'NO',
      'SWIFT_EMIT_LOC_STRINGS' => 'NO'
    })
  end
  project.root_object.attributes['TargetAttributes'] ||= {}
  project.root_object.attributes['TargetAttributes'][ui_tests.uuid] = {
    'TestTargetID' => host.uuid
  }
  scheme = Xcodeproj::XCScheme.new
  scheme.add_build_target(host)
  scheme.add_test_target(ui_tests)
  scheme.set_launch_target(host)
  scheme.test_action.build_configuration = 'Debug'
  scheme.test_action.xml_element.attributes['shouldUseLaunchSchemeArgsEnv'] = 'NO'
  scheme.save_as('iMusic.xcodeproj', 'iMusic UI Tests', true)
end

if $PROGRAM_NAME == __FILE__
  Dir.chdir(File.expand_path('..', __dir__))
  project = Xcodeproj::Project.open('iMusic.xcodeproj')
  configure_ui_tests(project)
  project.save
  puts 'Configured isolated UI test targets'
end

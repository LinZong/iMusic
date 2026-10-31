#!/usr/bin/env ruby
require 'xcodeproj'

# Reuses stable source references when adding files or targets to an existing checkout.
def ui_test_source(group, path)
  directory = File.dirname(path)
  parent = group
  unless directory == '.'
    directory.split('/').each do |component|
      parent = parent[component] || parent.new_group(component, component)
      parent.path = component
    end
  end
  parent.files.find { |file| file.path == File.basename(path) } || parent.new_file(File.basename(path))
end

# Configures isolated native hosts and a common regression suite for both Apple platforms.
def configure_ui_tests(project)
  app_group = project.main_group['Apps']
  shared = app_group['Shared']['iMusicApp.swift']
  testing_group = app_group['Testing'] || app_group.new_group('Testing', 'Testing')
  tests_group = project.main_group['UITests'] || project.main_group.new_group('UITests', 'UITests')
  ui_group = tests_group['iMusicUITests'] || tests_group.new_group('iMusicUITests', 'iMusicUITests')
  base = project.main_group['Config']['Base.xcconfig']
  local_package = project.root_object.package_references.find do |package|
    package.isa == 'XCLocalSwiftPackageReference' && package.relative_path == '.'
  end
  assets = app_group.files.find { |file| file.path == 'Resources/Assets.xcassets' }
  assets ||= app_group.new_file('Resources/Assets.xcassets')

  [[:ios, '17.0', 'iMusic', 'ios'], [:osx, '14.0', 'iMusicMac', 'mac']].each do |platform, minimum, prefix, suffix|
    host_name = prefix + 'UITestHost'
    host = project.targets.find { |target| target.name == host_name }
    host ||= project.new_target(:application, host_name, platform, minimum)
    sources = [shared] + Dir.glob('Apps/Testing/*.swift').sort.map do |path|
      ui_test_source(testing_group, File.basename(path))
    end
    sources.each do |source|
      host.source_build_phase.add_file_reference(source) unless host.source_build_phase.files_references.include?(source)
    end
    host.resources_build_phase.add_file_reference(assets) unless host.resources_build_phase.files_references.include?(assets)
    if host.package_product_dependencies.empty?
      product = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
      product.product_name = 'iMusicKit'
      product.package = local_package
      host.package_product_dependencies << product
      build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
      build_file.product_ref = product
      host.frameworks_build_phase.files << build_file
    end
    host.build_configurations.each do |config|
      config.base_configuration_reference = base
      config.build_settings.merge!({
        'PRODUCT_NAME' => host_name,
        'PRODUCT_BUNDLE_IDENTIFIER' => "$(IMUSIC_BUNDLE_PREFIX).uitesting.#{suffix}",
        'GENERATE_INFOPLIST_FILE' => 'YES',
        'INFOPLIST_KEY_CFBundleDisplayName' => prefix + ' UI Tests',
        'SWIFT_ACTIVE_COMPILATION_CONDITIONS' => '$(inherited) IMUSIC_UI_TESTING',
        'ASSETCATALOG_COMPILER_APPICON_NAME' => 'AppIcon',
        'ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME' => '',
        'IMUSIC_CLOUD_CONTAINER' => ''
      })
      if platform == :ios
        config.build_settings.merge!({
          'INFOPLIST_KEY_UIApplicationSceneManifest_Generation' => 'YES',
          'INFOPLIST_KEY_UILaunchScreen_Generation' => 'YES',
          'INFOPLIST_KEY_UISupportedInterfaceOrientations' => 'UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight',
          'TARGETED_DEVICE_FAMILY' => '1,2',
          'SUPPORTS_MACCATALYST' => 'NO',
          'SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD' => 'NO'
        })
      else
        config.build_settings.merge!({
          'CODE_SIGN_ENTITLEMENTS' => 'Config/macOS.entitlements',
          'ENABLE_HARDENED_RUNTIME' => 'NO',
          'INFOPLIST_KEY_NSPrincipalClass' => 'NSApplication',
          'INFOPLIST_KEY_LSApplicationCategoryType' => 'public.app-category.music'
        })
      end
    end

    test_name = prefix + 'UITests'
    ui_tests = project.targets.find { |target| target.name == test_name }
    ui_tests ||= project.new_target(:ui_test_bundle, test_name, platform, minimum)
    ui_tests.add_dependency(host) unless ui_tests.dependencies.any? { |dependency| dependency.target == host }
    Dir.glob('UITests/iMusicUITests/**/*.swift').sort.each do |path|
      source = ui_test_source(ui_group, path.delete_prefix('UITests/iMusicUITests/'))
      ui_tests.source_build_phase.add_file_reference(source) unless ui_tests.source_build_phase.files_references.include?(source)
    end
    ui_tests.build_configurations.each do |config|
      config.base_configuration_reference = base
      config.build_settings.merge!({
        'PRODUCT_NAME' => test_name,
        'PRODUCT_BUNDLE_IDENTIFIER' => "$(IMUSIC_BUNDLE_PREFIX).uitesting.#{suffix}.tests",
        'GENERATE_INFOPLIST_FILE' => 'YES',
        'TEST_TARGET_NAME' => host_name,
        'SWIFT_EMIT_LOC_STRINGS' => 'NO'
      })
      if platform == :ios
        # Preserve the existing iOS test-bundle identity for installed runners.
        config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = '$(IMUSIC_BUNDLE_PREFIX).uitesting.tests'
        config.build_settings['TARGETED_DEVICE_FAMILY'] = '1,2'
        config.build_settings['SUPPORTS_MACCATALYST'] = 'NO'
      end
    end
    project.root_object.attributes['TargetAttributes'] ||= {}
    project.root_object.attributes['TargetAttributes'][ui_tests.uuid] = { 'TestTargetID' => host.uuid }
    scheme = Xcodeproj::XCScheme.new
    scheme.add_build_target(host)
    scheme.add_test_target(ui_tests)
    scheme.set_launch_target(host)
    scheme.test_action.build_configuration = 'Debug'
    scheme.test_action.xml_element.attributes['shouldUseLaunchSchemeArgsEnv'] = 'NO'
    scheme.save_as('iMusic.xcodeproj', prefix + ' UI Tests', true)
  end
end

if $PROGRAM_NAME == __FILE__
  Dir.chdir(File.expand_path('..', __dir__))
  project = Xcodeproj::Project.open('iMusic.xcodeproj')
  configure_ui_tests(project)
  project.save
  puts 'Configured isolated iOS and macOS UI test targets'
end

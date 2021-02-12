# Author: Lev Trubov
# © 2021 Freestar, Inc.

# Freestar-Nimbus-SDK

Pod::Spec.new do |spec|
	spec.name                = 'Freestar-Nimbus-SDK'
	spec.version             = '1.7.1'
	spec.author              = 'Freestar'
	spec.license             = { :type => 'Apache2.0', :file => 'LICENCE.md' }
	spec.homepage            = 'http://www.freestar.com'
	spec.summary             = 'Helper Pod containing the Nimbus SDK in support of the Freestar Ads system'
	spec.platform            = :ios, '10.0'
	
	spec.dependency 'FBAudienceNetwork', '~> 6.2'
	spec.static_framework = true
	spec.swift_version = '5.3'

	spec.vendored_frameworks = [
		'cocoapods/nimbus/NimbusKit.xcframework', 
		'cocoapods/nimbus/NimbusCoreKit.xcframework',
		'cocoapods/nimbus/NimbusRenderKit.xcframework',
		'cocoapods/nimbus/NimbusRequestKit.xcframework',
		'cocoapods/nimbus/NimbusRenderStaticKit.xcframework',
		'cocoapods/nimbus/NimbusRenderVideoKit.xcframework'
	]
	
	spec.source_files = 'cocoapods/nimbus/NimbusFAN/**/*.swift'

	spec.source            = {
			:git => "https://github.com/freestarcapital/freestar-custom-cocoapods.git",
			:tag => 'v1.7.1'
	}

	spec.user_target_xcconfig = { 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'arm64' }
	spec.pod_target_xcconfig = { 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'arm64' }
end

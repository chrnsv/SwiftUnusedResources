Pod::Spec.new do |spec|
  spec.name                         = 'SwiftUnusedResources'
  spec.summary                      = 'SwiftUnusedResources'
  spec.homepage                     = 'https://github.com/mugabe/SwiftUnusedResources'
  spec.version                      = '0.0.1'
  spec.license                      = 'MIT'
  spec.authors                      = { 'mugabe' => 'https://github.com/mugabe' }
  spec.preserve_paths               = 'sur'
  spec.source            			= { :http => "https://github.com/mugabe/SwiftUnusedResources/releases/download/#{spec.version}/sur-#{spec.version}.zip" }
end

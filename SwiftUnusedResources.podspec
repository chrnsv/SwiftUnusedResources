Pod::Spec.new do |spec|
  spec.name                         = 'SwiftUnusedResources'
  spec.summary                      = 'SwiftUnusedResources'
  spec.homepage                     = 'https://github.com/mugabe/SwiftUnusedResources'
  spec.version                      = '0.0.8'
  spec.license                      = 'MIT'
  spec.authors                      = { 'mugabe' => 'kk@wachanga.com' }
  spec.preserve_paths               = 'sur', 'lib_InternalSwiftSyntaxParser.dylib'
  spec.source                       = { :http => "https://github.com/mugabe/SwiftUnusedResources/releases/download/#{spec.version}/sur-#{spec.version}.zip" }
end

Pod::Spec.new do |spec|
  spec.name                         = 'SwiftUnusedResources'
  spec.summary                      = 'SwiftUnusedResources'
  spec.homepage                     = 'https://github.com/mugabe/SwiftUnusedResources'
  spec.version                      = '0.0.2'
  spec.license                      = 'MIT'
  spec.authors                      = { 'mugabe' => 'kk@wachanga.com' }
  spec.preserve_paths               = 'sur', 'lib_InternalSwiftSyntaxParser.dylib'
  spec.source                       = { :http => "https://github.com/mugabe/SwiftUnusedResources/releases/download/v#{spec.version}/sur-v#{spec.version}.zip" }
end

Pod::Spec.new do |s|
  s.name             = 'handrail_bug_reporter'
  s.version          = '0.1.26'
  s.summary          = 'Reusable Flutter integration surface for Handrail mobile bug reports.'
  s.description      = <<-DESC
Reusable Flutter integration surface for submitting Handrail mobile bug reports.
                       DESC
  s.homepage         = 'https://dashboard.handrail-daas.com'
  s.license          = { :type => 'MIT' }
  s.author           = { 'Handrail' => 'support@handrail-daas.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '12.0'
  s.swift_version    = '5.0'
end

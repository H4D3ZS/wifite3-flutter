#!/usr/bin/env ruby
# run this on your Mac before building!
# gem install xcodeproj
require 'xcodeproj'

project_path = 'ios/Runner.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.find { |t| t.name == 'Runner' }

# Add source files
files_to_add = [
  'ios/Runner/Apple80211Backend.mm',
  'ios/Runner/MethodChannelHandler.mm',
  'ios/Runner/RTL8192EUBackend.mm',
  'ios/Runner/Rtl8192eudriver.mm',
  'ios/Runner/Rtl8192eudriver.h',
  'ios/Runner/WiFiBackend.h',
  'ios/Runner/rtl8192eufw.bin'
]

group = project.main_group.find_subpath(File.join('Runner'), true)
resources_phase = target.resources_build_phase

files_to_add.each do |file_path|
  file_name = File.basename(file_path)
  
  # Check if file already exists in project
  unless group.files.any? { |f| f.path == file_name }
    file_reference = group.new_reference(file_name)
    
    if file_name.end_with?('.mm', '.m', '.swift', '.cpp', '.c')
      target.add_file_references([file_reference])
      puts "Added #{file_name} to Compile Sources"
    elsif file_name.end_with?('.bin', '.plist') && file_name != 'entitlements.plist'
      resources_phase.add_file_reference(file_reference)
      puts "Added #{file_name} to Resources"
    else
      puts "Added #{file_name} to Project Navigator"
    end
  else
    puts "#{file_name} is already in the project."
  end
end

project.save
puts "Successfully updated Xcode project."

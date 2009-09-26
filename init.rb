# Include hook code here
puts "in init.rb ****************************** #{directory}"

$LOAD_PATH << File.join(directory, "lib")

%w{ models controllers helpers views }.each do |dir|
  path = File.join(directory, 'lib', dir)
  $LOAD_PATH << path
  Dependencies.load_paths << path
  Dependencies.load_once_paths.delete(path)
end

require "acts_with_metadata"
require "acts_with_metadata_helper.rb"
require "acts_as_metadata_crud_controller.rb"


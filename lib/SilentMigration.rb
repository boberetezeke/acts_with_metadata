require "SimpleTrace"

class Silent_Migration < ActiveRecord::Migration
	class << self
	def announce(x); $TRACE.debug 5, "announce: #{x}"; end
	def say(x,y=false); $TRACE.debug 5, "say: #{x}"; end
	def write(x=""); $TRACE.debug 5, "write: #{x}"; end
	end
end



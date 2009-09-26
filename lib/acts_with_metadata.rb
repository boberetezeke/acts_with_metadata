gem "activerecord"
require "active_record"
require "SimpleTrace"
require "SilentMigration"
require "singleton"

module ActiveRecord #:nodoc:
  module Acts #:nodoc:
 	# Specify this act if you want to have the your model have a view driven by
  	# meta-data.
  	
   # Example:
   #
   #   class Auto < ActiveRecord::Base
   #     acts_with_metadata
   #
   #     has_field "make", :type => :pull_down, :choices => ["Toyota", "GM", "Other"]
   #			has_field "model", :type => :text_field
   #			has_many "tires" 
   #   end
	module WithMetaData
      def self.included(base) # :nodoc:
        base.extend ClassMethods
      end

		#
		# This exception is thrown if a model that includes acts_with_metadata doesn't exist within the database.
		# It can be caught to add the necessary table (through a migration) to the database
		#
		class TableNotFoundError < StandardError
			attr_reader :table_name
			def initialize(table_name)
				@table_name = table_name
				super "table #{table_name} does not exist in database"
			end
		end

		#
		# This exception is thrown if a field does not exist in the table associated with the model that includes
		# acts_with_metadata. It can be caught to add the necessary field to the table (through a migration)
		# to the database
		#
		class FieldNotFoundError < StandardError
			attr_reader :class_name, :table_name, :field_name, :field_type
			def initialize(class_name, table_name, field_name, field_type, defaults_to=nil)
				@class_name = class_name
				@table_name = table_name
				@field_name = field_name
				@field_type = field_type
				@defaults_to = defaults_to
				super "field '#{field_name}' does not exist in database table #{table_name}"
			end
		end
		
		# FIXME: version shouldn't be in here, but it doesn't work to use :excluded_columns on ActiveRecord::Base sub-classes
		BUILT_IN_COLUMNS = %w{id created_at created_on updated_at updated_on type version}

		#
		# These methods are available inside of the class definitions like ActiveRecord methods (e.g. has_many)
		#
		module ClassMethods #:doc:
			attr_reader :declared_members, :default_members
			attr_reader :editlink_proc, :editlink_fields

			# ------------------------ Model directives ---------------------------------
			
			#
			# put this at the top of the model class to allow acts_with_metadata functionality
			#
			# options
			#   :re_initialize - force class re-init when it is included
			#   :excluded_columns - don't add this array of columns to members
			#
			def acts_with_metadata(options = {})
				$TRACE.debug 5, "acts_with_metadata (call): #{self.inspect} included?(#{self.included_modules.include?(ActiveRecord::Acts::WithMetaData::ActMethods)}), declared_members = #{@declared_members} options = #{options.inspect}"

				
				initialize_class(options) if options[:re_initialize] || !defined?(@declared_members)

         	# don't allow multiple calls
 				return if self.included_modules.include?(ActiveRecord::Acts::WithMetaData::ActMethods)
 				
				class_eval do
					include ActiveRecord::Acts::WithMetaData::ActMethods
				end
			end

			#
			# use this to specify the fields used in the link proc. This is a performance enhancement to force the loading of
			# only the fields you need to produce the link text. Helps on tables that have columns with a lot of data  in them.
			#
			def link_fields(*args)
				@editlink_fields = args
			end
			
			#
			# use this to specify proc used for the link text
			#
			def link_text(&p)
				$TRACE.debug 5, "saving link proc for self = #{self.inspect}, self.object_id = #{self.object_id}"
				@editlink_proc = p

				module_eval do
					def to_label
						#p.call(self, self)
						#"my label #{p.inspect}, #{self.inspect}"
						self.editlink(self)
					end
				end
			end

			#
			# use this to specify what to order the records on (SQL snippet)
			#
			def list_order(order_str)
				@params[:list_order_str] = order_str
			end

			#
			# use this to specify the number of items to retreive from the database
			#
			def list_limit(limit)
				@params[:list_limit] = limit
			end

			#
			# use this to specify which actions are in the list (possible values are "edit", "delete")
			#
			def list_actions(actions)
				@params[:list_actions] = actions
			end

			#
			# use this to specify if tags should be shown
			#
			def list_tags
				@params[:list_tags] = true
			end

			#
			# list of members shown in the list view
			#
			def list_members(members)
				@params[:list_members] = members
			end
			
			#
			# list of members shown in the list view
			#
			def show_members(members)
				@params[:show_members] = members
			end

			#
			# list of members shown in the list view
			#
			def edit_members(members)
				@params[:edit_members] = members
			end
			

			#
			# use this to select what field is used as the link in a list view
			#
			def link_field(field_name)
				@params[:link_field] = field_name.to_s
			end

			#
			# this is the same as the built-in ActiveRecord::has_many, but with additional
			# options:
			#
			# * display_name - what is displayed for this field title (default: the field name with _'s replaced with spaces)
			# * options - options to pass to the control that implements this field
			# * controller - name of controller to use for this object
			# * choices - array of choices or proc to return an array of choices for this field
			# * read_only - true if the field is read-only
			#
			def has_many(field_name_symbol, options={})
				$TRACE.debug 5, "has_many: #{self} - #{field_name_symbol}"
				association_internal(field_name_symbol, :has_many, options)
				super(field_name_symbol, options)
			end

			#
			# this is the same as the built-in ActiveRecord::belongs_to, but with additional
			# options:
			#
			# * display_name - what is displayed for this field title (default: the field name with _'s replaced with spaces)
			# * options - options to pass to the control that implements this field
			# * controller - name of controller to use for this object
			# * choices - array of choices or proc to return an array of choices for this field
			# * read_only - true if the field is read-only
			# * internal_user_only - true if field is not to be added to list of declared fields
			#
			def belongs_to(field_name_symbol, options={})
				$TRACE.debug 5, "belongs_to: #{self} - #{field_name_symbol}"

				if options[:internal_use_only] then
					options.delete(:internal_use_only)
					super(field_name_symbol, options)
				else
					if options[:foreign_key] then
						column_name = options[:foreign_key].to_s
					else
						column_name = field_name_symbol.to_s + "_id"				
					end
					column_name_symbol = column_name.intern
					$TRACE.debug 5, "belongs_to: column to look for #{column_name_symbol.inspect}"

					# FIXME: virtual relationships possible?				
					raise FieldNotFoundError.new(self.to_s, table_name, column_name_symbol, :integer) unless columns.map{|c| c.name}.include?(column_name_symbol.to_s)
			
					member = association_internal(field_name_symbol, :belongs_to, options)
					super(field_name_symbol, options)

					return unless defined?(@includes_acts_with_metadata)
					
					member.primary_key_name = self.reflect_on_association(field_name_symbol).primary_key_name
				end
			end

			#
			# this is the same as the built-in ActiveRecord::has_and_belongs_to_many, but with additional
			# options:
			#
			# * display_name - what is displayed for this field title (default: the field name with _'s replaced with spaces)
			# * options - options to pass to the control that implements this field
			# * controller - name of controller to use for this object
			# * choices - array of choices or proc to return an array of choices for this field
			# * read_only - true if the field is read-only
			#
			def has_and_belongs_to_many(field_name_symbol,          options={})
				$TRACE.debug 5, "has_and_belongs_to_many: #{self} - #{field_name_symbol}"
				association_internal(field_name_symbol, :has_and_belongs_to_many, options)
				super(field_name_symbol, options)
			end

			# 
			# this allows the user to specify additional information about a field, like
			# the type of control to use for it, the choices available and whether it
			# is read-only or not. Additional options include:
			#
			# * display_name - what is displayed for this field title (default: the field name with _'s replaced with spaces)
			# * type - this is the type of the field ala migrations (:string, :text, :integer, etc)
			# * options - options to pass to the control that implements this field
			# * choices - this is an array of strings that are valid choices for this field
			# * read_only - the field can't be edited (only displayed)
			# * is_virtual - this is a calculated field that is not in the database
			# * defaults_to - this is the default for the field
			#
			def has_field(field_name_symbol, options={})
				#initialize_members
				$TRACE.debug 5, "has_field in class #{self}, columns = #{columns.map{|c| c.name}.join(',')}"
				raise FieldNotFoundError.new(self.to_s, table_name, field_name_symbol, options[:type], options[:defaults_to]) unless columns.map{|c| c.name}.include?(field_name_symbol.to_s) || options[:is_virtual]

				field_setup_internal(field_name_symbol, options)
=begin
				opts = options[:options] || {}
				interfaces = options[:interfaces] || {}
				$TRACE.debug 5, "has_field: field_name_symbol.to_s = #{field_name_symbol.to_s}"
				$TRACE.debug 5, "has_field: options = #{options.inspect}"

				# set up defaults using defaults plugin
				if defined?(::ActiveRecord::Defaults) then
					if default_to = options[:defaults_to] then
						if default_to.respond_to?(:call) then
							default field_name_symbol, &default_to
						else
							default field_name_symbol => default_to
						end
					end
				end
=end				
				#choices = choices.map{|c| c.kind_of?(Symbol) ? _(c) : c}   # this is necessary for old symbol lookup string table
				@declared_members << ::ActiveRecord::Acts::WithMetaData::MetaData.new(
													self, field_name_symbol.to_s, 
													options)									
				#									:field_type => options[:type],
				#									:interfaces => interfaces,
				#									:from_s => options[:from_s],
				#									:choices => options[:choices],
				#									:control_type => options[:control_type],
				#									:read_only => options[:read_only],
				#									:is_declared => true,
				#									:defaults_to => options[:defaults_to],
				#									:options => opts)
			end

			#
			# This sets the default display name for a class or if called without an argument returns the display_name that is set for
			# this class
			#
			def display_name(str=nil)
				if str then
					@display_name = str
				else
					if @display_name then
						@display_name
					else
						@display_name = self.to_s.tableize.gsub(/_/, " ").capitalize
					end
				end
			end

			def interfaces(interfaces_hash=nil)
				if interfaces_hash then
					@interfaces = interfaces_hash
				else
					if @interfaces then
						@interfaces
					else
						@interfaces = {}
					end
				end
			end
			
			#
			# this is to be used by the view to get the meta data for this class
			#
			def members(use_only_declared_members=false)
				$TRACE.debug 9, "@declared_members = #{@declared_members.map{|x| x.field_name}.inspect}"
				m = @declared_members
				m.merge(@default_members) if use_only_declared_members
				$TRACE.debug 9, "def members: @declared_members merged = #{m.map{|x| x.field_name+'::'+x.options.inspect}.inspect}"
				#@params[:members_to_display] = m
				m
			end

			#
			# this returns the modifiable parameters associated with the class. These include:
			#
			# * list_limit - the number of records per list page (set by list_limit directive, default: 1000)
			# * list_order -the sql snippet used to order list results on a page (set by list_order directive, default: "id")
			# * list_find_spec - first argument to find clause (default: :all)
			#
			def params
				# make sure that members to display is right up to date with all declarations
				#@params[:members_to_display] = members
				@params
			end

			def add_to_built_in_columns(*columns)
				BUILT_IN_COLUMNS << columns.flatten.map{|x| x.to_s}
			end

			
			# --------------------------------------------------------------------------------
			private

			
			#
			# this is called to initialize acts_with_metadata for this class
			#
			def initialize_class(options) #:nodoc: all
				begin
					columns
				rescue Exception => e
					$TRACE.debug 5, "exception while calling columns in initialize_class = #{e.message}"
					$TRACE.debug 9, "backtrace = " + e.backtrace.join("\n")
					raise TableNotFoundError.new(table_name)
				end

				@includes_acts_with_metadata = true
				@default_members = Members.new
				@declared_members = Members.new
				@options = options
				@editlink_fields = ["*"]
				
				@params = {
					:list_order_str => "id",				# default list order is by id
					:list_find_spec => :all,				# default listing is of all records
					:list_conditions => nil,					# no conditions by default
					:list_limit => 20,						# default limit is 1000 records
					:list_page_param_name => "page"		# default param name is page
				}
				
				$TRACE.debug 5, "initialize_class before @class = #{self}"
				$TRACE.debug 9, "initialize_class @default_members = #{@default_members}"
				$TRACE.debug 9, "initialize_class @declared_members = #{@declared_members}"
				$TRACE.debug 9, "initialize_class included modules = #{self.included_modules.map{|x| x.to_s}.join(',')}"
				$TRACE.debug 9, "initialize_class included modules = #{self.superclass.included_modules.map{|x| x.to_s}.join(',')}"
				#if self.superclass.included_modules.include(
				if self.superclass != ActiveRecord::Base then
					# make sure the table has a type field
					raise FieldNotFoundError.new(self, table_name, "type", :string) unless self.columns.map{|x| x.name}.include?("type")
					
					$TRACE.debug 5, "superclass = #{self.superclass}"
					$TRACE.debug 9, "form order = #{self.superclass.members}"

					@default_members << self.superclass.default_members.dup
					@declared_members << self.superclass.declared_members.dup
				end

				columns.each do |column|
					# don't add implicit rails columns
					# FIXME: need to acknowledge changed names that active record users can use
					unless BUILT_IN_COLUMNS.include?(column.name) || 
							/_id$/.match(column.name) || 
							(@options.has_key?(:excluded_columns) && @options[:excluded_columns].map{|x| x.to_s}.include?(column.name))
						$TRACE.debug 5, "adding table columns: name = #{column.name}"
						# FIXME: what to do with column.default_value
						@default_members << ::ActiveRecord::Acts::WithMetaData::MetaData.new(
														self, column.name, 
														:options => {}, 
														:field_type => column.type)
					end
				end
				
				$TRACE.debug 5, "initialize_class after @class = #{self}"
				$TRACE.debug 9, "initialize_class @default_members = #{@default_members}"
				$TRACE.debug 9, "initialize_class @declared_members = #{@declared_members}"
			end

			#def editlist_order
			#	@order_str ||= "id"
			#	@order_str
			#end

			#
			# 
			#
			def field_setup_internal(field_name_symbol, options)
=begin
				# set up defaults using defaults plugin
				if defined?(::ActiveRecord::Defaults) then
					if defaults_to = options[:defaults_to] then
						if defaults_to.respond_to?(:call) then
							default field_name_symbol, &defaults_to
						else
							default field_name_symbol => defaults_to
						end
					end
				end
=end
			end
			
			#
			# this routine is used by all the relationship associations (has_many, belongs_to, etc)
			#
			def association_internal(field_name_symbol, field_type, options={})
				return unless defined?(@includes_acts_with_metadata)
				
				#initialize_members
				field_name = field_name_symbol.to_s

				field_setup_internal(field_name_symbol, options)
=begin
				opts = options[:options] || {}
				interfaces = options[:interfaces] || {}
				unless klass_name = options[:class_name]
					if field_type == :belongs_to then
						klass_name = field_name.camelize
					else
						klass_name = field_name.singularize.camelize
					end
				end
				#klass = Object.const_get(klass_name)
				unless choices = options[:choices]
					choices = proc{Object.const_get(klass_name).find_all}
				end
				unless controller = options[:controller]
					if field_type == :belongs_to then
						controller = field_name
					else
						controller = field_name.singularize
					end
				end
=end
				merge_options = {}
				merge_options[:field_type] = field_type
				
				unless klass_name = options[:class_name]
					if field_type == :belongs_to then
						klass_name = field_name.camelize
					else
						klass_name = field_name.singularize.camelize
					end
					merge_options[:field_class_name] = klass_name
				end
				#klass = Object.const_get(klass_name)
				unless options[:choices]
					merge_options[:choices] = proc{Object.const_get(klass_name).find(:all)}
				end
$TRACE.debug 5, "association_internal: controller (in) - #{merge_options[:controller].inspect}"
				unless options[:controller]
					if field_type == :belongs_to then
						merge_options[:controller] = field_name
					else
						merge_options[:controller] = field_name.singularize
					end
				end
$TRACE.debug 5, "association_internal: controller (out) - #{merge_options[:controller].inspect}"

				$TRACE.debug 9, "association_interal before: declared_members = #{@declared_members}"
				member = ::ActiveRecord::Acts::WithMetaData::MetaData.new(
												self, field_name,
												options.merge(merge_options))
				#								:options => opts,
				#								:interfaces => interfaces,
				#								:from_s => options[:from_s],
				#								:field_type => field_type,
				#								:choices => choices,
				#								:controller => controller,
				#								:klass_name => klass_name,
				#								:is_declared => true)

#if field_name.to_s == "tasks"
#	puts("member = #{member.inspect}")
#end
	
				$TRACE.debug 9, "association_interal after: declared_members = #{@declared_members}"
				[:options, :choices, :controller,
				 :read_only, :display_name, :display_partial, :edit_partial].each {|key| options.delete(key)}
				@declared_members << member
				member
			end

=begin
			def editform
				form = []
#=begin
				# this is code to automatically add on non-relationship fields if there are
				# no has_field calls so far
				non_relationship_fields = @form_order.reject {|nub| [:has_many, :belongs_to, :has_and_belongs_to].include(nub[2])}
				if non_relationship_fields.empty? then
					columns.each do |column|
						if column.
#end
				#@members.each do |member|
				#	form << ActiveRecord::Acts::MetaData.new(self, *member)
				#end
				#form
				self.members
			end
=end
		end # module ClassMethods

		#
		# This method is available on an object whose class includes acts_with_metadata
		#
		module ActMethods #:doc:
			#
			# return the link text for a given object that is being displayed as part of the context_object
			#
			def editlink(context_object)
				#"bob"
				$TRACE.debug 5, "self.class = #{self.class.inspect} self.class.object_id = #{self.class.object_id}"
				$TRACE.debug 5, "self = #{self.inspect}, context_object = #{context_object.inspect}"
				if self.class.editlink_proc then
					self.class.editlink_proc.call(self, context_object)
				else
					self.id.to_s
				end
			end

			def members_for_class
				self.class.members
			end

			def params_for_class
				self.class.params
			end

			def display_name_for_class
				self.class.display_name
			end
		end # module ActMethods
		
		#
		# class used to hold array/hash of class member's meta data
		#
		class Members # :nodoc:
			attr_reader :member_array, :member_hash
			def initialize(members=nil)
				if members then
					@member_array = members.member_array.dup
					@member_hash = members.member_hash.dup
				else
					@member_array = []
					@member_hash = {}
				end
			end

			def to_s
				@member_array.map{|x| x.field_name}.join(",")
			end
			
			# 
			# add either a member or all members in a Members object 
			#
			def <<(arg)
				if arg.kind_of?(Members) then
					arg.each {|md| push(md)}
				else
					if @member_hash[arg.field_name] then
						@member_hash[arg.field_name] = arg
						@member_array[@member_array.index(arg)] = arg
					else
						push(arg)
					end
				end
			end

			#
			# push a member onto the Members object
			#
			def push(arg)
				@member_array.push(arg)
				@member_hash[arg.field_name] = arg
			end

			#
			# select a member based on the field name
			#
			def [](arg)
				@member_hash[arg.to_s]
			end

			#
			# the number of members in the Members object
			#
			def size
				@member_array.size
			end

			#
			# iterate over the members objects in the order in which they were added
			#
			def each
				@member_array.each {|x| yield x}
			end

			#
			# iterate over the members objects in the order in which they were added with the index included
			#
			def each_with_index
				@member_array.each_with_index {|x,i| yield x,i}
			end

			def each_key
				@member_hash.each_key{|x| yield x}
			end
			
			#
			# do the enumerable map function for Members
			#
			def map
				@member_array.map {|x| yield x}
			end


			#
			# do enumerable function select for Members
			#
			def select
				@member_array.select{|x| yield x}
			end
			
			#
			# takes a either an array of symbols or strings or arguments that are symbols or strings
			# and re-orders and selects the members contained so that it will contain only those
			# specified
			#
			def select_and_order_members(*args)
				members_to_select = args.kind_of?(Array) ? args[0] : args

				# rebuild array from hash
				@member_array = []
				members_to_select.each {|member_name| @member_array.push(@member_hash[member_name.to_s]) if @member_hash.has_key?(member_name.to_s)}
				# rebuild hash from array
				@member_hash = {}
				@member_array.each {|member| @member_hash[member.field_name] = member}
			end
			
			# 
			# merge in another members object using (members!)
			#
			def merge(members)
				m = Members.new(self)
				m.merge!(members)
				m
			end

			#
			# This merges members into self where each member is added if it is not in self
			#
			def merge!(members)
				$TRACE.debug 9, "merge before: #{@member_array.map{|n| n.field_name+'::'+n.options.inspect}.join(',')}"

				members.each do |m| 
					$TRACE.debug 9, "merge: #{m.field_name}: options=#{m.options.inspect}"

					#$TRACE.debug 5, "merge: delete: #{m.field_name}"
					#@member_array.delete_if {|n| m.field_name == n.field_name}

					if !@member_hash.has_key?(m.field_name) then
						@member_array.push(m)
						@member_hash[m.field_name] = m
						#$TRACE.debug 5, "merge: delete: #{m.field_name}"
						#@member_array.delete_if {|n| m.field_name == n.field_name}
					end
				end

				$TRACE.debug 9, "merge after: #{@member_array.map{|n| n.field_name+'::'+n.options.inspect}.join(',')}"
				self
			end

			#
			# take a member out of the Members in the order in which they were added
			#
			def shift
				m = @member_array.shift
				@member_hash.delete(m.field_name)
				m
			end

			#
			# duplicate not only the hash and array, but the member objects as well
			#
			def dup
				#Marshal.load(Marshal.dump(self))
				ms = Members.new
				@member_array.each do |m|
					ms.push(m.dup)
				end
				ms
			end
		end


		#
		# this class encapsulates information about one field of an ActiveRecord class
		#
		#
		class MetaData
			# class of object that includes this field
			attr_reader :klass  
			# table name that includes this field
			attr_reader :table_name
			# field name in table
			attr_reader :field_name
			# field type (standard field types plus :belongs_to, has_many, :has_and_belongs_to_many, :has_one)
			attr_reader :field_type
			# the controller used to display this relationship field
			attr_reader :controller
			# true if field is read_only
			attr_reader :read_only
			# the default value for the field
			attr_reader :defaults_to

			# the primary key assoicated with a belongs_to relationship
			attr_accessor :primary_key_name
			# the display name for this field
			attr_accessor :display_name
			# options hash passed to control that implements this field
			attr_accessor :view_options
			# interface hash passed to stores that sync with this object
			attr_accessor :interfaces
			# partial used to display this member
			attr_accessor :display_partial
			# partial used to edit this member
			attr_accessor :edit_partial
			# if the field is calculated or derived
			attr_accessor :is_virtual

			# this is true if this is declared field from a has_field, has_many, etc
			attr_reader :is_declared

			DB_TYPE_TO_BUILT_IN_TYPE = {
				:string => "String",
				:text => "String",
				:integer => "Integer",
				:float => "Float",
				:boolean => "Integer"
			}
			
			def initialize(klass, field_name, values)
				#options={}, field_type=nil, choices=[], controller=nil, read_only=nil, display_name=nil, field_class_name=nil, display_partial=nil, edit_partial=nil) #:nodoc:
				
				@klass = klass
				@table_name = klass.to_s.tableize
				@field_name = field_name
				@values = values
				
				@view_options = values[:view_options] || values[:options] || {}
				@interfaces = values[:interfaces]
				@from_s = values[:from_s]
				@display_name = values[:display_name]  || field_name.gsub(/_/, " ").capitalize
				@field_type = values[:field_type] || values[:type] || @view_options[:type] || klass.content_columns.find {|x| x.name == field_name}.send("type")
#puts "caller = " + caller[0..20].join("\n")
				@field_class_name = values[:field_class_name] || DB_TYPE_TO_BUILT_IN_TYPE[@field_type]
				$TRACE.debug 5, "MetaData::initialize(#{klass}, #{field_name}): #{@field_type.inspect}, #{@field_class_name.inspect}, values=#{values.inspect}, options=#{options.inspect}"
				
				field_type = values[:field_type] || values[:type]
				@column = klass.content_columns.find {|x| x.name == field_name}
#				puts "field_name = #{field_name} field_type= #{field_type.inspect} @column = #{@column.inspect}"
#				puts caller.join("\n")
				@field_type = field_type ? field_type.to_sym : @column.type
				@control_type = values[:control_type] || @field_type
				
				@choices = values[:choices] || []
				@controller = values[:controller]
			 	@read_only = values[:read_only] || values[:is_virtual]
			 	@display_partial = values[:display_partial]
			 	@edit_partial = values[:edit_partial]
				@defaults_to = values[:defaults_to]

				@is_declared = values[:is_declared]

			 	@primary_key_name = nil
			end

			#
			def options
				return view_options
			end

			def ==(other)
				return false unless other.kind_of?(MetaData)

				return self.field_name == other.field_name
			end

			def to_s
				"[#{@field_name}: #{@field_type}]"
			end

			def from_s
				return @from_s if @from_s

				Proc.new { |member, str_value, object| field_class.from_s(str_value)}
			end
			
			#
			# duplicate this metadata
			#
			def dup
				MetaData.new(@klass, @field_name, @values)
				#Marshal.load(Marshal.dump(self))
			end
			
			#
			# the class of a relationship field
			#
			def field_class
				Object.const_get(@field_class_name)
			end

			def label_for
				@field_name
			end

			def sub_description
				""
			end
			#
			# the table name of a relationship field
			#
			def field_class_table
				@field_class_name.tableize
			end

			def label_for
				@field_name
			end

			def sub_description
				""
			end
			
			#
			# the control type that will be used for this field. This includes many legitimate ones like text_area, check_box, etc and
			# new ones that are used inside of the built in metacrud views to handle relationships like select_many_control and
			# select_one_control.
			#
			def control_type(context=:display)
				# if a partial is set, then 
				case context
				when :display
					return "partial" if @display_partial
				when :edit
					return "partial" if @edit_partial
				end
				
				val = case @control_type
				when :text      : 					"text_area"
				when :password  : 					"password_control"
				when :hidden    : 					"hidden_control"
				when :file      : 					"file_control"
				when :check     : 					"check_box"
				when :checkbox  : 					"check_box"
				when :radio     : 					"radio_button"
				when :date      : 					"date_select"
				when :timestamp : 					"select_time"
				when :datetime  :						"datetime_select"
				when :time      :						"time_select"
				when :select    : 					"select"
				when :has_many	 : 					"select_many_control"
				when :belongs_to : 					"select_one_control"
				when :has_and_belongs_to_many:	"select_many_control"
				when :has_one	 : 					"select_one_control"
				else            						"text_field"
				end

				#@klass.logger.info "@field_type = #{@field_type.inspect}, val = #{val.inspect}"
				val
			end

			#
			# return an array of strings that represent the choices for this field. The passed in object is the object
			# to which the field belongs. This in turn is passed on to a choices proc if one is defined for this field.
			#
			def choices(obj=nil)
				if @choices.respond_to?(:call) then
					@choices.call(obj)
				else
					@choices
				end
			end

			#
			# This builds a two element array that can be passed to options_for_select as the second argument to select_tag.
			# The first element of the array is hash that links the display text to the object's database id. The second element
			# of the array is the database id of the currently selected object or -1 if none is selected.
			#
			# The passed in object is the object to which the field belongs. This is passed on to the #choices call.
			#
			def belongs_to_select_args(obj)
				@klass.logger.info "belongs_to_select_args, obj = #{obj.inspect}, @choices = #{@choices.inspect}"
				@klass.logger.info "obj.send(#{@field_name.inspect}) = #{obj.send(@field_name).inspect}"
				#hash = {}
				#choices(obj).each{|x| hash[x.respond_to?(:editlink) ? x.editlink(obj): x.id] = x.id}
				hash = []
				choices(obj).each{|x| hash.push([x.respond_to?(:editlink) ? x.editlink(obj): x.id, x.id])}
				hash = hash.sort_by{|x|x[0]}
				hash.insert(0, ["", -1])
				
				if obj.send(@field_name) then
					ret = [hash, obj.send(@field_name).id]
				else
					#hash[""] = -1
					ret = [hash, -1]
				end
				@klass.logger.info "ret = #{ret.inspect}"
				ret
			end
			
			#
			# This builds a two element array that can be passed to options_for_select as the second argument to select_tag.
			# The first element of the array is hash that links the display text to the object's database id. The second element
			# of the array an array of database id's of the currently selected objects or [] if none are selected.
			#
			# The passed in object is the object to which the field belongs.
			#
			def has_many_select_args(obj)
				hash = {}
				choices(obj).each{|x| hash[x.respond_to?(:editlink) ? x.editlink(obj) : x.id] = x.id}
				[hash, obj.send(@field_name).map{|x| x.id}]
		  		#[@choices.map{|x| [x.editlink, x.id]}, @klass.find_all.map{|x| x.editlink}]
			end
		end # class MetaData

		#
		# This class is used to modify a database to have the tables and fields necessary to support what is declared in the
		# models that include acts_with_metadata
		#
		# You use it by doing:
		#
		# 	ActiveRecord::Acts::WithMetaData::Loader.new(filename)
		#
		class Loader
			include Singleton
			#
			# This will attempt to load a model file and generate any tables and fields necessary to support what is declared in the
			# model.
			#
			def initialize
				@migration_num = 1
			end

			#
			# this loads up ruby files in @directory and creates migrations necessary to allow the files to load
			#
			# new_class_procs - are procedures that either modify a new table migration being created or add in additional tables when a new
			#                table is being created.  They should take two arguments (action, table_name), where action is either:
			#                :define_additional_fields - this should return a string of the form: 't.column yada yada; t.column yada ' for as 
			#                                      many columns as are necessary to add
			#                :define_additional_tables - this should return a string of the form: 'create_table yada yada; yada yada; end'
			#
			def handle_exception(e, new_class_procs)
				if e.class == ActiveRecord::Acts::WithMetaData::TableNotFoundError then					
					$TRACE.debug 5, "Table not found '#{e.table_name}'"
					$TRACE.debug 9, "backtrace = " + e.backtrace.join("\n")
					migration_class_name = "C_#{e.table_name}_#{@migration_num}"
					add_table_migration = 	"class #{migration_class_name} < Silent_Migration;" 
					add_table_migration <<= 	"def self.up;"
					add_table_migration <<= 		"create_table('#{e.table_name}') do |t|"
					add_table_migration <<=				"t.column 'version', :integer;"
					add_table_migration <<=				"t.column 'created_at', :datetime;"
					new_class_procs.each do |new_class_proc|
						add_table_migration <<=			"#{new_class_proc.call(:add_additional_fields, e.table_name)};"
					end
					add_table_migration <<=			"end;"
					new_class_procs.each do |new_class_proc|
						add_table_migration <<=		"#{new_class_proc.call(:add_additional_tables, e.table_name)};"
					end
					add_table_migration <<=		"end;"
					add_table_migration <<=	"end;"
					loader_eval add_table_migration
					loader_eval "#{migration_class_name}.migrate(:up)"
					
					@migration_num += 1
					return true
					
				elsif e.class == ActiveRecord::Acts::WithMetaData::FieldNotFoundError then
					$TRACE.debug 5, "Field '#{e.field_name}' of type #{e.field_type}' not found in '#{e.table_name}'"
					$TRACE.debug 9, "backtrace = " + e.backtrace.join("\n")
					
					field_type = (e.field_type) ? e.field_type : :string
					migration_class_name = "C_#{e.table_name}_#{@migration_num}"
					
					loader_eval "class #{migration_class_name} < Silent_Migration; def self.up; add_column '#{e.table_name}', '#{e.field_name}', :#{field_type}; end; end" 
					loader_eval "#{migration_class_name}.migrate(:up)"
					
					@migration_num += 1
					return field_type
					
				else
					return false
				end
			end

			# 
			# This evaluates the code to create a migration and outputs debug info
			#
			def loader_eval(str) #:nodoc:
				$TRACE.debug 5, "active record eval = '#{str}'"
				Object.instance_eval(str)
			end		
		end
   end # module WithMetaData
	end # module Acts
end

ActiveRecord::Base.class_eval { include ActiveRecord::Acts::WithMetaData }

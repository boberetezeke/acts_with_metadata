module ActionController
	class Base
		#
		# 
		# acts_as_metadata_crud_controller
		# 
		# Basic Usage:
		#
		# class WidgetController < ActionController::Base
		#   acts_as_metadata_crud_controller  Widget
		# end
		#
		# Extended Usage (modifications of basic functionality
		#
		# Its functionality can be extended by overriding the standard actions
		# that it provides (show, edit, list, destroy, new). It takes information
		# that is specified in the model (with acts_with_metadata) and uses it to 
		# do its standard views. You can modify that information by creating a
		# @model_params hash that will override information specified in the model.
		# 
		# Below the members displayed and their order is specified
		#
		# def show
		#   @model_params[:members_to_display] = [:number, :make, :model]
		#   super
		# end
		#
		# You can also not have the standard view displayed for an action but still
		# use the model_params information in your own view
		#
		# def list
		#   @model_params[:list_order_str] = "number"
		#   super(false)  # don't allow super class to render 
		#   # use the standard controller/list.rhtml
		# end
		# 
		# Lastly you can generate the parameters for the shared view, modify them and
		# then render the shared view
		# 
		# def show
		#   super(false) # get everything ready for display but don't render it
		#   # modify model_params
		#   @model_params[:members]["body"].display_partial = "body"
		#   @model_params[:members]["attachment"].display_partial = "attachment"
		#   # render the shared view
		#   render("metacrud/show")
		# end
		# 
		# If you have your own action name and want to use the standard views, you can
		# call them but with a leading underscore
		#
		# def list_subjects_by_most_recent
		#   @model_params[:members_to_display] = [:date, :subject]
		#   @model_params[:list_order_str] = "id DESC"
		#   @model_params[:list_limit] = 50
		#   _list
		# end
		#
		# Model Params listing and correspondence to acts_with_metadata keywords
		#
		# | @model_params value                     | acts_with_metadata declaration            |
		# | :list_limit => 20                       | list_limit 20                             |
		# | :page_limit => 20                       | page_limit 20                             |
		# | :list_filtering => true                 | list_filtering true                       |
		# | :list_order_str => "name"               | list_order_str "name"                     |
		# | :members_to_display => [:name, phone]   | this is implicitly derived from has_field |
		# | :members_to_change => {:name => {:attr => value} | this is used to change the attribute for one member |
		# 
		# | @model_params[:members_to_change][:member] | acts_with_metadata declaration options                          |
		# | :display_partial => "shared/dtime.rhtml"   | has_field :start_time, :display_partial => "shared/dtime.rhtml" |
		# | :edit_partial => "shared/etime.rhtml"      | has_field :start_time, :edit_partial => "shared/dtime.rhtml"    |
		#
		# def list
		#   @model_params[:list_limit] = nil
		#   @model_params[:page_limit] = 20
		#   @model_params[:list_filtering] = true
		#   @model_params[:list_order_str] = "number"
		#   @model_params[:members_to_display] = [:number, :make, :model]
		#
		#   super(false)  # get everything ready for display but don't render it
		#
		#   filter_objects # do further processing on objects listed
		#
		#   # rendering is done by controller/list.rhtml
		# end
		#
		class << self
			def acts_as_metadata_crud_controller(model)
				include ActsAsMetaDataCRUDController
$TRACE.debug 5, "acts_as_metadata_crud_controller: self = #{self.class} model = #{model}"
				acts_as_metadata_crud_controller2(model)

				if self.respond_to? :active_scaffold then
					active_scaffold(model.to_s.tableize.singularize) do |config|
						all_members = crud_model.members
						config.columns = all_members.map{|x| x.field_name}
						edit_members = all_members.select{|x| x.field_type != :has_many && x.field_type != :has_and_belongs_to_many && x.field_name.to_s != "parent"}
						config.create.columns = edit_members.map{|x| x.field_name}
						config.update.columns = edit_members.map{|x| x.field_name}
						yield config if block_given?
					end
				end
			end
		end
			
		module ActsAsMetaDataCRUDController
		   def self.included(base) # :nodoc:
		   	base.extend ClassMethods
		   end

		   module ClassMethods
		   	attr_reader :crud_model
		   	
				def acts_as_metadata_crud_controller2(model)
					module_to_include = ::ActionController::Base::ActsAsMetaDataCRUDController::ActMethods
		      	# don't allow multiple calls
					#return if self.included_modules.include?(module_to_include)

					class_eval do
						include module_to_include
						@crud_model = model
					end
				end
		   end

			DEFAULT_MODEL_PARAMS = {
				:html_converter => proc{|exec_env, __x|
					__text = ""
					if __x && /<%/.match(__x) then
						begin
							__text = ERB.new(__x).result(exec_env)
						rescue Exception => e
							__text = "ERROR: #{e.message}\n" + 
							if m = /\(erb\):(\d+)/.match(e.backtrace.first) then
								error_line = m[1].to_i - 1
								__text += "on line *#{error_line}*\n\n"
								error_first = error_line - 2
								error_line = 0 if error_first < 0
								error_last = error_line + 2
								__x_lines = __x.split(/\n/)
								error_last = __x_lines.size - 1 if error_last > __x_lines.size - 1
								index = error_first
								__text += __x.split(/\n/)[error_first..error_last].map{|__y| __z = "*#{index}*: #{__y}"; index += 1; __z}.join("\n")
							else
								__text += e.backtrace.join("\n")
							end
						end
					else
						__text = __x if __x
					end
					RedCloth.new(__text).to_html.gsub(/<table>/, "<table class=\"textile-table\">")
				}
			}
			
		   module ActMethods
		   	attr_reader :model_params
		   	
		   	def initialize
		   		@model_params = DEFAULT_MODEL_PARAMS.dup
		   		super
		   	end
		   	
				def index
					list
				end

			 	def crud_model
			 		@crud_model = self.class.crud_model
					@crud_model
			 	end

			 	def title
			 		crud_model.display_name
			 	end

				def generate_params(model_klass, model_params = {}, object = nil, action = :show)
				$TRACE.debug 5, "generate_params: #{model_klass}"
				$TRACE.debug 5, "generate_perams: #{model_klass.params.inspect}"
					# merge in params set by individual controllers
					model_params = model_klass.params.merge(model_params)

					# select the object
					# FIXME: this should be for acts_as_database_object_crud_controller.rb
					#model_params[:members] = model_klass.members.dup
					model_params[:members] = model_klass.members(true).dup

					$TRACE.debug 5, "generate_params: #{model_klass}:" 
					$TRACE.debug 5, "generate_params(model_klass.members): #{model_klass.members.map{|m| m.field_name+'::'+m.options.inspect}.inspect}"
					$TRACE.debug 5, "generate_params(model_params[:members]): #{model_params[:members].map{|m| m.field_name+'::'+m.options.inspect}.inspect}"
					$TRACE.debug 5, "generate_params(model_params[:members_to_display]): #{model_params[:members_to_display].inspect}"

					members_to_display = nil
					if model_params.has_key?(:members_to_display) then
						members_to_display = model_params[:members_to_display]
					else
						case action
						when :show
							members_to_display = model_params[:show_members]
						when :edit
							members_to_display = model_params[:edit_members]
						when :list
							members_to_display = model_params[:list_members]
							$TRACE.debug 5, "generate_params(model_params[:list_members]): #{model_params[:list_members].inspect}"
						end
					end
					
					# select and order the members based on list of symbols in :members_to_display if its defined
					model_params[:members].select_and_order_members(members_to_display) if members_to_display

					$TRACE.debug 5, "generate_params(model_params[:members]): #{model_params[:members].map{|m| m.field_name}.inspect}"

					# modify any members that the user wants changed
					if model_params.has_key?(:members_to_change) then
						model_params[:members_to_change].each do |member_name, changes|
							changes.each do |attr, val|
								model_params[:members][member_name].send("#{attr}=", val)
							end
						end
					end

					unless model_params[:title]
						model_params[:title] = case action
							when :show
								#model_klass.display_name + ": " + ("showing %s" % [object.editlink(object)])
								object.editlink(object)
							when :edit
								model_klass.to_s.tableize.capitalize.singularize + ": " + ("editing %s" % [object.editlink(object)])
							when :list
								model_klass.display_name.pluralize.capitalize
							when :new
								"Enter new #{model_klass.to_s.tableize.singularize.gsub(/_/, ' ')}"
						end
					end
					
					$TRACE.debug 5, "generate_params(model_params - at end): #{model_params[:members].map{|m| m.field_name+'::'+m.options.inspect}.inspect}"

					model_params
				end

				def order_by(str)
					@model_params[:list_order_str] = str
				end

				def members_to_display(*args)
					if args.first.kind_of?(Array) then
						@model_params[:members_to_display] = args.first
					else
						@model_params[:members_to_display] = args
					end
				end

				def list_limit(limit)
					@model_params[:list_limit] = limit
				end

				def list_actions(*actions)
					if actions.kind_of? Array then
						@model_params[:list_actions] = actions
					else
						@model_params[:list_actions] = [actions]
					end
				end

				def list_tags
					@model_params[:list_tags] = true
				end
				
				def _new(render=true)
					@new = crud_model.new
					@model_params = generate_params(crud_model, @model_params, @new, :new)
					render(:template => "metacrud/new") if render
				end				
				
				def new(render=true)
					_new(render)
				end

				def _list(render=true)
					m = @model_params = generate_params(crud_model, @model_params, nil, :list)
					@count = crud_model.count(m[:list_find_spec], :conditions => m[:list_conditions])
					# if there is no list limit, then ignore pagination
					if m[:list_filtering] then
						offset = 1
					else
						m[:list_pages] = ActionController::Pagination::Paginator.new self, @count, m[:list_limit], params[:page]
						offset = m[:list_pages].current.offset
					end
					@list = crud_model.find(m[:list_find_spec], :conditions => m[:list_conditions], :order => m[:list_order_str], :offset => offset, :limit => m[:list_limit])
					$TRACE.debug 5, "list find spec = '#{m[:list_find_spec]}', list_conditions = '#{m[:list_conditions]}', list order = '#{m[:list_order_str]}' limit = #{m[:list_limit]}"
					render(:template => "metacrud/list") if render
				end
				
				def list(render=true)
					_list(render)
				end

				def _edit(render=true)
					@edit = crud_model.find(params[:id])
					@edit.class.members.each do |m| 
						if m.field_type == :text then
							value = @edit.send(m.field_name)
#$TRACE.debug 0, "AAMCC: field = #{m.field_name}, value = #{value.inspect}"
						end
					end
#$TRACE.debug 0, "AAMCC: @edit.fieldname.inspect = #{@edit.fieldname.inspect}"
#$TRACE.debug 0, "AAMCC: @edit.fieldname.to_s = #{@edit.fieldname.to_s}"
#$TRACE.debug 0, "AAMCC: @edit.fieldname.to_str = #{@edit.fieldname.to_str}"
					@model_params = generate_params(crud_model, @model_params, @edit, :edit)
					render(:template => "metacrud/edit") if render
				end
				
				def edit(render=true)
					$TRACE.debug 5, "@model_params = #{@model_params.inspect}"
					_edit(render)
				end
				
				def _show(render=true)
					@object = crud_model.find(params["id"])
					$TRACE.debug 5, "@model_params(_show,1) = #{@model_params.inspect}"
					@model_params = generate_params(crud_model, @model_params, @object, :show)
					$TRACE.debug 5, "@model_params(_show,2) = #{@model_params.inspect}"
$TRACE.debug 0, "show params = #{params.inspect}"
					if render then
						if self.respond_to?(:show_render)
							show_render 
						else
							if render then
								if params["layout"] == "none" then
									render(:template => "metacrud/show", :layout => false)
								else
									render(:template => "metacrud/show")
								end
							end
						end
					end
				end

				def show(render=true)
					_show(render)
				end


				# def new
					#if session[:back] then
					#	session[:back_stack] ||= []
					#	session[:back_stack].push(session[:back])
					#	session[:back] = nil
					#end
				#

				def new_stack
					#session[:back] ||= []
					#session[:back].push({:controller => , :action => })
					
					@object = crud_model.new
					render(:template => "metacrud/new")
				end

			 	def handle_relationship_fields(params, obj)
			 		logger.info "obj = #{obj.inspect}"
			 		logger.info "relations = #{crud_model.reflections.inspect}"
					crud_model.members.each do |member|
						logger.info "crud_model = #{crud_model} member.field_name = #{member.field_name}, member.control_type = #{member.control_type(:edit).inspect}"
						if ["select_many_control", "select_one_control"].include?(member.control_type(:edit)) then
							relationship_class = crud_model.reflect_on_association(member.field_name.to_sym).klass
						end
						logger.info "relationship_class = #{relationship_class}"
						if member.control_type(:edit) == "select_many_control" then
							new_link_ids = params[member.field_name]
							if new_link_ids then
								logger.info "has_many: values = #{new_link_ids.inspect}"
								logger.info "attributes = #{@object.attributes.inspect}"
								#logger.info "crud_model = #{crud_model.to_s} branches = #{crud_model.reflect_on_association(:branches).klass}"

								current_links = @object.send(member.field_name)
								current_link_ids = current_links.map{|x| x.id}
								if new_link_ids && new_link_ids.size > 0 then
									logger.info "links = #{current_link_ids.inspect}"

									new_links = new_link_ids.map{|id| relationship_class.find(id)}
									logger.info "new_links = #{new_links.inspect}"
									obj.send(member.field_name+"=", new_links)
								else
									obj.send(member.field_name+"=", [])
								end				
								params.delete(member.field_name)
							end

						elsif member.control_type(:edit) == "select_one_control"
							new_link_id = params["edit"][member.field_name]
							if new_link_id then
								logger.info "belongs_to: values = #{new_link_id.inspect}"
								if new_link_id.to_i != -1 then
									obj.send(member.field_name+"=", relationship_class.find(new_link_id))
								end
								params[:edit].delete(member.field_name)
							end
						end
					end
			 	end

			 	def handle_text_fields(params, object)
					object.class.members.each do |member|
$TRACE.debug 0, "checking member #{member.field_name} which is of type: #{member.field_type.inspect}"
$TRACE.debug 0, "params = #{params.inspect}"
$TRACE.debug 0, "check 1 = #{member.field_type == :text } check 2 = #{params.has_key?(member.field_name)}"
						if member.field_type == :text && params.has_key?(member.field_name) then
$TRACE.debug 0, "setting member to big string"
							object.send("#{member.field_name}=", BigString.new(params[member.field_name].gsub(/\r/, "")))
$TRACE.debug 0, "params before = #{params.inspect}"
							params.delete(member.field_name)
$TRACE.debug 0, "params after = #{params.inspect}"
						end
					end
			 	end

				def handle_datetime_fields(params, object)
$TRACE.debug 0, "handle_datetime_fields: params = #{params.inspect}"
					object.class.members.each do |member|
$TRACE.debug 0, "handle_datetime_fields: member = #{member.field_name}, #{member.field_type.inspect}"
						if [:datetime, :time, :date].include?(member.field_type) then
$TRACE.debug 0, "handle_datetime_fields: got datetime"
							dt_keys = params.keys.select{|key| /^#{member.field_name}/.match(key)}
$TRACE.debug 0, "handle_datetime_fields: dtkeys = #{dt_keys.inspect}"
dt_keys.each {|dtkey| $TRACE.debug 0, "#{dtkey} = '#{params[dtkey]}'"}
							dt_check_box_key = "#{member.field_name}(nil)"
							if params[dt_check_box_key] then
$TRACE.debug 0, "handle_datetime_fields: clearing field #{member.field_name}"
								object.send("#{member.field_name}=", nil)
								dt_keys.each {|dt_key| params.delete(dt_key)}
=begin
							else
								case member.field_type
								when :datetime
									year, month, day, hour, min = dt_keys.sort.map{|x| params[x].to_i}
									value = Time.new(year, month, day, hour, min)
								when :date
									year, month, day = dt_keys.sort.map{|x| params[x].to_i}
									value = Time.new(year, month, day)
								when :time
									hour, min = dt_keys.sort.map{|x| params[x].to_i}
									value = Time.new()
								end
								object.send("#{member.field_name}=", )
=end
							end
						end
					end
				end

				def handle_non_text_fields(params, object)
					object.class.members.each do |member|
						if params[member.field_name] then
							case member.field_type
							when :float
								params[member.field_name] = params[member.field_name].to_f
							when :integer
								params[member.field_name] = params[member.field_name].to_i
							end
						end
					end
				end

				def _create(render=true)
					before_create if self.respond_to?(:before_create)
					
					$TRACE.debug 5, "create: before new object of type #{crud_model}"
					@object = crud_model.new
					handle_relationship_fields(params, @object)
					handle_text_fields(params[:edit], @object)
					handle_datetime_fields(params[:edit], @object)
					handle_non_text_fields(params[:edit], @object)

					puts params[:edit].inspect

					if @object.update_attributes(params[:edit])
						$TRACE.debug 5, "create: before save object of type #{@object.class}"
						@object.save
						$TRACE.debug 5, "create: after save object of type #{@object.class}"
						after_create if self.respond_to?(:after_create)

						if render then
							flash[:notice] = sprintf("added %s", @object.editlink(@object))
							redirect_to :action => 'show', :id => @object
						end
					else
						render(:template => "metacrud/new") if render
					end
				end

				def create(render=true)
					_create(render)
				end
			 
				def _update(render=true)
$TRACE.debug 0, "acts_as_metadata_crud_controller#update, params = #{params.inspect}"
					@object = crud_model.find(params[:id])
					handle_relationship_fields(params, @object)
					logger.info "before update_attributes obj = #{@object.inspect}, params[:edit] = #{params[:edit].inspect}"

					handle_text_fields(params[:edit], @object)
					handle_datetime_fields(params[:edit], @object)
					handle_non_text_fields(params[:edit], @object)

					ret = @object.update_attributes(params[:edit])
					logger.info "after update_attributes ret = #{ret} obj = #{@object.inspect}"
					if (ret)
						@object.save
						if render then
						flash[:notice] = sprintf("updated %s", @object.editlink(@object))
			#			if session[:back_stack] && session[:back_stack].size > 0 then
			#				back_info = session[:back_stack].pop
			#				redirect_to :controller => back_info[:controller], :action => back_info[:action], :id => back_info[:id]
			#			else
						if params["save_and_continue"] then
							redirect_to :action => 'edit', :id => @object
						else
							redirect_to :action => 'show', :id => @object
						end
			#			end
						end
					else
						render(:template => "metacrud/edit") if render
					end
				end

			 	def update(render=true)
			 		_update(render)
			 	end
			 	
				def _destroy
					obj = crud_model.find(params[:id])
					flash[:notice] = sprintf("deleted %s", obj.editlink(obj))
					obj.destroy
					redirect_to :action => 'list'
				end

				def destroy
					_destroy
				end
		   end
		end
	end	
end


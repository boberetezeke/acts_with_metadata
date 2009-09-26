module ActsWithMetaDataHelper
	def relationship_link_to(context_obj, value, action = "show")
		if value then
			$TRACE.debug 5, "-- relationship_link_to: for #{value.class_name}:#{value.object_id}  --"
			#@klass.logger.info "relationship_link_to: #{value.editlink.inspect}, #{value.id.inspect}, #{@controller.inspect}"
			begin
				r = link_to(display_link(context_obj, value), {:controller => value.class_name.underscore.singularize, :action => action, :id => value.database_id})
			rescue Exception => e
				r = "Exception: #{e.message}"
			end
			#view.link_to(value.display_link(view), {:controller => @controller ? @controller : value.class.to_s.underscore.singularize, :action => "show", :id => value.id})
			$TRACE.debug 5, "-- relationship_link_to --"
			r
		else
			"(no value)"
		end
	end

	def display_link(context_object, value)
		$TRACE.debug 5, "-- display_link: for #{value.class}:#{value.object_id}  --"
		if value.respond_to? :editlink then
			r = h(value.editlink(context_object))
		else
			r = value.id.to_s
		end
		$TRACE.debug 5, "-- display_link --"
		#h("bob")
		r
	end

	def display_value(obj, meta_data, max_lines=nil, html_converter=nil)
		$TRACE.debug 5, "-- display_value: for #{obj.class}, field #{meta_data.field_name}, class #{meta_data.klass}, control_type #{meta_data.control_type(:display)}--"
		#@klass.logger.info "object: #{obj.class}"
		#if meta_data.control_type == "select_many_control" then # && meta_data.field_name == "mail_messages" then
		#	one_class_table_id = obj.class.to_s.tableize.singularize + "_id"
		#	many_class_table = meta_data.field_class_table
		#	link_fields = meta_data.field_class.editlink_fields.join(",")
		#	value = meta_data.field_class.find_by_sql("SELECT #{link_fields} FROM #{many_class_table} WHERE (#{many_class_table}.#{one_class_table_id} = #{obj.id})")
		#else
			value = obj.send(meta_data.field_name)
		#end
		dvalue = case meta_data.control_type(:display)
		when "partial"
			render(:partial => meta_data.display_partial, :object => obj, :locals => {:meta_data => meta_data})
		when "password_control"				:	value.gsub(/./, "*")
		when "check_box"	 					:	value ? "true" : "false"
		when "select_many_control"			:  
			if max_lines && value.size > max_lines-1 then
		  		value[0..max_lines-1].map{|x| relationship_link_to(obj, x)}.join(", ") + "<p>continued...</p>"
			else
		  		value.map{|x| relationship_link_to(obj, x)}.join(", ")
		  	end
		when "select_one_control"			:	(value ? relationship_link_to(obj, value) : "")
#		when "datetime_select"
#			obj.send(meta_data.field_name).localtime.strftime("%m/%d/%Y %H:%M:%S")
#		when "date_select"
#			obj.send(meta_data.field_name).localtime.strftime("%m/%d/%Y")
#		when "time_select"
#			obj.send(meta_data.field_name).localtime.strftime("%I:%M %p").downcase
		when "text_area"
			#$TRACE.debug 5, "value = #{value.inspect}"
			#value = value.gsub(/\r\n/, "\\r\\n") 
			#$TRACE.debug 5, "value2 = #{value.inspect}"
			if html_converter then
				value = html_converter.call(binding, value)
			else
				value = h(value)
				#$TRACE.debug 5, "value3 = #{value.inspect}"
				value_lines = value.split(/\n/)
				if max_lines && value_lines.size > max_lines then
					value = value_lines[0..max_lines].join("<br>") + "<p>continued...</p>"
				else
					value = value_lines.join("<br>")
				end
			end
			#$TRACE.debug 5, "value4 = #{value.inspect}"
			value
		else            						h(value)
		end
		#@klass.logger.info "field: #{meta_data.field_name}, display value: #{dvalue}"

		$TRACE.debug 5, "-- display_value: ----"
		dvalue
	end

	def edit_value(object, meta_data)
		case meta_data.control_type(:edit)
		when "partial"
			return	render(	:partial => meta_data.edit_partial, 
									:object => object,
									:locals => {:meta_data => meta_data})
		when "select_many_control"
			return 	select_tag("#{meta_data.field_name}[]", options_for_select(*(meta_data.has_many_select_args(object))), meta_data.options.merge({:multiple => "true"})) +
						link_to("add new #{meta_data.field_name}", { :controller => meta_data.controller, :action => "new"}, {:target=>"_new"})
		when 	"select_one_control"
			return 	select_tag("edit[#{meta_data.field_name}]", options_for_select(*(meta_data.belongs_to_select_args(object))), meta_data.options) +
#			return 	select_tag("edit[#{meta_data.field_name}]", options_for_select([["", 0], ["Bob", 1], ["Fred", 2], ["Joe", 3], ["Pete", 4]], 0), meta_data.options) +
						link_to("add new #{meta_data.field_name}", { :controller => meta_data.controller, :action => "new"}, {:target=>"_new"})
		when "select"
			choices = meta_data.choices(object).map{|x| x.to_s}
			value = object.send(meta_data.field_name)
			return	select_tag("edit[#{meta_data.field_name}]", 
							options_for_select(choices, value), meta_data.options)	#.merge({:name => "edit[#{meta_data.field_name}]"})
		when "check_box"
			return	check_box("edit", meta_data.field_name, meta_data.options, "true", "false")
		#when "time_select"
		#	time = object.send(meta_data.field_name)
		#	return	"Clear Time" +
		when "datetime_select"
			datetime = object.send(meta_data.field_name)
			return 	"Clear Time" + 
						check_box_tag("edit[#{meta_data.field_name}(nil)]", "1", datetime == nil, meta_data.options) + 
						datetime_select("edit", meta_data.field_name, meta_data.options)
		when "date_select"
			date = object.send(meta_data.field_name)
			return   "Clear Time" + 
						check_box_tag("edit[#{meta_data.field_name}(nil)]", "1", date == nil, meta_data.options) + 
						date_select("edit", meta_data.field_name, meta_data.options)
		when "time_select"
			time = object.send(meta_data.field_name)
			return 	"Clear Time" + 
						check_box_tag("edit[#{meta_data.field_name}(nil)]", "1", time == nil, meta_data.options) + 
						time_select("edit", meta_data.field_name, meta_data.options)
		when "text_area"
			text_area("edit", meta_data.field_name, {:cols => 80}.merge(meta_data.options))
		else
			return	send(meta_data.control_type, "edit", meta_data.field_name, meta_data.options)
		end

=begin		
		<% if member.control_type == "select_many_control" %>
			<%= select_tag("#{member.field_name}[]", options_for_select(*(member.has_many_select_args(self, object))), member.options.merge({:multiple => "true"})) %>
			<%= link_to "add new #{member.field_name}", { :controller => member.controller, :action => "new"}, {:target=>"_new"} %>
		<% elsif member.control_type == "select_one_control" %>
			<%= select_tag("edit[#{member.field_name}]", options_for_select(*(member.belongs_to_select_args(self, object))), member.options) %>
			<%= link_to "add new #{member.field_name}", { :controller => member.controller, :action => "new"}, {:target=>"_new"} %>
		<% elsif member.control_type == "select" %>
			<%= select("edit", member.field_name, member.choices(object), member.options) %>
		<% elsif member.control_type == "radio_button" %>
			<%= radio_button("edit", member.field_name, object.send(member.field_name), member.options) %>
		<% elsif member.control_type == "check_box" %>
			<%= check_box("edit", member.field_name, member.options, "true", "false") %>
		<% else %>
			<%= send(member.control_type, "edit", member.field_name, member.options) %>
		<% end %>
=end
	end
=begin				
	def subdesc
		key = "#{@tablename}_#{@field_name}_subdesc".to_sym
		if _(key)
			"<div class=\"subdesc\">" + _(key) + "</div>"
		else
			""
		end
	end
	def belongs_to_select_args(obj, meta_data)
		#@klass.logger.info "belongs_to_select_args, obj = #{obj.inspect}, @choices = #{@choices.inspect}"
		#@klass.logger.info "obj.send(#{@field_name.inspect}) = #{obj.send(@field_name).inspect}"
		hash = {}
		meta_data.choices(obj).each{|x| hash[x.display_link(obj)] = x.id}
		if obj.send(meta_data.field_name) then
			ret = [hash, obj.send(meta_data.field_name).id]
		else
			hash[""] = -1
			ret = [hash, -1]
		end
		#@klass.logger.info "ret = #{ret.inspect}"
		ret
	end
	
	def has_many_select_args(view, obj)
		hash = {}
		choices(obj).each{|x| hash[x.display_link(obj)] = x.id}
		[hash, obj.send(meta_data.field_name).map{|x| x.id}]
  		#[@choices.map{|x| [x.editlink, x.id]}, @klass.find_all.map{|x| x.editlink}]
	end
=end	 
end

require 'digest/sha2'
require	'tempfile'
require	'kconv'
require	'fileutils'
require 'base64'

module WikiMscgenHelper

	ALLOWED_FORMAT = {
		"png" => { :type => "png", :ext => ".png", :content_type => "image/png" },
		"jpg" => { :type => "jpg", :ext => ".jpg", :content_type => "image/jpeg" },
		"svg" => { 
			:type => "svg", :ext => ".svg", :content_type => "image/svg+xml" ,
			:inline => true,
		},
	}.freeze

	def	render_graph(params, dot_text, options = {})
		fmt = decide_format(params[:format])

		name = "wiki_mscgen_plugin." + Digest::SHA256.hexdigest( {
			:format => params[:format],
			:dot_text => dot_text,
		}.to_s)
		cache_seconds = Setting.plugin_wiki_mscgen_plugin['cache_seconds'].to_i || 600
		result = Rails.cache.fetch(name, :raw => false, :expires_in => cache_seconds) do
			Rails.logger.info "[wiki_mscgen]not in cache: #{name}"
			self.render_graph_exactly(fmt, dot_text, options)
		end

		return result
	end


	def	make_macro_output_by_title(macro_params)
		wiki = @project.wiki
		if wiki.nil?
			raise "Wiki not found" 
		end
		page = wiki.find_page(macro_params[:title], :project => @project)
		if page.nil? || 
			!User.current.allowed_to?(:view_wiki_pages, page.wiki.project)
			raise "Page(#{macro_params[:title]}) not found" 
		end

		if	macro_params[:version] && !User.current.allowed_to?(:view_wiki_edits, @project)
			macro_params[:version] = nil
		end

		content = page.content_for_version(macro_params[:version])
		self.make_macro_output_by_text(content.text, macro_params, false)
	end

	def	make_macro_output_by_text(dottext, macro_params, using_data_scheme)
		graph = self.render_graph(macro_params, dottext)
		if !graph[:image]
			raise "page=#{macro_params[:title]}, error=#{graph[:message]}"
		end

		macro = {
			:params => macro_params,
			:graph => graph,
			:dottext => dottext,
			:map_index => @index_macro,
		}
		if !@project.nil?
			macro[:project_id] = @project.id
		end

		if using_data_scheme
			macro[:data_scheme] = "data:#{graph[:format][:content_type]};base64,#{Base64.encode64(graph[:image]).gsub(/\n/, '')}"
		end


		fmt = decide_format(macro_params[:format])
		inline_default = fmt[:inline]
		inline_allowed = !inline_default.nil?
		inline_opt = macro_params[:inline].to_s.downcase
		output_inline = inline_allowed && 
			!macro_params[:with_source] &&
			!(inline_opt != "" && inline_opt != "true" || 
				(inline_opt == "" && inline_default == false)) 
		if output_inline
			return render_to_string  :layout => false, 
				:template => "wiki_mscgen/inline_#{fmt[:type]}", 
				:locals => {:macro => macro}
		end


		render_to_string :layout => false, 
			:template => 'wiki_mscgen/macro', 
			:locals => {:macro => macro}
	end

	def	countup_macro_index
		if @index_macro
			@index_macro = @index_macro + 1
		else
			@index_macro = 0
		end
		@index_macro
	end

	def	render_graph_exactly(fmt, dot_text, options = {})

		dir = File.join([Rails.root, 'tmp', 'wiki_mscgen_plugin'])
		FileUtils.mkdir_p(dir);
		if !FileTest.writable?(dir) && !Redmine::Platform.mswin?
			FileUtils.chmod(0700, dir);
		end

		temps = {
			:img => Tempfile.open("graph", dir),
			:map => Tempfile.open("map", dir),
			:dot => Tempfile.open("dot", dir),
			:err => Tempfile.open("err", dir),
		}.each {|k, v|
			v.close
		}

		result = {}
		self.create_image_using_dot(fmt, dot_text, result, temps) 

		img = nil
		maps = []
		begin
			temps[:img].open
			# need for Windows.
			temps[:img].binmode
			img = temps[:img].read
			if img.size == 0
				img = nil
			end

			temps[:map].open
			temps[:map].each {|t|
				cols = t.split(/ /)
				if cols[0] == "base"
					next
				end

				shape = cols.shift
				url = cols.shift
				maps.push(:shape => shape, :url => url, :positions => cols)
			}
		ensure
			temps.each {|k, v|
				if v != nil 
					v.close(true)
				end
			}
		end

		result[:image] = img
		result[:maps] = maps
		result[:format] = fmt
		result
	end

	def	create_image_using_dot(fmt, dot_text, result, temps)
		Rails.logger.info("[wiki_mscgen]using mscgen")

		temps[:dot].open
		temps[:dot].write(dot_text)
		temps[:dot].close

		p = lambda {|mes|
			temps[:err].open
			t = temps[:err].read.to_s.strip
			t = t.toutf8
			result[:message] = t != "" ? t : mes
		}

		system("mscgen -T#{fmt[:type]} -i /dev/stdin -o /dev/stdout < \"#{temps[:dot].path}\" > \"#{temps[:img].path}\" 2>\"#{temps[:err].path}\"")
		if !$?.exited? || $?.exitstatus != 0
			Rails.logger.info("[wiki_mscgen]dot image: #{$?.inspect}")
			p.call("failed to execute mscgen when creating image.")
			return
		end

		system("mscgen -Tismaps -i /dev/stdin -o /dev/stdout < \"#{temps[:dot].path}\" > \"#{temps[:map].path}\" 2>\"#{temps[:err].path}\"")
		if !$?.exited? || $?.exitstatus != 0
			Rails.logger.info("[wiki_mscgen]dot map: #{$?.inspect}")
			p.call("failed to execute mscgen when creating map.")
			return
		end
	end


private 


	def	decide_format(fmt)
		fmt = ALLOWED_FORMAT[fmt.to_s.downcase]
		fmt ||= ALLOWED_FORMAT["png"]

		fmt
	end

	class Macro
		def	initialize(view, wiki_content)
			@content = wiki_content

			@view = view
			@view.controller.extend(WikiMscgenHelper)
			[@content, @view.controller].each {|e|
				if @project.nil? && e.respond_to?(:project)
					@project = e.project
				end
			}

			if @project.nil? 
				if @view.params[:controller] == 'projects'
					project_id_param = :id
				else
					project_id_param = :project_id
				end

				if !@view.params[project_id_param].nil?
					@project = Project.find(@view.params[project_id_param])
				end
			end
		end

		def	mscgen(args)
			begin
				if @project.nil?
					Rails.logger.info "[wiki_mscgen]project is not defined."
					return ""
				end

				title = args.pop.to_s
				if title == ""
					raise "With no argument, this macro needs wiki page name"
				end

				set_macro_params(args)
				macro_params = @macro_params.clone
				macro_params[:title] = title
				@view.controller.countup_macro_index()
				@view.controller.make_macro_output_by_title(macro_params)
			rescue => e
				Rails.logger.warn "[wiki_mscgen]#{e.backtrace.join("\n")}"
				ex = RuntimeError.new(e.message)
				ex.set_backtrace(e.backtrace)
				raise ex
			end
		end

		def	mscgen_me(args, title)
			begin
				if !@content.nil? && !@content.kind_of?(WikiContent) && !@content.kind_of?(WikiContent::Version)
					raise "This macro can be described in wiki page only."
				end

				if @project.nil?
					Rails.logger.info "[wiki_mscgen]project is not defined."
					return ""
				end

				using_data_scheme = false
				# want to use previewing text.
				text = @view.params[:content] && @view.params[:content][:text]
				if !text.nil?
					using_data_scheme = true
				end

				if text.nil? && !@content.nil?
					text = @content.text
				end

				if text.nil?
					return	""
				end

				set_macro_params(args)
				macro_params = @macro_params.clone
				macro_params[:title] = title
				macro_params[:version] = @view.params[:version]
				@view.controller.countup_macro_index()
				@view.controller.make_macro_output_by_text(text, macro_params, using_data_scheme)
			rescue => e
				Rails.logger.warn "[wiki_mscgen]#{e.backtrace.join("\n")}"
				ex = RuntimeError.new(e.message)
				ex.set_backtrace(e.backtrace)
				raise ex
			end
		end

		def	mscgen_link(args, title, dottext)
			begin
				if @project.nil?
					Rails.logger.info "[wiki_mscgen]project is not defined."
					return ""
				end

				using_data_scheme = true

				set_macro_params(args)
				macro_params = @macro_params.clone
				macro_params[:title] = title
  			macro_params[:version] = @view.params[:version]

				@view.controller.countup_macro_index()
				@view.controller.make_macro_output_by_text(dottext, macro_params, using_data_scheme)
			rescue => e
				Rails.logger.warn "[wiki_mscgen]#{e.backtrace.join("\n")}"
				ex = RuntimeError.new(e.message)
				ex.set_backtrace(e.backtrace)
				raise ex
			end
		end


private
		def	set_macro_params(args)
			@macro_params = {
				:format => "png",
				:layout => "dot",
			}

			need_value = {
				:inline => true, 
				:format => true, 
				:lauout => true,
				:target => true,
				:href => true,
				:wiki => true,
				:align => true,
				:width => true,
				:height => true,
			}

			args.each {|a|
				k, v = a.split(/=/, 2).map { |e| e.to_s.strip }
				if k.nil? || k == ""
					next
				end

				sym = k.intern
				if need_value[sym] && (v.nil? || v.to_s == "")
					raise "macro parameter:#{k} needs value"
				end
				@macro_params[sym] = v.nil? ? true : v.to_s
			}
		end
	end


	class ViewListener < Redmine::Hook::ViewListener
		def view_layouts_base_html_head(context)
			context[:controller].send(:render_to_string,
				:template => 'wiki_mscgen/_head',
				:layout => false,
				:locals => {:context => context})
		end
	end
end

# vim: set ts=2 sw=2 sts=2:


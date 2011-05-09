require 'digest/sha2'
require	'tempfile'
require	'kconv'
require	'fileutils'

module WikiGraphvizHelper

	class	FalldownDotError < RuntimeError
	end

	ALLOWED_LAYOUT = {
		"circo" => 1, 
		"dot" => 1, 
		"fdp" => 1, 
		"neato" => 1, 
		"twopi" => 1,
	}.freeze

	ALLOWED_FORMAT = {
		"png" => { :type => "png", :ext => ".png", :content_type => "image/png" },
		"jpg" => { :type => "jpg", :ext => ".jpg", :content_type => "image/jpeg" },
	}.freeze

	def	render_graph(params, dot_text, options = {})
		layout = decide_layout(params[:layout])
		fmt = decide_format(params[:format])

		name = Digest::SHA256.hexdigest( {
			:layout => params[:layout],
			:format => params[:format],
			:dot_text => dot_text,
		}.to_s)
		cache_seconds = Setting.plugin_wiki_graphviz_plugin['cache_seconds'].to_i
		result = nil
		if cache_seconds > 0 && ActionController::Base.cache_configured?
			# expect ActiveSupport::Cache::MemCacheStore
			result = read_fragment name , :raw => false
		end

		if !result
			result = self.render_graph_exactly(layout, fmt, dot_text, options)
			# expect ActiveSupport::Cache::MemCacheStore
			if cache_seconds > 0 && ActionController::Base.cache_configured?
				write_fragment name, result, :expires_in => cache_seconds, :raw => false
				RAILS_DEFAULT_LOGGER.info "[wiki_graphviz]cache saved: #{name}"
			end
		else
			RAILS_DEFAULT_LOGGER.info "[wiki_graphviz]from cache: #{name}"
		end

		return result
	end


	def	make_macro_output_by_title(macro_params, project_id)
		page = @wiki.find_page(macro_params[:title], :project => @project)
		if page.nil? || 
			!User.current.allowed_to?(:view_wiki_pages, page.wiki.project)
			raise "Page(#{macro_params[:title]}) not found" 
		end

		if	macro_params[:version] && !User.current.allowed_to?(:view_wiki_edits, @project)
			macro_params[:version] = nil
		end

		content = page.content_for_version(macro_params[:version])
		self.make_macro_output_by_text(content.text, macro_params, project_id)
	end

	def	make_macro_output_by_text(dottext, macro_params, project_id)
		graph = self.render_graph(macro_params, dottext)
		if !graph[:image]
			raise "page=#{macro_params[:title]}, error=#{graph[:message]}"
		end

		macro = {
			:project_id => project_id,
			:params => macro_params,
			:graph => graph,
			:dottext => dottext,
			:map_index => @index_macro,
		}

    render_to_string :template => 'wiki_graphviz/macro', :layout => false, :locals => {:macro => macro}
	end

	def	countup_macro_index
		if @index_macro
			@index_macro = @index_macro + 1
		else
			@index_macro = 0
		end
		@index_macro
	end

	def	render_graph_exactly(layout, fmt, dot_text, options = {})

		dir = File.join([RAILS_ROOT, 'tmp', 'wiki_graphviz_plugin'])
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
		begin
			self.create_image_using_gv(layout, fmt, dot_text, result, temps)
		rescue NotImplementedError, FalldownDotError
			self.create_image_using_dot(layout, fmt, dot_text, result, temps) 
		end

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

	def	create_image_using_dot(layout, fmt, dot_text, result, temps)
		RAILS_DEFAULT_LOGGER.info("[wiki_graphviz]using dot")

		temps[:dot].open
		temps[:dot].write(dot_text)
		temps[:dot].close

		p = proc {|mes|
			temps[:err].open
			t = temps[:err].read.to_s.strip
			t = t.toutf8
			result[:message] = t != "" ? t : mes
		}

		system("dot -K#{layout} -T#{fmt[:type]} < \"#{temps[:dot].path}\" > \"#{temps[:img].path}\" 2>\"#{temps[:err].path}\"")
		if !$?.exited? || $?.exitstatus != 0
			RAILS_DEFAULT_LOGGER.info("[wiki_graphviz]dot image: #{$?.inspect}")
			p.call("failed to execute dot when creating image.")
			return
		end

		system("dot -K#{layout} -Timap < \"#{temps[:dot].path}\" > \"#{temps[:map].path}\" 2>\"#{temps[:err].path}\"")
		if !$?.exited? || $?.exitstatus != 0
			RAILS_DEFAULT_LOGGER.info("[wiki_graphviz]dot map: #{$?.inspect}")
			p.call("failed to execute dot when creating map.")
			return
		end
	end

	def	create_image_using_gv(layout, fmt, dot_text, result, temps)
		RAILS_DEFAULT_LOGGER.info("[wiki_graphviz]using Gv")

		pipes = IO.pipe

		begin
			pid = fork {
				# child
	
				# Gv reports errors to stderr immediately.
				# so, get the message from pipe
				STDERR.reopen(pipes[1])
	
				begin
					require 'gv'
				rescue LoadError
					exit! 5
				end

				g = nil
				ec = 0
				begin
					g = Gv.readstring(dot_text)
					if g.nil?
						ec = 1
						raise	"readstring"
					end
					r = Gv.layout(g, layout)
					if !r
						ec = 2
						raise	"layout"
					end
					r = Gv.render(g, fmt[:type], temps[:img].path)
					if !r
						ec = 3
						raise	"render"
					end
					r = Gv.render(g, "imap", temps[:map].path)
					if !r
						ec = 4
						raise	"render imap"
					end
				rescue RuntimeError
				ensure
					if g
						Gv.rm(g)
					end
				end
				exit! ec
			}

			# parent
			pipes[1].close

			Process.waitpid pid
			stat = $?
			ec = stat.exitstatus
			RAILS_DEFAULT_LOGGER.info("[wiki_graphviz]child status: #{stat.inspect}")
			if stat.exited? && ec == 5
				# Chance to falldown using external dot command.
				raise FalldownDotError, "failed to load Gv."
			end

			result[:message] = pipes[0].read.to_s.strip
			if ec != 0 && result[:message] == ""
				result[:message] = "Child process failed."
			end

		ensure
			pipes.each {|p|
				if !p.closed?
					p.close
				end
			}
		end

	end

private 


	def	decide_format(fmt)
		fmt = ALLOWED_FORMAT[fmt.to_s.downcase]
		fmt ||= ALLOWED_FORMAT["png"]

		fmt
	end

	def	decide_layout(layout)
		layout = layout.to_s.downcase
		if !ALLOWED_LAYOUT[layout]
			layout = "dot"
		end

		layout
	end


	class Macro
		def	initialize(view, wiki_content)
			@content = wiki_content

			@view = view
			@view.controller.extend(WikiGraphvizHelper)
		end

		def	graphviz(args, project_id)
			begin
				title = args.pop.to_s
				if title == ""
					raise "With no argument, this macro needs wiki page name"
				end

				set_macro_params(args)
				macro_params = @macro_params.clone
				macro_params[:title] = title
				@view.controller.countup_macro_index()
				@view.controller.make_macro_output_by_title(macro_params, project_id)
			rescue => e
				# wiki_formatting.rb(about redmine 1.0.0) catch exception and write e.to_s into HTML. so escape message.
				ex = RuntimeError.new(ERB::Util.html_escape(e.message))
				ex.set_backtrace(e.backtrace)
				raise ex
			end
		end

		def	graphviz_me(args, project_id, title)
			begin
				if @content.nil?
					return	""
				end

				set_macro_params(args)
				macro_params = @macro_params.clone
				macro_params[:title] = title
				@view.controller.countup_macro_index()
				@view.controller.make_macro_output_by_text(@content.text, macro_params, project_id)
			rescue => e
				# wiki_formatting.rb(about redmine 1.0.0) catch exception and write e.to_s into HTML. so escape message.
				ex = RuntimeError.new(ERB::Util.html_escape(e.message))
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
end

# vim: set ts=2 sw=2 sts=2:


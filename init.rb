require 'redmine'


Rails.logger.info 'Starting wiki_mscgen_plugin for Redmine'

Redmine::Plugin.register :wiki_mscgen_plugin do |plugin|
	requires_redmine :version_or_higher => '4.0.0'
  name 'Mscgen Wiki-macro Plugin'
  author 'zecke'
  url "http://github.com/zecke/redmine-wiki_mscgen_plugin"
  description 'Render graph image from the wiki contents by mscgen(http://www.mcternan.me.uk/mscgen/)'
  version '0.8.0'
	settings :default => {'cache_seconds' => '0'}, :partial => 'wiki_mscgen/settings'

	Redmine::WikiFormatting::Macros.register do

		desc <<'EOF'
Render graph image from the wiki page which is specified by macro-args.

<pre>
{{mscgen(Foo)}}
{{mscgen(option=value...,Foo)}}
</pre>

* Available options are below.
** format={png|jpg|svg}
** layout={dot|neato|fdp|twopi|circo|osage|patchwork|sfdp}
** inline={true|false}
*** If svg format is specified, Its default output is inline SVG. If inline is false, img tag will be used.
** target={_blank|any} (*1)
** with_source (*1)
** no_map (*1)
** wiki=page(which link to) (*1)
** link_to_image (*1)
** align=value(e.g. {right|left}) (*1)
** width=value(e.g. 100px, 200%)
** height=value(e.g. 100px, 200%)
* (*1): These options do not affect to the inline SVG.
EOF

		plugin_directory = File.basename(File.dirname(__FILE__))

		check_plugin_directory = lambda {
			if plugin_directory != plugin.id.to_s
				raise "*** Plugin directory name of 'Mscgen Wiki-macro Plugin' is must be '#{plugin.id}', but '#{plugin_directory}'"
			end
		}

		macro :mscgen do |wiki_content_obj, args|
			check_plugin_directory.call
			m = WikiMscgenHelper::Macro.new(self, wiki_content_obj)
			m.mscgen(args).html_safe
		end

		desc <<'EOF'
Render graph image from the current wiki page.

<pre>
// {{mscgen_me}}
// {{mscgen_me(option=value...)}}
</pre>

* options: see mscgen macro.
EOF
		macro	:mscgen_me do |wiki_content_obj, args|
			check_plugin_directory.call
			m = WikiMscgenHelper::Macro.new(self, wiki_content_obj)
			m.mscgen_me(args, params[:id]).html_safe
		end


		desc <<'EOF'
Render graph image from text within the macro command.

<pre>
{{graphviz_link()
  graphviz commands
}}
{{graphviz_link(option=value...)
  graphviz commands
}}
</pre>

* options: see graphviz macro.
EOF
		macro	:mscgen_link do |wiki_content_obj, args, dottext |
			check_plugin_directory.call
			m = WikiMscgenHelper::Macro.new(self, wiki_content_obj)
			m.mscgen_link(args, params[:id], dottext).html_safe
		end

	end
end


      
# vim: set ts=2 sw=2 sts=2:

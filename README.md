# Redmine Wiki mscgen-macro plugin

Redmine Wiki Mscgen-macro plugin will make Redmine's wiki to render graph image
forked from the Graphviz-macro plugin.

## Features

* Add wiki macro ```{{mscgen}}```, ```{{mscgen_link}}``` and ```{{mscgen_me}}```
* Write wiki page as dot format, and the macros make it graph image.

### {{mscgen}} macro

* This macro render graph image from other wiki page's content.

	```
    {{mscgen(Foo)}}
    {{mscgen(option=value,Foo)}}
    {{mscgen(target=_blank,with_source,Foo)}}
	```

* format={png|jpg|svg}
* inline={true|false}
	* If svg format is specified, Its default output is inline SVG. If inline is false, img tag will be used.
* target={_blank|any} (*1)
* with_source : Display both image and its source(dot) (*1)
* no_map : Disable clickable map. (*1)
* wiki=page : Link image to specified wiki page. (*1)
* link_to_image : Link image to itself. (*1)
* align=value : Additional attr for IMG. (*1)  
   e.g.) ```right```, ```left```
* width=value : Additional attr for IMG.   
	*  It is recommended to use no_map option together.  
       e.g.) ```100px```, ```200%```
* height=value : Additional attr for IMG. 
	* It is recommended to use no_map option together.  
      e.g.) ```100px```, ```200%```
* (*1): These options do not affect to the inline SVG.

### {{mscgen_me}} macro

* This macro render graph image from the wiki page which includes this macro. 
* Use this macro *commented out* like below. If it is not commented out, renderer fails syntax error.

	```
    // {{mscgen_me()}}
    // {{mscgen_me(option=value)}}
	```

* options: See ```{{mscgen}}``` macro.
* When previewing, this macro output the image into img@src with data scheme. Thus, old browsers can't render it.

### {{mscgen_link}} macro

* This macro render graph image having passing the dot description inline. 

	```
    {{mscgen_link()
    msc {...}
    }}
    {{mscgen_link(option=value)
    msc {...}
    }}
	```

* options: See ```{{mscgen}}``` macro.

## Tips

* Example

	```
    {{mscgen_link()
    msc {
      hscale = "2";

      a,b,c;

      a->b [ label = "ab()" ] ;
      b->c [ label = "bc(TRUE)"];
      c=>c [ label = "process(1)" ];
      c=>c [ label = "process(2)" ];
      ...;
      c=>c [ label = "process(n)" ];
      c=>c [ label = "process(END)" ];
      a<<=c [ label = "callback()"];
      ---  [ label = "If more to run", ID="*" ];
      a->a [ label = "next()"];
      a->c [ label = "ac1()\nac2()"];
      b<-c [ label = "cb(TRUE)"];
      b->b [ label = "stalled(...)"];
      a<-b [ label = "ab() = FALSE"];
    }
    }}
	```

## Requirement

* Redmine 4.0.0 or later.
* ruby 2.2
* Mscgen http://www.mcternan.me.uk/mscgen/
		```
* memcached (optional)

## Getting the plugin

https://github.com/zecke/redmine-wiki_mscgen_plugin

e.g.)
```
git clone git://github.com/zecke/redmine-wiki_mscgen_plugin wiki_mscgen_plugin
```


## Install

1. Copy the plugin tree into #{RAILS_ROOT}/plugins/

	```
    #{RAILS_ROOT}/plugins/
        wiki_mscgen_plugin/
	```
2. Make sure the temporary directory writable by the process of redmine.

	```
    #{RAILS_ROOT}/tmp/
	```

	This plugin try to create follwing directory and create tmporary file under it.

	```
    #{RAILS_ROOT}/tmp/wiki_mscgen_plugin/
	```

3. Restart Redmine.

### Optional

* If you want to use caching feature for rendered images, must configure your cache_store.
* This plugin expects the store like ```ActiveSupport::Cache::DalliStore``` which provides marshaling when set/get the value. 

<!-- dummy for breaking list -->

1. Setup caching environment, like memcached.
1. Install gem for caching.
   ```
   # e.g.) cd $RAILS_ROOT
   $ bundle add dalli
   ```
1. Configure cache_store.

	```
     e.g.) config/environments/production.rb
     config.action_controller.perform_caching = true
     config.action_controller.cache_store = :dalli_cache_store, "localhost" 
	```
1. Restart Redmine.
1. Login to Redmine as an Administrator.
1. Setup wiki mscgen-macro settings in the Plugin settings panel.

## License

This plugin is licensed under the GNU GPL v2.  
See COPYRIGHT.txt and GPL.txt for details.


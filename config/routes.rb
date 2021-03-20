Rails.application.routes.draw do
	get 'projects/:project_id/wiki/:id/mscgen', :to => 'wiki_mscgen#mscgen'
end

# vim: set ts=2 sw=2 sts=2:


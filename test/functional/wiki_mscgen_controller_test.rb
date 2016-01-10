require File.dirname(__FILE__) + '/../test_helper'

class WikiMscgenControllerTest < ActionController::TestCase
  # Replace this with your real tests.
  def test_routing
   	assert_recognizes( 
		{
			:controller => 'wiki_mscgen', 
			:action => 'mscgen',
			:project_id => 'sample',
			:id => 'WikiPage'
		},
		'projects/sample/wiki/WikiPage/mscgen'
	)
   	assert_routing( 
		'projects/sample/wiki/WikiPage/mscgen',
		:controller => 'wiki_mscgen', 
		:action => 'mscgen',
		:project_id => 'sample',
		:id => 'WikiPage'
	)
  end
end

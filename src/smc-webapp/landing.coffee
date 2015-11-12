###
Entry point for the Landing Page -- sign up, sign in, learn more about.
###

# static html which gets progressively refined/used as templated by jQuery -- will go away with React.js rewrite

require('./html')
# Needed by DateTimePicker - http://jquense.github.io/react-widgets/docs/#/i18n
require('react-widgets/lib/less/react-widgets.less')

# SASS Style file
require('./index.sass')

# Load/initialize React-related flux functionality
require('./r')

require('./system_notifications')

# Initialize some jquery plugins needed below (TODO: will obviously go away with react rewrite)
require('./jquery_plugins')

# Initialize the top navigation bar.
require('./top_navbar')

# Account flux store
require('./account_flux')

# The login page
require('./account')

# Enable the exit confirmation functionality -- checks if you really want to exit page
require('./exit_confirmation')

# Uncomment the below and everything gets loaded all at once, rather than lazy when
# other stuff gets opened.  Is faster in some ways and slower in others.
if true
    require('./projects')
    require('./editor')

# TODO: temporary -- ensure that the help page is rendered: do this once only on load
# WE will remove this when we have a proper router.
require('./r_help').render_help_page()

# Should be loaded last -- this checks the url and opens up the relevant page, etc.
require('./last')


# Enable transparent server-side requiring of cjsx files.
require('node-cjsx').transform()

# Code for static server-side rendering of the subscription options.
exports.render_subscriptions = ->
    React = require('react')
    billing = require('./billing.cjsx')
    fs = require('fs')
    html = React.renderToString(billing.render_static_pricing_page())
    filename = '../static/policies/pricing.html'
    s = fs.readFileSync(filename+'.template').toString()
    i = s.indexOf('start:SubscriptionGrid')
    i = s.indexOf('\n', i) + 1
    j = s.indexOf('end:SubscriptionGrid')
    j = s.lastIndexOf('\n', j) - 1
    s = s.slice(0,i) + html + s.slice(j+1)
    fs.writeFileSync(filename, s)

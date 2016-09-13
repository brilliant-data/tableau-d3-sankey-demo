_ = require 'underscore'
Promise = require 'bluebird'
cors = require('cors')


express = require 'express'
app = express()

server_config =
  port: 9998
  address: "0.0.0.0"



# create a config to configure both pooling behavior
# and client options
# note: all config is optional and the environment variables
# will be read if the config is not present
process.on 'unhandledRejection', (e)->
  console.error("Node 'unhandledRejection':", e.message, e.stack)



app.use express.static('_public')
app.use(cors())

app.listen server_config.port, server_config.address, ()->
  console.log("Test app listening on port #{server_config.port}!")



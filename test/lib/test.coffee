assert = require 'assert'

build = require '../../lib/index.coffee'

describe 'test Output', ->

  it 'should build', -> assert build()

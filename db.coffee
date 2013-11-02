
# Our very own tiny database layer.
# Wraps MongoClient in a layer of Bling's Promises.

MongoClient = require('mongodb').MongoClient
$ = require 'bling'

# teach bling how to deal with some mongo objects
$.type.register 'ObjectId', {
	is: (o) -> o?._bsontype is "ObjectID"
	string: (o) -> o.toHexString()
	repr: (o) -> "ObjectId('#{o.toHexString()}')"
}

$.type.register 'cursor', {
	is: (o) -> o?.cursorId?
	string: (o) -> "Cursor(#{o.totalNumberOfRecords})"
}

connections = {}

# db is the public way to construct a db object,
# expects to (eventually) use a promise from the connections map
db = (ns = "/") ->
	collection: (_coll) ->
		o = (_op) -> (args...) -> # wrap a native operation with a promise
			try p = $.Promise()
			finally unless ns of connections then p.fail "namespace not connected: #{ns}"
			else
				fail_or = (pass) -> (e, r) ->
					return p.fail(e) if e
					try pass(r) catch err
						$.log "During #{_op}", err.stack
				connections[ns].wait fail_or (_db) ->
					_db.collection(_coll)[_op] args..., fail_or p.finish
		# Support these native operations:
		findOne:     o 'findOne'
		find:        o 'find'
		count:       o 'count'
		insert:      o 'insert'
		update:      o 'update'
		save:        o 'save'
		remove:      o 'remove'
		ensureIndex: o 'ensureIndex'

db.connect = (args...) ->
	url = args.pop()
	ns = if args.length then args.pop() else "/"
	connections[ns] = $.extend ($.Promise.wrapCall MongoClient.connect, url, { safe: true }),
		ns: ns
		url: url

module.exports.db = db

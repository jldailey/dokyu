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

routes = { }
connections = { }
connect = (url) ->
	p = $.Promise()
	MongoClient.connect url, { safe: true }, (err, nativ) ->
		if err then p.fail err
		else p.finish nativ
	p

exports.db = db = (ns = "/") ->
	collection: (_coll) ->
		# Wrap the native operations in Promises
		wrapped = (_op) -> (args...) ->
			q = $.Promise()
			unless ns of connections
				throw new Error("namespace not connected: #{ns}")
			connections[ns].wait (err, nativ) ->
				if err then q.fail err
				else nativ.collection(_coll)[_op] args..., (err, result) ->
					if err then q.fail err
					else q.finish result
			q
		findOne:     wrapped 'findOne'
		find:        wrapped 'find'
		count:       wrapped 'count'
		insert:      wrapped 'insert'
		update:      wrapped 'update'
		save:        wrapped 'save'
		remove:      wrapped 'remove'
		ensureIndex: wrapped 'ensureIndex'

db.connect = (args...) ->
	url = args.pop()
	ns = if args.length then args.pop() else "/"
	connections[ns] = connect routes[ns] = url

if require.main is module

	# set the default connection
	db.connect "mongodb://localhost:27017/default"

	# set up a test connection
	db.connect "test", "mongodb://localhost:27017/test"

	$.Promise.compose(
		# use the default connection
		db().collection("documents").count().wait (err, count) ->
			$.log "default.documents count:", err ? count
		
		# use the test connection
		db("test").collection("document").count().wait (err, count) ->
			$.log "test.documents count:", err ? count
	).wait (err) ->
		process.exit if err then 1 else 0
		

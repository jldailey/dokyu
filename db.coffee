
# Our very own tiny database layer.
# Wraps MongoClient in a layer of Bling's Promises.

MongoClient = require('mongodb').MongoClient
$ = require 'bling'

# teach bling how to deal with some mongo objects
$.type.register 'ObjectId',
	is: (o) -> o?._bsontype is "ObjectID"
	string: (o) -> o.toHexString()
	repr: (o) -> "ObjectId('#{o.toHexString()}')"

$.type.register 'cursor',
	is: (o) -> o and o.cursorId?
	string: (o) -> "Cursor(n=#{o?.totalNumberOfRecords})"

connections = {}

default_namespace = "/"

# db is the public way to construct a db object,
# expects to (eventually) use a promise from the connections map
db = (ns = default_namespace) ->
	collection: (_coll) ->
		log = $.logger "[db/#{_coll}]"
		o = (_op) -> (args...) -> # wrap a native operation with a promise
			p = $.Promise()
			unless ns of connections then p.fail "namespace not connected: #{ns}"
			else
				id = p.promiseId
				fail_or = (pass) -> (e, r) ->
					if e then return p.fail(e)
					try pass(r) catch err
						log "failed", _op, id, $.debugStack err.stack
				connections[ns].wait fail_or (_db) ->
					_db.collection(_coll)[_op] args..., fail_or (result) ->
						p.finish result
			# log "returning", p
			return p
		# Wrap these native operations:
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
	ns = if args.length then args.pop() else default_namespace
	connections[ns] = $.extend ($.Promise.wrapCall MongoClient.connect, url, { safe: true }),
		ns: ns
		url: url

db.disconnect = (ns = default_namespace) ->
	connections[ns]?.then (_db) -> _db.close()


module.exports.db = db

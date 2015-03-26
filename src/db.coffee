
# Our very own tiny database layer.

$ = require 'bling'
Mongo = require 'mongodb'
{MongoClient, ObjectID} = Mongo

# teach bling how to deal with some mongo objects
$.type.register 'ObjectId',
	is: (o) -> o and o._bsontype is "ObjectID"
	string: (o) -> (o and o.toHexString()) or String(o)
	repr: (o) -> "ObjectId('#{o.toHexString()}')"

$.type.register 'cursor',
	is: (o) -> o and o.cursorState?
	string: (o) -> "Cursor(#{$.as 'string', o.cursorState.cursorId})"

$.type.register 'WriteResult',
	is: (o) -> o and o.result?.ok? and o.connection?
	string: (o) -> "WriteResult(ok=#{o.result.ok}, n=#{o.result.n})"
	repr: (o) -> "WriteResult({ ok: #{o.result.ok}, n: #{o.result.n}})"

connections = Object.create null
collections = Object.create null

default_namespace = "/"

# db is the public way to construct a db object,
# expects to (eventually) use a promise from the connections map
db = (ns = default_namespace) ->
	createCollection: (name, opts, cb) ->
		key = ns + ":" + name
		# $.log "db: createCollection", key, opts
		unless ns of connections then $.log "db: not connected: #{ns}"
		else if key of collections then $.log "db: createCollection already exists:", name
		else
			# $.log "db: createCollection",name,"starting to wait..."
			connections[ns].wait (err, _db) ->
				if err then return $.log "db: createCollection error", err
				# $.log "db: createCollection", name, "starting"
				opts.safe = true
				_db.createCollection name, opts, (err) ->
					# $.log "db: createCollection", name, "completed"
					collections[key] = _db.collection(name)
					cb? err
	collection: (_coll) ->
		log = $.logger "[db/#{_coll}]"
		o = (_op) -> (args...) -> # wrap a native operation with a promise
			p = $.Promise()
			if $.is 'function', $(args).last()
				p.wait args.pop()
			# log "starting #{_op}:", args...
			unless ns of connections then p.fail "namespace not connected: #{ns}"
			else
				id = p.promiseId
				fail_or = (pass) -> (e, r) ->
					# log "failing #{_op}:", e if e
					if e then return p.fail(e)
					try pass(r) catch err
						log "failed in callback", _op, id, $.debugStack err.stack
				connections[ns].wait fail_or (_db) ->
					# log "#{_op}: issuing on #{_coll}:", args...
					_db.collection(_coll)[_op] args..., fail_or (result) ->
						# log "#{_op}: result", try $.as 'string', result catch err then String(result)
						p.finish result
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
		stream: (query, cb) ->
			unless ns of connections then cb new Error "namespace not connected: #{ns}"
			else connections[ns].wait (err, _db) =>
				key = ns + ":" + _coll
				# log "stream: starting...", key, query
				if err then cb(err)
				else unless key of collections
					# log "stream: restarting..."
					$.delay 50, => @stream query, cb
				else
					try
						# log "stream: query...", query
						do openStream = ->
							stream = collections[key].find(query, {
								tailable: true,
								awaitdata: true,
								numberOfRetries: -1
							}).stream()
							stream.on 'error', (err) ->
								log "stream: error", err
								cb err, null
							stream.on 'data', (doc) ->
								# log "stream: data", doc
								cb null, doc
							stream.on 'close', ->
								# log "stream: close", arguments
								$.delay 100, openStream
					catch err
						log "stream: caught", err
						cb err, null

db.connect = (args...) ->
	url = args.pop()
	ns = if args.length then args.pop() else default_namespace
	connections[ns] = $.extend p = $.Promise(),
		ns: ns
		url: url
	# $.log "db: connect starting", url
	MongoClient.connect url, { safe: true }, (err, db) ->
		if err then p.reject(err) else p.resolve(db)
	p.wait (err) ->
		if err then $.log "connection error:", err

db.disconnect = (ns = default_namespace) ->
	connections[ns]?.then (_db) -> _db.close()

db.ObjectId = Mongo.ObjectID

module.exports.db = db

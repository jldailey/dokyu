
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
		opts = $.extend {}, opts, { safe: true }
		log = $.logger "db.createCollection('#{name}', #{$.as 'repr', opts}, cb)"
		key = ns + ":" + name
		# $.log "db: createCollection", key, opts
		unless ns of connections then $.log "db: not connected: #{ns}"
		else if key of collections then $.log "db: createCollection already exists:", name
		else
			# $.log "db: createCollection",name,"starting to wait..."
			log "waiting for connection..."
			connections[ns].wait (err, _db) ->
				if err then return log err
				log "connected..."
				# $.log "db: createCollection", name, "starting"
				_db.createCollection name, opts, (err) ->
					# $.log "db: createCollection", name, "completed"
					collections[key] = _db.collection(name)
					cb? err
	collection: (_coll) ->
		o = (_op, _touch) -> (args...) -> # wrap a native operation with a promise
			log = $.logger "db.#{_coll}.#{_op}(#{$(args).map($.partial $.as, 'string').join ", "})"
			p = $.Promise()
			if $.is 'function', $(args).last()
				p.wait args.pop()
			log "starting"
			unless ns of connections then p.fail "namespace not connected: #{ns}"
			else
				id = p.promiseId
				fail_or = (pass) -> (e, r) ->
					log "MongoClient failed:", e if e
					if e then return p.fail(e)
					try pass(r) catch err
						log "failed in callback", id, $.debugStack err.stack
				connections[ns].wait fail_or (_db) ->
					log "issuing real command to MongoClient..."
					_db.collection(_coll)[_op] args..., fail_or (result) ->
						log "MongoClient responded:", $.as 'string', result
						p.resolve result
			return _touch?(p) ? p
		# Wrap these native operations:
		findOne:     o 'findOne'     # (qry, [fields], cb)
		find:        o 'find'        # (qry, [fields], [opts], cb)
		count:       o 'count'       # (qry, [opts], cb)
		insert:      o 'insert'      # (doc, [opts], cb)
		update:      o 'update'      # (qry, update, [opts], cb)
		save:        o 'save'        # (obj, [opts], cb)
		remove:      o 'remove'      # (qry, [opts], cb)
		ensureIndex: o 'ensureIndex' # (obj, [opts], cb)
		stream: (query, cb) ->
			log = $.logger "db.#{_coll}.stream(#{$.as 'string', query})"
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
								awaitData: true,
								numberOfRetries: -1
							}).stream()
							stream.on 'error', (err) ->
								log "error", err
								cb err, null
							stream.on 'data', (doc) ->
								# log "stream: data", doc
								cb null, doc
							stream.on 'close', ->
								# log "stream: close", arguments
								$.delay 100, openStream
					catch err
						log "caught", err
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

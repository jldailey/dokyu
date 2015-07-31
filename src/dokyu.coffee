$ = require 'bling'
{db} = require './db'

#define KB *1024
#define MB *1024 KB
#define GB *1024 MB

createObjectId = -> db.ObjectId.createPk()

classes = {}

$.type.extend 'global',
	string: (o) -> "{ ... global ... }"

$.type.register 'document', _tmp = {
	is: (o) -> o and $.isType 'InnerDocument', o
	string: (o) -> "{ ... document:#{String(o._id).substr(19)} ... }"
	repr: (o) -> "new #{o.constructor.name}({ #{("'#{k}': #{$.toRepr v}" for k,v of o).join()} })"
	clone: (o) ->
		if o then new (o.constructor)(o) else null
	hash: (o) -> ($.hash(k)*$.hash(v) for k,v of o).sum()
}

Document = (collection, doc_opts) ->
	doc_opts = $.extend {
		timeout: 3000
		collection: collection
		ns: undefined
	}, doc_opts
	return classes[doc_opts.collection] or= class InnerDocument extends $.EventEmitter

		log = $.logger "[#{doc_opts.collection}]"

		instance_counter = 0
		instance_cache = new $.Cache(1000, Infinity)

		# the default constructor gets used to build instances,
		# given a result document from the database
		constructor: (props) ->
			super @
			if props? then for own k,v of props then @[k] = v
			@instanceId = instance_counter++
			@_id ?= createObjectId()

		# MyDocument.getOrCreate is the most common way to access documents.
		# e.g.
		#   class MyDocument extends Document('documents') then @unique { name: 1 }
		#   MyDocument.getOrCreate { name: ... }, (err, doc) ->
		InnerDocument.getOrCreate = (query, cb) ->
			klass = @
			p = $.Promise()
			if $.is 'function', cb
				p.wait cb
			fail_or = (f) -> (e, r) ->
				if e then return p.reject(e)
				try f(r) catch err then p.reject(err)
				null

			db(doc_opts.ns).collection(collection).findOne(query).wait fail_or (result) ->
				if result?
					key = String result._id
					p.resolve instance_cache.set key, if instance_cache.has key
						# freshen the cached item with data fields from the db,
						# but runtime things (from __proto__) like events, are preserved
						$.extend instance_cache.get(key), result
					else new klass(result)
				else
					key = String (ret = new klass query)._id
					p.resolve instance_cache.set key, ret
			p

		# construct all the stuff from a type, recursively
		construct = (klass, stuff) ->
			stuff = switch $.type stuff
				when "object" then new klass stuff
				when "array","bling"
					stuff.map $.partial construct, klass
				else stuff

		# o wraps a db operation to do class-mapping on its output,
		# e.g. MyDocument.findOne(query) searches the right collection,
		# and returns MyDocument objects. MyDocument.find(query)
		# returns a cursor that yields MyDocuments.
		o = (_op, expect_result=false) -> (args...) ->
			klass = @
			# wrap this operation in a Promise
			p = $.Promise()
			# automatically use a callback (if given) to wait on the Promise
			if $.is 'function', $(args).last()
				p.wait args.pop()
			# if we are updating an object, and we pass the whole object in
			# then there is only one match possible (the _id) so don't bother with the rest
			if _op is 'update' and '_id' of args[0]
				args[0] = { _id: args[0]._id }
			timer = $.delay doc_opts.timeout, -> p.reject('timeout')
			# $.log "[o] starting op:", _op, "(",args,") on collection", doc_opts.collection
			db(doc_opts.ns).collection(doc_opts.collection)[_op](args...).wait (err, result) ->
				timer.cancel()
				# $.log "[o] finished op:", _op, err, try $.as 'string', result catch err then String(result)
				switch
					when err then p.reject(err)
					when expect_result and not result? then p.reject "no result"
					else
						p.resolve construct klass, result
				null
			p

		$.extend InnerDocument,
			count:   o 'count'
			findOne: o 'findOne', true
			update:  o 'update'
			remove:  o 'remove'
			index:   o 'ensureIndex'
			unique: (keys) -> @index keys, { unique: true, dropDups: true }
			# set the default query timeout
			timeout: (ms) ->
				try doc_opts.timeout = parseInt ms, 10
				catch err then doc_opts.timeout = 1000
				@
			# find creates a fake cursor
			find: (query = {}, opts = {}) ->
				klass = @
				cursor_promise = db(doc_opts.ns).collection(doc_opts.collection).find(query, opts)
				fail_or = (cb, f) -> (e,r) ->
					cb ?= $.identity
					return cb(e) if e
					try f(r) catch err then cb(err)
				finish = (cb, obj) ->
					cb null, construct(klass, obj)
				oo = (_op, swallow, touch) -> (args...) ->
					kursor = @
					cb = args.pop()
					cursor_promise.wait fail_or cb, (cursor) ->
						# $.log "[oo] starting op:", _op, "on cursor", $.keysOf(cursor.cursorState)
						cursor[_op] fail_or cb, (result) ->
							# $.log "[oo] finished op:", _op, $.keysOf(result)
							try touch? kursor, result
							if result? then finish cb, result
							else unless swallow then cb "no result", null
							else null
				# Return a fake cursor that yields the right type
				nextObject: oo 'nextObject', false
				toArray:    oo 'toArray',    false, (kursor) -> kursor.position = kursor.length
				each: (cb) ->
					@nextObject (err, item) =>
						if err is "no result"
							cb null, null
						else
							cb err, item
							@each cb
					null

		$.type.extend {
			unknown:   { symbol: -> "{unknown}" }
			document:  { symbol: -> "{document}" }
			bling:     { symbol: -> "$()" }
			array:     { symbol: -> "[]" }
			function:  { symbol: -> "->" }
			promise:   { symbol: -> "{promise}" }
			null:      { symbol: -> "{null}" }
			undefined: { symbol: -> "{undefined}" }
			string:    { symbol: -> "{string}" }
			number:    { symbol: -> "{number}" }
			ObjectId:  { symbol: -> "{ObjectId}" }
			object:    { symbol: -> "{object}" }
		}

		print_proto_chain = $.printProtoChain = (o, indent = 0) ->
			return unless o?
			spacer = $.repeat(". ", indent)
			cname = o.constructor?.name ? ""
			console.log spacer + (if indent > 0 then "\\_" else "") + "class #{cname}:"
			for own k,v of o ? {}
				console.log "#{spacer}|- #{k} #{$.type.lookup(v).symbol(v)}"
			print_proto_chain o.__proto__, indent + 1
			null

		# save should be recursive
		# for every join on this document,
		# detach and save any joined items
		# then save self and re-attach items
		save: (cb) ->
			try return p = $.Promise().wait (err, doc) -> cb? err, doc
			finally db(doc_opts.ns).collection(doc_opts.collection).save(@).wait (err, write) =>
				if err then p.reject err
				else p.resolve @

		remove: (cb) ->
			try return p = $.Promise().wait (err, doc) -> cb? err, doc
			finally db(doc_opts.ns).collection(doc_opts.collection).remove( _id: @_id ).wait (err, removed) =>
				if err then p.reject err
				else p.resolve $.extend @, { _id: null }

Document.connect = (args...) ->
	cb = if $.is 'function', $(args).last() then args.pop()
	else $.identity
	db.connect(args...).wait cb
	Document

Document.disconnect = ->
	db.disconnect()
	Document

module.exports = Document

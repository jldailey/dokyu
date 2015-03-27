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

		joins = $ [
			[ 'ready', null, null ] # during saves, detach but dont save it
		]

		# the default constructor gets used to build instances,
		# given a result document from the database
		constructor: (props) ->
			super @
			for own k,v of props
				@[k] = v
			@_id ?= createObjectId()
			@ready ?= $.Promise()
			progress = $.Progress 2 + joins.length # 2 = 1 for setup, and 1 for the collection creation
			InnerDocument.ready.wait -> progress.finish 1
			fail_or = (f) -> (err, result) ->
				if err then return progress.reject err
				else f(result)
			for join in joins then do (join) =>
				[name, coll, type, field] = join
				if not coll?
					progress.finish(1)
				klass = classes[coll] # the wrapper class for objects from this collection
				coll = db(doc_opts.ns).collection(coll)
				query = { }
				query[field] = @_id
				switch type
					when 'tailable'
						coll.stream query, (err, doc) =>
							unless err then @emit name, doc
						progress.finish(1)
					when 'array'
						fields = { }
						sort = { }
						sort[field+"_index"] = 1
						coll.find(query, fields, sort).wait fail_or (cursor) =>
							cursor.toArray (err, items) =>
								@[name] = if klass then items.map (x) ->
									x = new klass x
									if $.is 'promise', x.ready
										progress.include x.ready
									x
								else items
								progress.finish(1)
					when 'object'
						coll.findOne(query).wait fail_or (item) =>
							@[name] = if item? and klass then construct klass, item else item
							progress.finish(1)
			progress.finish(1)
			progress.wait (err) =>
				if err then @ready?.reject err
				else @ready?.resolve @

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
				$.log "getOrCreate: result", e, r
				if e then return p.reject(e)
				try f(r) catch err then p.reject(err)
				null

			$.log "getOrCreate: calling findOne", query
			db(doc_opts.ns).collection(collection).findOne(query).wait fail_or (result) ->
				if result? then new klass(result).ready.wait p.handler
				else new klass(query).save().wait p.handler
			p

		# MyDocument.ready is the basic promise that the collection has been created
		InnerDocument.ready = $.Progress(1)

		# joins will get processed as each @join directive is parsed on each class definition
		# so immediately on the next tick, consider the setup to be started
		# each join can call InnerDocument.ready.include {promise} to delay readiness.
		$.immediate -> InnerDocument.ready.finish 1

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
			p = $.Promise()
			if $.is 'function', $(args).last()
				p.wait args.pop()
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
			join:   (name, coll, type, field, opts) ->
				if $.is 'object', field
					opts = field
				unless $.is 'string', field
					field = 'parent'
				joins.push [name, coll, type, field]
				fields = Object.create null
				fields[field] = 1
				if type is 'array'
					fields[field+"_index"] = 1
				# make sure the join query will be indexed
				switch type
					when 'array' then db(doc_opts.ns).collection(coll).ensureIndex fields, \
						$.extend {}, opts
					when 'object' then db(doc_opts.ns).collection(coll).ensureIndex fields, \
						$.extend {}, opts
					when 'tailable'
						InnerDocument.ready.include p = $.Promise()
						# $.log "dokyu: createCollection", coll, opts
						opts = $.extend { capped: true, max: 10000, size: 10 MB }, opts
						db(doc_opts.ns).createCollection coll, opts, (err) ->
							if err then p.reject "save: createCollection error", err
							p.resolve()
				@
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
			orig = @
			save_log = $.logger "save(#{@constructor.name}:#{@name})"
			try return p = $.Promise().wait (err, result) ->
				# save_log "ended with:", err, result
				cb? err, result
			finally orig.ready.then ->
				copy = $.clone orig
				# save_log "starting save...", $.as 'string', copy
				unless copy?
					return p.fail "clone failed"
				do nextJoin = (j = 0) ->
					if j >= joins.length
						# save_log "done saving all joins, saving copy...", copy, doc_opts.ns, doc_opts.collection
						return db(doc_opts.ns).collection(doc_opts.collection).save(copy).wait (err, write) ->
							# save_log "done saving copy", err, write?.result
							if err then return p.reject err
							# save_log "resolving with original"
							p.resolve orig
					[name, coll, type, field] = joins[j]
					do (name, coll, type, field) ->
						switch type
							when 'object'
								if not copy[name]?
									nextJoin j + 1
								else
									copy[name][field] = orig[name][field] = orig._id
									copy[name].save (err, write) ->
										# save_log "done with", name, err, write
										nextJoin j + 1
							when 'tailable'
								return nextJoin j + 1
							when 'array'
								a = copy[name]
								b = orig[name]
								do nextItem = (i = 0) ->
									if i >= a.length
										return nextJoin j + 1
									# save_log "join",j,"saving",name,'index',i
									a[i][field] = b[i][field] = orig._id
									a[i][field+"_index"] = b[i][field+"_index"] = i
									a[i].save (err, write) ->
										# save_log "done with", name, i, err, write
										nextItem i + 1
							when null
								# save_log "detaching completely", name
								delete copy[name]
								nextJoin j + 1
						null
					null

		remove: ->
			p = $.Progress(1)
			@ready.then (self) =>
				log "Removing", @_id, "from", doc_opts.collection
				p.include db(doc_opts.ns).collection(doc_opts.collection).remove( _id: @_id )
				for join in joins then do (join) =>
					[name, coll, type,field] = join
					query = {}
					query[field] = @_id
					log "Removing joined data from", coll, "query:", query
					p.include db(doc_opts.ns).collection(coll).remove( query, { multi: true } )
				p.finish(1)
			p.on 'progress', (cur, max) =>
				log "Removed", @_id, cur,"of",max
			p

Document.connect = (args...) ->
	cb = if $.is 'function', $(args).last() then args.pop()
	else $.identity
	db.connect(args...).wait cb
	Document

Document.disconnect = ->
	db.disconnect()
	Document

module.exports = Document

$ = require 'bling'
{db} = require './db'

createObjectId = -> db.ObjectId.createPk()

classes = {}

Document = (collection, doc_opts) ->
	doc_opts = $.extend {
		timeout: 1000
		collection: collection
		ns: undefined
	}, doc_opts
	return classes[doc_opts.collection] or= class InnerClass

		log = $.logger "[#{doc_opts.collection}]"

		joins = $ [
			[ 'ready', null, null ] # during saves, detach but dont save it
		]

		# the default constructor gets used to build instances,
		# given a result document from the database
		constructor: (props) ->
			$.extend @, props, # add the database fields to this instance
				ready: $.Promise() # and add a promise that indicates completion of all joins
			@_id ?= createObjectId()
			progress = $.Progress 1 + joins.length
			fail_or = (f) -> (err, result) ->
				if err then return progress.reject err
				else f(result)
			for join in joins then do (join) =>
				[name, coll, type] = join
				if not coll?
					progress.finish(1)
				klass = classes[coll] # the wrapper class for objects from this collection
				coll = db(doc_opts.ns).collection(coll)
				switch type
					when 'array'
						query = { parent: @_id }
						fields = { }
						sort = { index: 1 }
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
						query = { parent: @_id }
						coll.findOne(query).wait fail_or (item) =>
							@[name] = if item? and klass then construct klass, item else item
							progress.finish(1)
			progress.finish(1)
			progress.wait (err) =>
				if err then @ready.reject err
				else @ready.resolve @

		# the static method that is most commonly used to
		# access documents.
		InnerClass.getOrCreate = (query, cb) ->
			klass = @
			p = $.Promise()
			if $.is 'function', cb
				p.wait cb
			fail_or = (f) -> (e, r) ->
				if e then return p.reject(e)
				try f(r) catch err then p.reject(err)
				null
			db().collection(collection).findOne(query).wait fail_or (result) ->
				if result? then new klass(result).ready.wait p.handler
				else new klass(query).save().wait p.handler
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
			p = $.Promise()
			if $.is 'function', $(args).last()
				p.wait args.pop()
			timer = $.delay doc_opts.timeout, -> p.reject('timeout')
			# $.log "[o] starting op:", _op, "(",args,") on collection", doc_opts.collection
			db(doc_opts.ns).collection(doc_opts.collection)[_op](args...).wait (err, result) ->
				timer.cancel()
				# $.log "[o] finished op:", _op, err, result, p.promiseId
				switch
					when err then p.reject(err)
					when expect_result and not result? then p.reject "no result"
					else
						p.resolve construct klass, result
				null
			p

		$.extend InnerClass,
			count:   o 'count'
			findOne: o 'findOne', true
			update:  o 'update'
			remove:  o 'remove'
			index:   o 'ensureIndex'
			# save:    o 'save' # not join safe at the moment
			unique: (keys) -> @index keys, { unique: true, dropDups: true }
			join:   (name, coll, type = 'single') ->
				joins.push [name, coll, type]
				# make sure the join query will be indexed
				coll = db(doc_opts.ns).collection(coll)
				switch type
					when 'array'  then coll.ensureIndex { parent: 1, index: 1 }
					when 'object' then coll.ensureIndex { parent: 1 }, {unique: true}
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
						# $.log "[oo] starting op:", _op, "on cursor", cursor.cursorId.toString()
						cursor[_op] fail_or cb, (result) ->
							# $.log "[oo] finished op:", _op, result
							kursor.length = cursor.totalNumberOfRecords
							kursor.position += 1
							try touch? kursor, result
							if result? then finish cb, result
							else unless swallow then cb "no result", null
							else null
				# Return a fake cursor that yields the right type
				length:     0
				position:   0
				nextObject: oo 'nextObject', false
				each:       oo 'each',       true
				toArray:    oo 'toArray',    false, (kursor) -> kursor.position = kursor.length

		# save should be recursive
		# for every join on this document,
		# detach and save any joined items
		# then save self and re-attach items
		save: (cb) ->
			save_log = $.logger "save(#{@name})"
			try return p = $.Promise().then (self) -> self.ready.resolve self
			finally @ready.then (self) ->
				self.ready.reset()
				if cb then self.ready.wait cb
				detached = Object.create null
				do nextJoin = (j = 0) ->
					if j >= joins.length
						# save_log "done saving all joins, saving self...", self, doc_opts.ns, doc_opts.collection
						return db(doc_opts.ns).collection(doc_opts.collection).save(self).wait (err) ->
							if err then p.reject err
							else p.resolve $.extend self, detached
					[name, coll, type] = joins[j]
					do (name, coll, type) ->
						switch type
							when 'object'
								# save_log "join",j,"saving",name, self[name]
								if not self[name]?
									nextJoin j + 1
								else
									self[name].parent = self._id
									self[name].save (err) ->
										detached[name] = self[name]
										self[name] = self[name]._id
										nextJoin j + 1
							when 'array'
								a = self[name]
								detached[name] = new Array(a.length)
								do nextItem = (i = 0) ->
									if i >= a.length
										return nextJoin j + 1
									# save_log "join",j,"saving",name,'index',i
									a[i].parent = self._id
									a[i].save (err) ->
										detached[name][i] = a[i]
										a[i] = a[i]._id
										nextItem i + 1
							when null
								# save_log "join",j,"detaching",name, self.name
								detached[name] = self[name]
								delete self[name]
								nextJoin j + 1
						null
					null



		remove: ->
			p = $.Progress(1)
			@ready.then (self) =>
				log "Removing", @_id, "from", doc_opts.collection
				p.include db(doc_opts.ns).collection(doc_opts.collection).remove( _id: @_id )
				for join in joins then do (join) =>
					[name, coll, type] = join
					log "Removing joined data from", coll, "query:", { parent: @_id }
					p.include db(doc_opts.ns).collection(coll).remove( { parent: @_id }, { multi: true } )
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

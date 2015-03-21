$ = require 'bling'
{db} = require './db'

classes = {}

Document = (collection, doc_opts) ->
	doc_opts = $.extend {
		timeout: 1000
		collection: collection
		ns: undefined
	}, doc_opts
	return classes[doc_opts.collection] = class InnerClass

		log = $.logger "[#{doc_opts.collection}]"

		joins = [ ]

		# the default constructor gets used to build instances,
		# given a result document from the database
		constructor: (props) ->
			$.extend @, props, # add the database fields to this instance
				ready: $.Promise() # and add a promise that indicates completion of all joins
			progress = $.Progress(1 + joins.length)
			fail_or = (f) ->
				(err, result) ->
					if err then return progress.reject err
					else f(result)
			for join in joins then do (join) =>
				[name, coll, findOp] = join
				klass = classes[coll] # the wrapper class for objects from this collection
				coll = db(doc_opts.ns).collection(coll)
				switch findOp
					when 'multiple','multi','all'
						query = { doc_id: @_id }
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
					when 'single','one','exact'
						query = { doc_id: @_id }
						coll.findOne(query).wait fail_or (item) =>
							@[name] = if item? and klass then inherit klass, item else item
							progress.finish(1)
			progress.finish(1)
			progress.wait (err) =>
				if err then @ready.reject err
				else @ready.resolve @

		# the static method that is most commonly used to
		# access documents.
		InnerClass.getOrCreate = (query) ->
			klass = @
			p = $.Promise()
			fail_or = (f) -> (e, r) ->
				if e then return p.reject(e)
				try f(r) catch err then p.reject(err)
				null
			db().collection(collection).findOne(query).wait fail_or (result) ->
				if result? then new klass(result).ready.wait p.handler
				else new klass(query).save().wait p.handler
			p

		# make all the stuff inherit from a type, as much as possible; in-place
		inherit = (klass, stuff) ->
			stuff = switch $.type stuff
				when "object" then new klass stuff
				when "array","bling"
					stuff.map (i) -> inherit klass, i
				else stuff

		# o wraps a db operation to do class-mapping on its output,
		# e.g. MyDocument.findOne(query) searches the right collection,
		# and returns MyDocument objects. MyDocument.find(query)
		# returns a cursor that yields MyDocuments.
		o = (_op, expect_result=false) -> (args...) ->
			klass = @
			p = $.Promise()
			timer = $.delay doc_opts.timeout, -> p.reject('timeout')
			# $.log "[o] starting op:", _op, "(",args,") on collection", doc_opts.collection
			db(doc_opts.ns).collection(doc_opts.collection)[_op](args...).wait (err, result) ->
				timer.cancel()
				# $.log "[o] finished op:", _op, err, result, p.promiseId
				switch
					when err then p.reject(err)
					when expect_result and not result? then p.reject "no result"
					when typeof result in ['string','number']
						p.resolve result
					else
						p.resolve new klass result
				null
			p

		$.extend InnerClass,
			count:   o 'count'
			findOne: o 'findOne', true
			update:  o 'update'
			remove:  o 'remove'
			index:   o 'ensureIndex'
			save:    o 'save'
			unique: (keys) -> @index keys, { unique: true, dropDups: true }
			join:   (name, coll, findOp = 'single') ->
				joins.push [name, coll, findOp]
				switch findOp
					when 'multiple','multi','all' then db(doc_opts.ns).collection(coll).ensureIndex( doc_id: 1, index: 1 )
					when 'single','one','exact' then db(doc_opts.ns).collection(coll).ensureIndex( {doc_id: 1}, { unique: true } )
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
					return cb(e) if e
					try f(r) catch err then cb(err)
				finish = (cb, obj) ->
					cb null, inherit(klass, obj)
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

		save: ->
			p = $.Promise()
			@ready.then (self) ->
				detached = Object.create null
				to_save = $(joins).map (join) ->
					[name, coll, findOp] = join
					# detach all the joined objects (so we don't save them inline)
					detached[name] = self[name]
					self[name] = null
					# queue up all the items to be saved
					[ coll, detached[name] ]
				do_save = (_id) ->
					$.Promise.compose( save_promises = to_save.map (pair) ->
						[ coll, obj ] = pair
						coll = db(doc_opts.ns).collection(coll)
						q = if $.is 'array', obj
							$.Promise.compose( coll.save($.extend doc, {doc_id:_id, index:i}) for doc,i in obj )
						else
							(coll.save $.extend obj, doc_id: _id)
					).wait (err, saved) ->
						for k,v of detached
							self[k] = v
						p.resolve(self)
				if not self._id
					db(doc_opts.ns).collection(doc_opts.collection).save(self).wait (err, saved) ->
						if err then p.reject err
						else do_save(self._id = saved._id)
				else
					to_save.unshift [ doc_opts.collection, self ]
					do_save(self._id)
			p

		remove: ->
			p = $.Progress(1)
			@ready.then (self) =>
				log "Removing", collection, @_id
				p.include db(doc_opts.ns).collection(doc_opts.collection).remove( _id: @_id )
				for join in joins then do (join) =>
					[name, coll, findOp] = join
					log "Removing from",coll,"query:", { doc_id: @_id }
					p.include db(doc_opts.ns).collection(coll).remove( { doc_id: @_id }, { multi: true } )
				p.finish(1)
			p.on 'progress', (cur, max) ->
				log "Removed", cur, max
			p

Document.connect = (args...) ->
	db.connect args...
	Document

Document.disconnect = ->
	db.disconnect()
	Document

module.exports = Document

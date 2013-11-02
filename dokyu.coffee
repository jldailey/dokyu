$ = require 'bling'
{db} = require './db'

Document = (collection, doc_opts) ->
	doc_opts = $.extend {
		timeout: 1000
		collection: collection
	}, doc_opts
	return class InnerDocument

		constructor: (props) -> $.extend @, props

		InnerDocument.getOrCreate = (query) ->
			klass = @
			try p = $.Promise()
			finally
				fail_or = (f) -> (e, r) ->
					return p.fail(e) if e
					try f(r) catch err then p.fail(err)
				db().collection(collection).findOne(query).wait fail_or (result) ->
					if result? then p.finish new klass result
					else new klass(query).save().wait fail_or p.finish

		# make all the stuff inherit from a type, as much as possible; in-place
		inherit = (klass, stuff) ->
			return switch $.type stuff
				when "object" then new klass(stuff)
				when "array","bling"
					for x,i in stuff
						stuff[i] = inherit klass, stuff[i]
					stuff
				else stuff

		# o wraps a db operation to do class-mapping on its output,
		# e.g. MyDocument.findOne(query) searches the right collection,
		# and returns MyDocument objects. MyDocument.find(query)
		# returns a cursor that yields MyDocuments.
		o = (_op, no_result=false) -> (args...) ->
			klass = @
			try p = $.Promise() # .wait (err, result) -> $.log "promise to #{_op} on #{collection} finished, id:", p.promiseId
			finally
				to = $.delay doc_opts.timeout, -> p.fail('timeout')
				db().collection(collection)[_op](args...).wait (err, result) ->
					to.cancel()
					return p.fail(err) if err
					return p.finish inherit klass, result if result?
					if no_result then p.fail "no result"

		$.extend InnerDocument,
			count:   o 'count'
			findOne: o 'findOne', true
			update:  o 'update'
			remove:  o 'remove'
			save:    o 'save'
			index:   o 'ensureIndex'
			unique: (keys) -> @index keys, { unique: true }
			# set the default query timeout
			timeout: (ms) ->
				try doc_opts.timeout = parseInt ms, 10
				catch err then doc_opts.timeout = 1000
				@
			# find creates a fake cursor
			find: (query = {}, opts = {}) ->
				klass = @
				cursor_promise = db().collection(collection).find(query, opts)
				fail_or = (cb, f) -> (e,r) ->
					return cb(e) if e
					try f(r) catch err then cb(err)
				finish = (cb, obj) ->
					if (i = inherit klass, obj)? then cb(null, i)
				oo = (_op, swallow, touch) -> (args...) ->
					kursor = @
					cb = args.pop()
					cursor_promise.wait fail_or cb, (cursor) ->
						cursor[_op] fail_or cb, (result) ->
							kursor.length = cursor.totalNumberOfRecords
							kursor.position += 1
							touch? kursor, result
							if result? then finish cb, result
							else unless swallow then cb "no result", null
							else null
				# Return a fake cursor that yields the right type
				length: 0
				position: 0
				nextObject: oo 'nextObject', false
				each:       oo 'each',       true
				toArray:    oo 'toArray',    false, (kursor) -> kursor.position = kursor.length

		save: ->
			db().collection(collection).save(@).wait (err, saved) =>
				try @_id = saved._id

		remove: ->
			db().collection(collection).remove( _id: @_id )

Document.connect = (args...) ->
	db.connect args...
	Document

module.exports= Document

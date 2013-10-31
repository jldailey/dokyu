$ = require 'bling'
{db} = require './db'

Document = (collection, doc_opts) ->
	doc_opts = $.extend {
		timeout: 1000
		collection: collection
	}, doc_opts
	return class Document

		constructor: (props) -> $.extend @, props

		Document.getOrCreate = (query) ->
			klass = @
			try p = $.Promise()
			finally
				fail_or = (f) -> (e, r) -> if e then p.fail(e) else f r
				db().collection(collection).findOne(query).wait fail_or (result) ->
					if result? then p.finish new klass result
					else new klass(query).save fail_or p.finish

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
		o = (_op) -> (args...) ->
			klass = @
			try p = $.Promise()
			finally
				to = $.delay doc_opts.timeout, -> p.fail('timeout')
				db().collection(collection)[_op](args...).wait (err, result) ->
					to.cancel()
					return p.fail(err) if err
					return p.fail("no result") unless result?
					p.finish inherit klass, result

		$.extend Document,
			count:   o 'count'
			findOne: o 'findOne'
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
				fail_or = (cb, f) -> (e,r) -> if e then cb(e) else f r
				finish = (cb, obj) ->
					if (i = inherit klass, obj)? then cb(null, i)
					else cb("no result")
				oo = (_op, touch) -> (args...) ->
					kursor = @
					cb = args.pop()
					cursor_promise.wait fail_or cb, (cursor) ->
						cursor[_op] fail_or cb, (result) ->
							kursor.length = cursor.totalNumberOfRecords
							kursor.position += 1
							touch? kursor, result
							finish cb, result
				# Return a fake cursor that yields the right type
				length: 0
				position: 0
				nextObject: oo 'nextObject'
				each:       oo 'each'
				toArray:    oo 'toArray', (kursor) -> kursor.position = kursor.length
					


		save: ->
			db().collection(collection).save(@).wait (err, saved) =>
				try @_id = saved._id

		remove: ->
			db().collection(collection).remove( _id: @_id )

Document.connect = (args...) -> db.connect args...

module.exports= Document

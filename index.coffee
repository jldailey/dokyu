{db} = require './db'

Document = (collection) ->
	class Document
		
		@getOrCreate = (query) ->
			q = $.Promise()
			klass = @
			db().collection(collection).findOne(query).wait (err, result) ->
				if err then q.fail err
				else q.finish new klass result ? query
			q

		# make all the stuff inherit from a type, as much as possible
		inherit = (klass, stuff) ->
			return switch $.type stuff
				when "object" then new klass(stuff)
				when "array","bling"
					for x,i in stuff
						stuff[i] = inherit klass, stuff[i]
					stuff
				else stuff

		# wrap up a bunch of db operations as type-wrapped
		# class operations, e.g. MyDocument.findOne(query)
		# searches the right collection, and returns MyDocument objects.
		# MyDocument.find(query) returns a cursor that yields MyDocuments.
		wrapped = (_op) ->
			(args...) ->
				q = $.Promise()
				# $.log "Calling #{_op} on #{collection}..."
				timeout = $.delay 1000, -> q.fail('timeout')
				db().collection(collection)[_op](args...).wait (err, result) =>
					timeout.cancel()
					return q.fail(err) if err
					return q.fail("no result") unless result?
					q.finish inherit @, result
				q
					
		$.extend @,
			count:   wrapped 'count'
			findOne: wrapped 'findOne'
			update:  wrapped 'update'
			remove:  wrapped 'remove'
			save:    wrapped 'save'
			index:   wrapped 'ensureIndex'
			unique: (keys) -> @index keys, { unique: true }
			find: (query = {}, opts = {}) ->
				klass = @
				cursor_promise = db().collection(collection).find(query, opts)
				# A cursor proxy that yields the right sub-type
				nextObject: (args...) ->
					cb = args.pop()
					opts = if args.length then args.pop() else {}
					cursor_promise.wait (err, cursor) ->
						return cb(err) if err
						cursor.nextObject opts, (err, obj) ->
							return cb(err) if err
							return cb(null, i) if (i = inherit klass, obj)?
				toArray: (cb) ->
					cursor_promise.wait (err, cursor) ->
						return cb(err) if err
						cursor.toArray (err, items) ->
							return cb(err) if err
							return cb(null, i) if (i = inherit klass, items)?
				each: (cb) ->
					cursor_promise.wait (err, cursor) ->
						return cb(err) if err
						cursor.each (err, item) ->
							return cb(err) if err
							return cb(null, i) if (i = inherit klass, item)?

		save: ->
			db().collection(collection).save(@).wait (err, saved) =>
				try @_id = saved._id

Document.connect = (args...) -> db.connect args...

modules.exports = Document

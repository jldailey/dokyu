{db} = require './db'

Document = (collection) ->
	class Document
		
		@getOrCreate = (query) ->
			q = $.Promise()
			klass = @
			db().collection(collection).findOne(query).wait (err, result) ->
				if err then q.fail err
				else if result?
					q.finish new klass result
				else
					new klass(query).save (err, saved) ->
						if err then q.fail err
						else q.finish saved
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
				klass = @
				q = $.Promise()
				# $.log "Calling #{_op} on #{collection}..."
				timeout = $.delay 1000, -> q.fail('timeout')
				db().collection(collection)[_op](args...).wait (err, result) ->
					timeout.cancel()
					return q.fail(err) if err
					return q.fail("no result") unless result?
					q.finish inherit klass, result
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
				length: 0
				position: 0
				nextObject: (args...) ->
					kursor = @
					cb = args.pop()
					opts = if args.length then args.pop() else {}
					cursor_promise.wait (err, cursor) ->
						return cb(err) if err
						cursor.nextObject opts, (err, obj) ->
							return cb(err) if err
							kursor.length = cursor.totalNumberOfRecords
							kursor.position += 1
							return cb(null, i) if (i = inherit klass, obj)?
				toArray: (cb) ->
					kursor = @
					cursor_promise.wait (err, cursor) ->
						return cb(err) if err
						cursor.toArray (err, items) ->
							return cb(err) if err
							kursor.position \
								= kursor.length \
								= cursor.totalNumberOfRecords
							return cb(null, i) if (i = inherit klass, items)?
				each: (cb) ->
					kursor = @
					cursor_promise.wait (err, cursor) ->
						return cb(err) if err
						cursor.each (err, item) ->
							return cb(err) if err
							kursor.length = cursor.totalNumberOfRecords
							kursor.position += 1
							return cb(null, i) if (i = inherit klass, item)?

		save: ->
			db().collection(collection).save(@).wait (err, saved) =>
				try @_id = saved._id

		remove: ->
			db().collection(collection).remove( _id: @_id )

Document.connect = (args...) -> db.connect args...

module.exports = Document

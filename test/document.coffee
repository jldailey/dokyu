Document = require "../index"

describe "Document", ->

	it "can set a default connection", ->
		Document.connect "mongodb://localhost:27017/document_test"
	
	it "can set namespaced connections", ->
		Document.connect "beta", "mongodb://localhost:27017/beta"

	describe "sub-classing", ->

		it "puts documents in a collection", (done) ->
			class BasicDocument extends Document("basic")
				constructor: ->

			new BasicDocument( magic: "marker" ).save().wait (err, saved) ->
				assert '_id' of saved, "_id of saved"
				assert.equal saved.constructor, BasicDocument
				assert.equal saved.magic, "marker"
				done()

		it "allows indexing", (done) ->
			class Unique extends Document("uniques")
				@unique { special: 1 }
				constructor: ->

			$.Promise.compose(
				new Unique( special: "one" ).save()
				new Unique( special: "two" ).save()
				new Unique( special: "one" ).save()
			).wait (err) ->
				# err should be a duplicate key error from the "one"s
				assert.equal err.code, "E11000"
				done()

		it "honors the constructor", (done) ->
			class Constructed extends Document("constructs")
				constructor: (props) ->
					@jazz = -> "hands!"
					$.extend @, props

			Constructed.getOrCreate( name: "Jesse" ).wait (err, doc) ->
				assert.equal doc.constructor, Constructed
				assert.equal doc.name, "Jesse"
				assert.equal doc.jazz(), "hands!"
				done()


		'''
				
		class BlogPost extends Document("blogposts")
			@unique { title: 1 }
			@index { author: 1 }

			@defaults = {
				title: "Untitled"
				author: "Anonymous"
				body: ""
				views: 0
			}

			constructor: (props) ->
				$.extend @, BlogPost.defaults, props

			toLine: -> "#{@title} by #{@author} (#{@views} views)"
			toString: ->
				@views += 1
				"""
					#{@title}
					---------
					#{@body}
					-- by #{@author} (#{@views} views)
				"""

		BlogPost.remove( title: /^First/ ).wait (err, removed) ->
			$.log "removed:", err ? removed
			BlogPost.getOrCreate( title: "Second Article" ).wait (err, doc) ->
				return $.log(err) if err
				try $.log "type:", $.type(doc), doc.constructor.name
				doc.author = "Jane Doe"
				doc.body = "This is another article from a totally different perspective."
				doc.save().wait (err, saved) ->
					return $.log(err) if err
					BlogPost.findOne(author: "Jane Doe").wait (err, doc) ->
						return $.log(err) if err
						console.log doc.toString()

		new BlogPost( title: "Untitled #1", body: "We Are Legion." ).save()

		BlogPost.count( author: "Anonymous" ).wait (err, count) ->
			$.log "Article count:", count
		
		BlogPost.find().nextObject (err, obj) ->
			$.log "The first post:", obj?.toLine()
		
		i = 0
		BlogPost.find( ).each (err, obj) ->
			console.log "#{++i}.", obj?.toLine()
		'''


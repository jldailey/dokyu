Document = require "../dokyu"
assert = require "assert"
$ = require 'bling'

describe "Document", ->

	Document.connect "mongodb://localhost:27017/document_test"
	
	it ".connect(ns, url)", ->
		Document.connect "beta", "mongodb://localhost:27017/beta"

	describe "class extends Document(collection)", ->

		it "stores objects in a collection", (done) ->
			class BasicDocument extends Document("basic")

			new BasicDocument( magic: "marker" ).save().wait (err, saved) ->
				assert '_id' of saved, "_id of saved"
				assert.equal saved.constructor, BasicDocument
				assert.equal saved.magic, "marker"
				done()

		it ".unique, .index", (done) ->
			class Unique extends Document("uniques")
				@unique { special: 1 }

			$.Promise.compose(
				new Unique( special: "one" ).save()
				new Unique( special: "two" ).save()
				new Unique( special: "one" ).save()
			).wait (err) ->
				# err should be a duplicate key error from the "one"s
				assert.equal err.code, 11000
				done()

		describe "uses the constructor", ->
			class Constructed extends Document("constructs")
				constructor: (props) ->
					super(props)
					@jazz = -> "hands!"
			it "when saving objects", (done) ->
				new Constructed( name: "Jesse" ).save().wait (err, doc) ->
					throw err if err
					assert.equal doc.constructor, Constructed
					assert.equal doc.name, "Jesse"
					assert.equal doc.jazz(), "hands!"
					done()
			it "when fetching objects", (done) ->
				Constructed.findOne( name: "Jesse" ).wait (err, doc) ->
					throw err if err
					assert.equal doc.constructor, Constructed
					assert.equal doc.name, "Jesse"
					assert.equal doc.jazz(), "hands!"
					done()

		describe "static database operations:", ->
			it "count", (done) ->
				class Counted extends Document("counted")
					@unique { name: 1 }

				$.Promise.compose(
					Counted.getOrCreate( name: "one" )
					Counted.getOrCreate( name: "two" )
					Counted.getOrCreate( name: "three" )
				).wait (err) ->
					assert.equal err, null
					Counted.count().wait (err, count) ->
						assert.equal count, 3
						done()

			it "findOne", (done) ->
				class FindOne extends Document("findOne")

				$.Promise.compose(
					FindOne.getOrCreate( name: "a" )
					FindOne.getOrCreate( name: "b" )
					FindOne.getOrCreate( name: "c" )
				).wait (err) ->
					assert.equal err, null
					$.Promise.compose(
						FindOne.findOne().wait (err, one) ->
							assert.equal err, null
							assert one.name in [ "a","b","c" ]
						FindOne.findOne( name: "a" ).wait (err, one) ->
							assert.equal err, null
							assert.equal one.name, "a"
					).wait (err) ->
						assert.equal err, null
						done()

			it "update", (done) ->
				class Update extends Document("updates")

				Update.remove({}).wait (err, result) ->
					$.Promise.compose(
						new Update( name: "a" ).save()
						new Update( name: "b" ).save()
						new Update( name: "c" ).save()
					).wait (err) ->
						assert.equal err, null
						Update.update({name: "a"}, { $set: { magic: "marker" } }).wait (err, result) ->
							assert.equal err, null
							Update.findOne( name: "a" ).wait (err, result) ->
								assert.equal err, null
								assert.equal result.magic, "marker"
								done()

			describe "save", ->
				class Saved extends Document("saves")

				it "MyDocument.save(obj)", (done) ->
					new Saved( name: "a" ).save().wait (err, saved) ->
						assert.equal err, null
						assert.equal saved.constructor, Saved
						assert.equal saved.name, "a"
						Saved.remove( name: "a" ).wait (err, removed) ->
							assert.equal err, null
							assert.equal removed, 1
							done()

				it "MyDocument::save()", (done) ->
					b = new Saved( name: "b" )
					Saved.save(b).wait (err, saved) ->
						assert.equal err, null
						assert.equal saved._id, b._id # this asserts both that saved is the right object,
						# and that the _id is written back to b in-place
						done()

			it "remove"
			it "index", -> # tested elsewhere
			it "unique", -> # tested elsewhere
			describe "find", ->
				class Hay extends Document("haystack")
					@unique { name: 1 }

				it "Cursor::nextObject", (done) ->
					Hay.remove({}).wait (err) ->
						assert.equal err, null
						$.Promise.compose(
							new Hay( name: "needle" ).save(),
							(new Hay( name: $.random.string 32 ).save() for _ in [0...10])...
						).wait (err) ->
							assert.equal err, null
							cursor = Hay.find( name: "needle" )
							assert 'nextObject' of cursor
							cursor.nextObject (err, obj) ->
								assert.equal err, null
								done()

				it "Cursor::each", (done) ->
					Hay.remove({}).wait (err) ->
						assert.equal err, null
						$.Promise.compose(
							new Hay( name: "needle" ).save(),
							(new Hay( name: $.random.string 32 ).save() for _ in [0...10])...
						).wait (err) ->
							assert.equal err, null
							cursor = Hay.find( name: /^n/ )
							cursor.each (err, item) ->
								assert.equal err, null
								assert /^n/.test item.name
								if cursor.position is cursor.length
									done()

				it "Cursor::toArray", (done) ->
					Hay.remove({}).wait (err) ->
						assert.equal err, null
						$.Promise.compose(
							new Hay( name: "needle" ).save(),
							(new Hay( name: $.random.string 32 ).save() for _ in [0...10])...
						).wait (err) ->
							assert.equal err, null
							cursor = Hay.find( name: /^n/ )
							cursor.toArray (err, items) ->
								assert items.length > 0
								for item in items
									assert /^n/.test item.name
								done()

Document = require "../lib/dokyu"
assert = require "assert"
$ = require 'bling'

describe "Document", ->

	Document.connect "mongodb://localhost:27017/document_test"

	describe ".connect", ->
		it "supports namespaced connections", ->
			Document.connect "beta", "mongodb://localhost:27017/beta"

	describe "class extends Document(collection)", ->

		it "stores objects in a collection", (done) ->
			class BasicDocument extends Document("basic")

			new BasicDocument( magic: "marker" ).save().wait (err, saved) ->
				assert '_id' of saved, "_id of saved"
				assert.equal saved.constructor, BasicDocument
				assert.equal saved.magic, "marker"
				done()

		describe ".unique, .index", ->
			it "ensures indexes and constraints", (done) ->
				class Unique extends Document("uniques")
					@unique { special: 1 }

				p = Unique.remove({}).wait (err) ->
					if err then return done err
					new Unique( special: "one" ).save().wait (err) ->
						if err then return done err
						new Unique( special: "two" ).save().wait (err) ->
							if err then return done err
							new Unique( special: "one" ).save().wait (err) ->
								# err should be a duplicate key error from the "one"s
								assert.equal err?.code, 11000
								done()

		describe "uses the constructor", ->
			it "when saving objects", (done) ->
				class Constructed extends Document("constructs")
					constructor: (props) ->
						super(props)
						@jazz = -> "hands!"
				new Constructed( name: "Jesse" ).save().wait (err, doc) ->
					throw err if err
					assert.equal doc.constructor, Constructed
					assert.equal doc.name, "Jesse"
					assert.equal doc.jazz(), "hands!"
					done()
			it "when fetching objects", (done) ->
				class Constructed extends Document("constructs")
					constructor: (props) ->
						super(props)
						@jazz = -> "hands!"
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
						FindOne.findOne( name: "d" ).wait (err) ->
							assert.equal err.message, "no result"
					).wait (err) ->
						assert.equal err.message, "no result"
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

				it "MyDocument.save(obj)", (done) ->
					class Saved extends Document("saves")
					new Saved( name: "a" ).save().wait (err, saved) ->
						assert.equal err, null
						assert.equal saved.constructor, Saved
						assert.equal saved.name, "a"
						Saved.remove( name: "a" ).wait (err, removed) ->
							assert.equal err, null
							assert.equal removed, 1
							done()

				it "MyDocument::save()", (done) ->
					class Saved extends Document("saves")
					b = new Saved( name: "b" )
					Saved.save(b).wait (err, saved) ->
						assert.equal err, null
						assert.equal saved._id, b._id # this asserts both that saved is the right object,
						# and that the _id is written back to b in-place
						done()

			it "remove", (done) ->
				class Remove extends Document("removed")

				$.Promise.compose(
					(new Remove( name: "a" + $.random.string 16 ).save() for _ in [0...3])...
				).wait (err) ->
					assert.equal err, null
					Remove.remove( name: /^a/ ).wait (err, removed) ->
						assert.equal err, null
						assert.equal removed, 3
						Remove.count({}).wait (err, count) ->
							assert.equal err, null
							assert.equal count, 0
							done()

			it "index", -> # tested elsewhere
			it "unique", -> # tested elsewhere
			describe "find", ->

				it "Cursor::nextObject", (done) ->
					class Hay extends Document("haystack")
						@unique { name: 1 }
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
								assert.equal obj.name, "needle"
								done()

				it "Cursor::each", (done) ->
					class Hay extends Document("haystack")
						@unique { name: 1 }
					Hay.remove({}).wait (err) ->
						assert.equal err, null
						$.Promise.compose(
							new Hay( name: "needle" ).save(),
							(new Hay( name: $.random.string 32 ).save() for _ in [0...22])...
						).wait (err) ->
							assert.equal err, null
							cursor = Hay.find( name: /^n/ )
							cursor.each (err, item) ->
								assert.equal err, null
								assert /^n/.test item.name
								if cursor.position is cursor.length
									done()

				it "Cursor::toArray", (done) ->
					class Hay extends Document("haystack")
						@unique { name: 1 }
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

		describe "joins", ->
			it "lets one document come from two collections", (done) ->
				class A extends Document("As")
					@join 'b', 'Bs', 'one'

				class B extends Document("Bs")
					constructor: (@name) ->

				a = new A()
				a.ready.then ->
					a.b = new B("Groot")
					assert.equal a.b.name, "Groot"
					a.save().wait (err) ->
						assert.equal err, null
						assert.equal a.b?.name, "Groot"
						done()

			it "lets you join arrays onto a document", (done) ->
				class AA extends Document("AAs")
					@join 'b', 'BBs', 'all'

				class BB extends Document("BBs")

				a = new AA
				a.ready.then ->
					a.b.push new BB name: "Groot"
					a.b.push new BB name: "Broot"
					assert.equal a.b[0].name, "Groot"
					assert.equal a.b[1].name, "Broot"
					assert.equal $(a.b).select("_id").filter(undefined, false).length, 0
					a.save().wait (err) ->
						assert.equal err, null
						assert.equal a.b?.length, 2
						assert.equal $(a.b).select("_id").filter(undefined, false).length, 2
						assert.deepEqual $(a.b).select("doc_id.toString").call(), $(a, a).select("_id.toString").call()
						AA.getOrCreate({ _id: a._id }).wait (err, doc) ->
							assert.equal err, null
							assert.equal doc.b?.length, 2
							assert.equal doc.b[0].name, "Groot"
							assert.equal doc.b[1].name, "Broot"
							assert.equal $(doc.b).select("_id").filter(undefined, false).length, 2
							assert.deepEqual $(doc.b).select("doc_id.toString").call(), $(a, a).select("_id.toString").call()
							done()

Document = require "../lib/dokyu"
assert = require "assert"
$ = require 'bling'

test_log = $.logger "TEST:"

describe "Document", ->

	Document.connect "mongodb://localhost:27017/document_test", (err) ->

	describe ".connect", ->
		it "supports namespaced connections", ->
			Document.connect "beta", "mongodb://localhost:27017/beta", (err) ->

	describe "class extends Document(collection)", ->
		it "is an EventEmitter", ->
			class BasicDocument extends Document("basic")
			assert.equal $.type(new BasicDocument().on), 'function'

		it "takes properties given to the constructor", ->
			class BasicDocument extends Document("basic")

			b = new BasicDocument name: "magic"
			assert.equal b.name, "magic"

		it "stores objects in a collection", (done) ->
			class BasicDocument extends Document("basic")

			new BasicDocument( magic: "marker" ).save().wait (err, saved) ->
				assert.equal err, null
				assert saved?
				assert '_id' of saved, "_id of saved"
				assert.equal saved.constructor, BasicDocument
				assert.equal saved.magic, "marker"
				new BasicDocument( magic: "flute" ).save().wait (err, saved) ->
					assert.equal err, null
					assert saved?
					assert '_id' of saved, "_id of saved"
					assert.equal saved.constructor, BasicDocument
					assert.equal saved.magic, "flute"
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

describe "A Complete Example", ->
	it "works", (done) ->
		done()


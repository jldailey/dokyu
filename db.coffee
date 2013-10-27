MongoClient = require('mongodb').MongoClient
$ = require 'bling'

$.type.register 'ObjectId', {
	is: (o) -> o?._bsontype is "ObjectID"
	string: (o) -> o.toHexString()
	repr: (o) -> "ObjectId('#{o.toHexString()}')"
}

dbs =
	test: "mongodb://localhost:27017/test"


exports.db = db = (db_name = "test" ) ->
	unless db_name of dbs
		throw new Error "unknown db_name (do you need to call db.register()?), known dbs: #{Object.keys(dbs).join()}"
	p = $.Promise()
	MongoClient.connect url = dbs[db_name], (err, db) ->
		return p.fail(err) if err
		p.finish(db)
	$.extend p,
		collection: (_coll) ->
			wrapped = (_op) -> (args...) ->
				q = $.Promise()
				p.wait (err, db) ->
					return q.fail(err) if err
					db.collection(_coll)[_op] args..., (err, result) ->
						return q.fail(err) if err
						q.finish(result)
				q
			return {
				findOne: wrapped 'findOne'
				find: wrapped 'find'
				count: wrapped 'count'
				insert: wrapped 'insert'
				update: wrapped 'update'
				ensureIndex: wrapped 'ensureIndex'
			}
	p

db.register = (name, url) ->
	if name of url
		$.log "WARN: over-writing existing database name: #{name} was: #{dbs[name]} now: #{url}"
	dbs[name] = url

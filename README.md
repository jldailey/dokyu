dokyu
-----

A little ORM for mongodb: ```npm install dokyu```

Basic Usage
===========

```coffee

Document = require 'dokyu'

class MyDocument extends Document("my_collection")
  @unique { title: 1 }
  jazz: -> "hands!"

Document.connect "mongodb://..."

doc = new MyDocument( title: "Manifesto" )
doc.author = "Anonymous"
doc.save().wait ->
  MyDocument.getOrCreate( title: "Manifesto" ).wait (err, doc) ->
    doc.author # "Anonymous", from the database
    doc.jazz() # "hands!", from the prototype

```

API
===

Some short-hand notation: A 'Promise(err, x)' is a Promise you use with `.wait (err, x) ->`

* __Document.connect( [name], url )__

  The _url_ should be something like: ```"mongodb://localhost:27017/db_name"```.

  TODO: Any connection options supported by mongo can be given as URL params, ```"?safe=true&replSet=rs0"```

  TODO: The optional name is accepted, and creates a separate connection, but cannot yet be used.

* __Document(collection_name, [opts])__ →

  This creates a new class, suitable for sub-classing.
  
  The generated class is referred to as the __InnerDocument__.
  
  For instance, given `class Foo extends Document("foos")`,
  all instances of `Foo` will read/write to the `"foos"` collection,
  using whatever database you are connected to (see Document.connect).
  
  The optional __[opts]__ is a key/value object with two meaningful keys:
  - _opts.timeout_, in ms, for all operations on this collection.
  - _opts.collection_, over-rides the collection name in the first argument (a way to have a default and dynamic value)


* __MyDocument.count( query )__ → Promise(err, count)
  
  The `count` value is the number of documents matching the query.

  ```coffee
  MyDocument.count( query ).wait (err, count) ->
    assert typeof count is 'number'
  ```

* __MyDocument.findOne( query )__  → Promise(err, doc)
  
  The `doc` value is the first matching instance of MyDocument.

  ```coffee
  MyDocument.findOne( query ).wait (err, doc) ->
    doc.jazz() # "hands!"
  ```

* __MyDocument.find( query, opts )__ → Promise(err, cursor)

  The `cursor` given here is a special proxy cursor with a much simplified interface.
  - `length: 0`, the total number of records available to the cursor
  - `position: 0`, is incremented as you read from the cursor
  - `nextObject(cb)`, calls `cb(err, doc)` where doc is an instance of MyDocument.
  - `each(cb)`, calls `cb(err, doc)` for every result, each doc is an instance of MyDocument.
  - `toArray(cb)`, calls `cb(err, array)`, where array is full of the MyDocument instances found.

  
* __MyDocument.update( query, update, [ opts ] )__ → Promise(err, updated)

  The `updated` value is the number of documents updated.

* __MyDocument.save( doc )__ → Promise(err, saved)

  The `saved` value is the saved document (possibly with a new `_id` field).
  
* __MyDocument.remove( query )__ → Promise(err, removed)
  
  The `removed` value is the number of document removed.

* __MyDocument.index( obj, [ opts ] )__ → Promise(err)
  
  Calls `ensureIndex` on the underlying collection.

* __MyDocument.unique( obj )__ → Promise(err)

  Calls `ensureIndex( obj, { unique: true })` on the underlying collection.
  
* __MyDocument.timeout( ms )__ → chainable

  Sets the timeout for operations on this collection.


document.coffee
===============

A toy ORM for mongodb.

```coffee

Document = require 'document'

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
